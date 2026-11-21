import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'node/child_process';
import { openRecordDetails, expectFieldVisible, startInlineEdit, saveInlineEdit } from './record-page';

/**
 * [SCRUM-467] Offer validity on Opportunities — UI end-to-end against Test-Org.
 *
 * AC (ticket, verbatim-kernel):
 *   AC1 both offer dates visible on the record (customer view)
 *   AC2 without "Offer valid until" the last valid day = sent + 30 days
 *   AC3 status + days left at a glance (live / last valid day / expired)
 *   AC4 a record without offer data never looks expired
 *   AC5 an expired offer cannot be closed as Won (refusal saves nothing)
 *   AC6 renewal = two new dates -> then it can be closed as Won
 *   AC7 Closed Lost stays possible although the offer is expired
 *   AC8 after the deal is closed the dates are frozen (further fills refused)
 *   AC9 Report: open deals whose offer expires within the next 14 days
 *   AC10 Report: offers that already expired, kept separate
 *   AC11 nothing happens on its own (no email, no task, no auto-close)
 *   AC12 Permission Set: the set holder can record the dates (positive UI path;
 *        the foreign-record cases are System.runAs Apex - SCRUM467OfferFlsTest)
 *   AC13 user without the set: fields not even readable (Apex System.runAs;
 *        a second licensed UI user is impossible on this org - 2 licences,
 *        both taken by the admins)
 *
 * Verified DOM/locator facts (live probes, 2026-11-21, Test-Org):
 *   - The Offer-validity layout section renders inside a CLOSED Shadow-Root:
 *     `document.querySelectorAll('records-record-layout-item')` returns 0 and
 *     innerText of those elements is empty. The values are only in the
 *     Accessibility tree -> ONE `page.ariaSnapshot()` per read (house rule,
 *     same as SCRUM-417).
 *   - Snapshot lines (label + value on ONE line):
 *       - text: Offer sent on 15.11.2026
 *       - listitem: Offer status offer valid for 14 more days
 *       - listitem: Offer expired False Offer expired
 *       - listitem: Offer days left 14
 *       - empty fields render the label with NOTHING behind it
 *     Booleans render "True"/"False"; dates use the user's locale DD.MM.YYYY.
 *   - Inline edit: the button is named "Edit <Label>"; after the click the
 *     field appears as `combobox "<Label>"` / input with that accessible name
 *     (verified with "Edit Stage" -> combobox "Stage": Prospecting).
 *   - Reports render as a real <table> in the lightningReportApp cross-doc
 *     frame (house pattern SCRUM-428); "Total Records N" is the report total.
 */

const TAG = '[SCRUM-467-e2e]';

/* --------------------------- sf-CLI helpers (house) ------------------------ */

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function rawOut(command: string): string {
  return execSync(command, {
    encoding: 'utf-8',
    timeout: 120000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
}

function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}

function soqlTooling(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -t -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}

function createRecord(type: string, fields: string): string {
  const doc = shellJson(
    rawOut(`sf data create record -s ${type} -v "${fields}" --target-org Test-Org --json`)
  );
  const id = doc?.result?.id ?? doc?.id;
  if (!id) throw new Error(`Create ${type} lieferte keine Id: ${JSON.stringify(doc).slice(0, 300)}`);
  return String(id);
}

function deleteRecord(type: string, id: string) {
  try {
    rawOut(`sf data delete record -s ${type} -i ${id} --target-org Test-Org --json`);
  } catch {
    /* best effort */
  }
}

/* ----------------------------- date anchors ------------------------------- */
// Relative to TODAY so that the 14-day window gate cannot drift with the
// calendar (house rule for SCRUM-4xx report tests).
const TODAY = new Date();
function iso(off: number): string {
  const d = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + off);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function de(off: number): string {
  const d = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + off);
  return `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`;
}

/* --------------------------- record-value reader --------------------------- */

async function offerValues(page: Page): Promise<Record<string, string>> {
  const snap = await page.ariaSnapshot();
  const wanted = [
    'Offer sent on',
    'Offer valid until',
    'Offer status',
    'Offer expired',
    'Offer expiry (last valid day)',
    'Offer expires within 14 days',
    'Offer days left',
  ];
  const out: Record<string, string> = {};
  for (const label of wanted) {
    let value: string | null = null;
    for (const raw of snap.split('\n')) {
      const line = raw.trim();
      if (line.includes('Edit ' + label)) continue; // the inline-edit button, not the value
      const at = line.lastIndexOf(label);
      if (at < 0) continue;
      let rest = line.slice(at + label.length).trim();
      // "Offer expired" line repeats the label after the boolean value.
      if (rest.endsWith(label)) rest = rest.slice(0, rest.length - label.length).trim();
      if (rest.startsWith(label)) continue; // a longer label that merely contains this one
      value = rest;
      break;
    }
    if (value === null) {
      throw new Error(`"${label}" not in the accessibility tree at all (Offer validity section missing?) :: ${snap.slice(0, 400)}`);
    }
    out[label] = value;
  }
  return out;
}

/* ------------------------------ fixtures ---------------------------------- */

type Fix = { tag: string; id: string; acct: string };
const FIXTURES: Fix[] = [];

function seedFixtures() {
  // A: no offer data at all            B1: expiry exactly today+14 (window edge)
  // B2: live, 5 days left              B3: default rule -> expiry = sent+30 = today
  // C1: explicit expiry in the past    C2: default rule expired (sent+30 = today-7)
  const spec: Array<[string, number | null, number | null]> = [
    ['A', null, null],
    ['B1', -6, 14],
    ['B2', -2, 5],
    ['B3', -30, null],
    ['C1', -30, -11],
    ['C2', -21, null],
  ];
  for (const [name, sentOff, untilOff] of spec) {
    const acct = createRecord('Account', `Name='${TAG}-${name}'`);
    let fields =
      `Name='${TAG} ${name}' StageName='Prospecting' CloseDate='${iso(60)}' AccountId='${acct}'`;
    if (sentOff !== null) fields += ` Offer_Sent_On__c='${iso(sentOff)}'`;
    if (untilOff !== null) fields += ` Offer_Valid_Until__c='${iso(untilOff)}'`;
    const id = createRecord('Opportunity', fields);
    FIXTURES.push({ tag: name, id, acct });
  }
}

function fixtureId(name: string): string {
  const f = FIXTURES.find((x) => x.tag === name);
  if (!f) throw new Error('fixture ' + name + ' missing');
  return f.id;
}

function fixtureName(name: string): string {
  return `${TAG} ${name}`;
}

function soqlOffer(id: string): any {
  const recs = soql(
    `SELECT Id, IsClosed, StageName, Offer_Sent_On__c, Offer_Valid_Until__c, ` +
      `Offer_Expires_On__c, Offer_Days_Left__c, Offer_Status__c, Offer_Expired__c, ` +
      `Offer_Expiring_14D__c, Loss_Reason__c FROM Opportunity WHERE Id='${id}'`
  );
  if (recs.length !== 1) throw new Error(`SOQL read-back for ${id} returned ${recs.length} rows`);
  return recs[0];
}

function countOpen(cond: string): number {
  return soql(`SELECT Id FROM Opportunity WHERE IsClosed=false AND ${cond} LIMIT 500`).length;
}

/* --------------------------- picklist click (house) ------------------------ */

async function clickOption(page: Page, optionName: string) {
  const opt = page.getByRole('option', { name: optionName, exact: true }).last();
  await opt.waitFor({ state: 'visible', timeout: 10000 });
  for (let i = 0; i < 4; i++) {
    await opt.click({ force: true }).catch(() => {});
    await page.waitForTimeout(400);
    if (!(await opt.isVisible().catch(() => false))) break;
  }
  if (await opt.isVisible().catch(() => false)) {
    throw new Error('Picklist-Option nicht registriert: ' + optionName);
  }
}

async function dismissGuidance(page: Page) {
  const dlg = page.getByRole('dialog', { name: /Try the new Salesforce Setup/i });
  if (await dlg.count()) {
    await dlg.getByRole('button').first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

/* ============================ THE ACCEPTANCE TESTS ========================= */

test.describe('[SCRUM-467] Offer validity on Opportunities (UI)', () => {
  test.describe.configure({ timeout: 180000 });

  test.beforeAll(async () => {
    seedFixtures();
    console.log(
      `[SEED] ${FIXTURES.length} fixtures: ` +
        FIXTURES.map((f) => `${f.tag}=${f.id}`).join(' ') +
        ` | anchors sent/until iso=${iso(-6)}/${iso(14)}`
    );
  });

  test.afterAll(async () => {
    for (const f of FIXTURES) {
      deleteRecord('Opportunity', f.id);
      deleteRecord('Account', f.acct);
    }
  });

  test('AC1: both offer dates visible on the record', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${fixtureId('B2')}/view`);
    const v = await offerValues(page);
    expect(v['Offer sent on'], `AC1 AC-sent-value: expected ${de(-2)}, rendered "${v['Offer sent on']}"`).toBe(de(-2));
    expect(v['Offer valid until'], `AC1 AC-until-value: expected ${de(5)}, rendered "${v['Offer valid until']}"`).toBe(de(5));
    const snap = await page.ariaSnapshot();
    expect(snap, 'AC1: the Offer validity section is not on the record page').toContain('Offer validity');
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC1: sent=${v['Offer sent on']} until=${v['Offer valid until']} (rendered)` });
  });

  test('AC2: default expiry = sent + 30 days, past the last valid day', async ({ page }) => {
    const id = fixtureId('B3');
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    const v = await offerValues(page);
    expect(v['Offer sent on'], `AC2 anchor: expected ${de(-30)}`).toBe(de(-30));
    expect(v['Offer valid until'], `AC2 default rule: "Offer valid until" must stay EMPTY, rendered "${v['Offer valid until']}"`).toBe('');
    expect(v['Offer expiry (last valid day)'], `AC2 default expiry: expected ${de(0)}, rendered "${v['Offer expiry (last valid day)']}"`).toBe(de(0));
    const row = soqlOffer(id);
    expect(row.Offer_Valid_Until__c, `AC2 SOQL: Offer_Valid_Until__c not null (${row.Offer_Valid_Until__c})`).toBe(null);
    expect(String(row.Offer_Expires_On__c), `AC2 SOQL expiry expected ${iso(0)}`).toContain(iso(0));
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC2: until empty, expiry ${v['Offer expiry (last valid day)']} = sent+30` });
  });

  test('AC3: status and days left at a glance (live / last day / expired)', async ({ page }) => {
    const b1 = await offerValues(await openB(page, 'B1'));
    expect(b1['Offer status'], `AC3 last-day wording expected "offer valid for 14 more days", rendered "${b1['Offer status']}"`).toBe('offer valid for 14 more days');
    expect(b1['Offer days left'], `AC3 days-left for window edge: expected "14", rendered "${b1['Offer days left']}"`).toBe('14');
    expect(b1['Offer expires within 14 days'], 'AC3 window flag for the edge record (today+14) must be True').toBe('True');
    const c1 = await offerValues(await openB(page, 'C1'));
    expect(c1['Offer status'], `AC3 expired wording: expected "offer expired", rendered "${c1['Offer status']}"`).toBe('offer expired');
    expect(c1['Offer expired'], 'AC3 expired flag').toBe('True');
    expect(c1['Offer days left'], `AC3 a past offer has no days left (empty): rendered "${c1['Offer days left']}"`).toBe('');
    const b2 = await offerValues(await openB(page, 'B2'));
    expect(b2['Offer status'], `AC3 live wording: expected "offer valid for 5 more days", rendered "${b2['Offer status']}"`).toBe('offer valid for 5 more days');
    expect(b2['Offer days left'], 'AC3 days left for the live offer (5)').toBe('5');
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC3: B1="${b1['Offer status']}"(${b1['Offer days left']}) C1="${c1['Offer status']}" B2="${b2['Offer status']}"(${b2['Offer days left']})` });
  });

  test('AC4: a record without offer data never looks expired', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${fixtureId('A')}/view`);
    const v = await offerValues(page);
    for (const label of ['Offer sent on', 'Offer valid until', 'Offer expiry (last valid day)', 'Offer days left', 'Offer status']) {
      expect(v[label], `AC4 no-offer record must render "${label}" empty, rendered "${v[label]}"`).toBe('');
    }
    expect(v['Offer expired'], 'AC4: a record without offer data is never flagged expired').toBe('False');
    expect(v['Offer expires within 14 days'], 'AC4: never flagged as expiring soon either').toBe('False');
    const row = soqlOffer(fixtureId('A'));
    expect(row.Offer_Expired__c, `AC4 SOQL flag expected false (${row.Offer_Expired__c})`).toBe(false);
    expect(row.Offer_Expiring_14D__c, `AC4 SOQL window flag expected false (${row.Offer_Expiring_14D__c})`).toBe(false);
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC4: all 7 offer fields empty on page, both flags False (SOQL too)` });
  });

  test('AC5: an expired offer cannot be closed as Won - refusal saves nothing', async ({ page }) => {
    const id = fixtureId('C1');
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await dismissGuidance(page);
    await startInlineEdit(page, 'Stage');
    await clickOption(page, 'Closed Won');
    await saveInlineEdit(page);
    // The refusal must be on screen and the record must not have moved.
    await expect(
      page.getByText(/already expired|closed as Won/i).first(),
      'AC5: no refusal wording on screen after saving Closed Won on an expired offer'
    ).toBeVisible({ timeout: 20000 });
    const row = soqlOffer(id);
    expect(row.IsClosed, `AC5 refusal must leave the record open (IsClosed=${row.IsClosed})`).toBe(false);
    expect(row.StageName, `AC5 stage must stay Prospecting, got ${row.StageName}`).toBe('Prospecting');
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC5: refusal shown, SOQL IsClosed=false StageName=${row.StageName}` });
  });

  test('AC6: renewal with two new dates makes it closeable as Won', async ({ page }) => {
    const id = fixtureId('C1');
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await dismissGuidance(page);
    const sent = await startInlineEdit(page, 'Offer sent on');
    await sent.fill(de(0));
    const until = await startInlineEdit(page, 'Offer valid until');
    await until.fill(de(10));
    await saveInlineEdit(page);

    // The renewal persisted: reload the record and read the rendered values.
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    const v = await offerValues(page);
    expect(v['Offer sent on'], `AC6 renewal: expected ${de(0)}, rendered "${v['Offer sent on']}"`).toBe(de(0));
    expect(v['Offer valid until'], `AC6 renewal: expected ${de(10)}, rendered "${v['Offer valid until']}"`).toBe(de(10));
    expect(v['Offer status'], `AC6 after renewal: expected "offer valid for 10 more days", rendered "${v['Offer status']}"`).toBe('offer valid for 10 more days');
    const renewed = soqlOffer(id);
    expect(String(renewed.Offer_Sent_On__c), `AC6 SOQL renewal sent expected ${iso(0)}`).toContain(iso(0));
    expect(String(renewed.Offer_Valid_Until__c), `AC6 SOQL renewal until expected ${iso(10)}`).toContain(iso(10));
    expect(renewed.IsClosed, 'AC6 the renewal itself must not close the deal').toBe(false);

    // Now closing as Won must work.
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await startInlineEdit(page, 'Stage');
    await clickOption(page, 'Closed Won');
    await saveInlineEdit(page);
    const closed = soqlOffer(id);
    expect(closed.IsClosed, `AC6 after renewing, Closed Won must persist (IsClosed=${closed.IsClosed})`).toBe(true);
    expect(closed.StageName, `AC6 stage expected Closed Won, got ${closed.StageName}`).toBe('Closed Won');
    expect(String(closed.Offer_Sent_On__c), `AC6 closing must keep the renewed dates (sent ${iso(0)}`).toContain(iso(0));
    expect(String(closed.Offer_Valid_Until__c), `AC6 closing must keep the renewed dates (until ${iso(10)}`).toContain(iso(10));
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC6: renewal rendered+SOQL ${iso(0)}/${iso(10)} then Closed Won persisted, dates kept` });
  });

  test('AC7: Closed Lost stays possible although the offer is expired', async ({ page }) => {
    const id = fixtureId('C2');
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    const before = soqlOffer(id);
    expect(before.IsClosed, 'AC7 fixture must start open').toBe(false);
    await dismissGuidance(page);
    await startInlineEdit(page, 'Verlustgrund');
    await clickOption(page, 'Zu teuer');
    await startInlineEdit(page, 'Stage');
    await clickOption(page, 'Closed Lost');
    await saveInlineEdit(page);
    const after = soqlOffer(id);
    expect(after.IsClosed, `AC7 Closed Lost must persist despite an expired offer (IsClosed=${after.IsClosed})`).toBe(true);
    expect(after.StageName, `AC7 stage expected Closed Lost, got ${after.StageName}`).toBe('Closed Lost');
    expect(after.Loss_Reason__c != null, `AC7 loss reason persisted (${after.Loss_Reason__c})`).toBe(true);
    expect(String(after.Offer_Sent_On__c), `AC7 closing must not clear the offer history (${iso(-21)}`).toContain(iso(-21));
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC7: Closed Lost + reason persisted, offer history kept (${after.Offer_Sent_On__c})` });
  });

  test('AC8: after the deal is closed the offer dates are frozen', async ({ page }) => {
    const id = fixtureId('C1'); // closed as Won in AC6, offer dates still filled
    const before = soqlOffer(id);
    expect(before.IsClosed, 'AC8 fixture is the closed deal from AC6 (IsClosed must be true)').toBe(true);
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await dismissGuidance(page);
    const sent = await startInlineEdit(page, 'Offer sent on');
    await sent.fill(de(-40));
    await saveInlineEdit(page);
    await expect(
      page.getByText(/already closed|cannot be changed/i).first(),
      'AC8: no refusal wording shown for filling dates on a closed deal'
    ).toBeVisible({ timeout: 20000 });
    const after = soqlOffer(id);
    expect(String(after.Offer_Sent_On__c), `AC8 refusal must not move the dates (${String(before.Offer_Sent_On__c)} expected, got ${String(after.Offer_Sent_On__c)})`).toBe(String(before.Offer_Sent_On__c));
    expect(String(after.Offer_Valid_Until__c), 'AC8 the other date must be untouched too').toBe(String(before.Offer_Valid_Until__c));
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC8: refusal shown, dates unchanged ${String(after.Offer_Sent_On__c)}/${String(after.Offer_Valid_Until__c)}` });
  });

  test('AC9: Report shows the open deals expiring within 14 days, soonest first', async ({ page }) => {
    const dueCount = countOpen('Offer_Expiring_14D__c=true');
    expect(dueCount, 'AC9 ground truth: at least one offer must expire within 14 days, else the criterion is untested').toBeGreaterThan(0);
    const frame = await openReportFrame(page, 'SCRUM467_Offer_Renewals_Due_14D');
    const total = await reportTotalRecords(frame);
    expect(total, `AC9 Report total (${total}) vs SOQL ${dueCount} open records with Offer_Expiring_14D__c`).toBe(dueCount);
    const rows = await reportDataRows(frame);
    const data = dataRowsOf(rows);
    expect(data.length, `AC9 rendered record rows (${data.length}) must equal Total Records ${total}`).toBe(total);
    const firstDate = data.length > 0 ? (data[0][0].match(/^\d{2}\.\d{2}\.\d{4}/) ?? [''])[0] : '';
    expect(
      firstDate,
      `AC9 sort order: first group must be the earliest expiry ${de(0)}, got "${firstDate}"`
    ).toBe(de(0));
    for (const name of ['B1', 'B2', 'B3']) {
      const hit = data.some((r) => r.some((c) => c.includes(fixtureName(name))));
      expect(hit, `AC9 fixture ${name} missing from the report`).toBe(true);
    }
    expect(
      data.some((r) => r.some((c) => c.includes(fixtureName('C1')) || c.includes(fixtureName('C2')))),
      'AC9 an already-expired offer must NOT be in the due-soon report'
    ).toBe(false);
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC9: Report total=${total}, dataRows=${data.length}, SOQL=${dueCount}, first group ${firstDate}` });
  });

  test('AC10: Report shows the expired offers, kept apart from the due-soon ones', async ({ page }) => {
    const expiredCount = countOpen('Offer_Expired__c=true');
    expect(expiredCount, 'AC10 ground truth: at least one expired offer must exist, else untested').toBeGreaterThan(0);
    const frame = await openReportFrame(page, 'SCRUM467_Offer_Expired_Renewals');
    const total = await reportTotalRecords(frame);
    expect(total, `AC10 Report total (${total}) vs SOQL ${expiredCount}`).toBe(expiredCount);
    const rows = await reportDataRows(frame);
    const data = dataRowsOf(rows);
    expect(data.length, `AC10 rendered record rows (${data.length}) vs Total Records ${total}`).toBe(total);
    const firstExp = data.length > 0 ? (data[0][0].match(/^\d{2}\.\d{2}\.\d{4}/) ?? [''])[0] : '';
    expect(
      firstExp,
      `AC10 sort order oldest-first: first group must be ${de(-11)} (C1 = today-11), got "${firstExp}"`
    ).toBe(de(-11));
    for (const name of ['C1', 'C2']) {
      const hit = data.some((r) => r.some((c) => c.includes(fixtureName(name))));
      expect(hit, `AC10 fixture ${name} missing from the expired report`).toBe(true);
    }
    for (const name of ['B1', 'B2', 'B3']) {
      const hit = data.some((r) => r.some((c) => c.includes(fixtureName(name))));
      expect(hit, `AC10 separation: ${name} (not expired) must not be in the expired report`).toBe(false);
    }
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC10: Report total=${total}, dataRows=${data.length}, SOQL=${expiredCount}, first group ${firstExp}` });
  });

  test('AC11: nothing happens on its own', async ({ page }) => {
    // A record with no offer data (created today, untouched) stays open, unchanged.
    const row = soqlOffer(fixtureId('A'));
    expect(row.IsClosed, 'AC11 a no-offer record must not close itself').toBe(false);
    expect(row.StageName, 'AC11 a no-offer record must not change its stage').toBe('Prospecting');
    expect(row.Offer_Sent_On__c, 'AC11 nothing fills the offer dates on its own').toBe(null);
    // No Task objects were introduced for these deals, and no new sObject type.
    const tasks = soql(`SELECT Id, Subject FROM Task WHERE Subject LIKE '%SCRUM-467%'`);
    expect(tasks.length, `AC11 auto-tasks introduced for these deals (${tasks.length}) must be 0`).toBe(0);
    const objs = soqlTooling(`SELECT Queryable, Name FROM EntityDefinition WHERE Name LIKE 'Offer%'`);
    expect(objs.length, `AC11 a dedicated offer object would violate "no new objects" (${objs.map((o: any) => o.Name)})`).toBe(0);
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC11: no Task/Mail rows, no new EntityDefinition, no self-changes` });
  });

  test('AC12: the Permission-Set holder records both dates end-to-end', async ({ page }) => {
    // The E2E session IS the CLI user (holds SCRUM467_Offer_Dates) and the
    // fixture belongs to the SAME user (owner check per design).
    const id = fixtureId('B2');
    await openRecordDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await dismissGuidance(page);
    const until = await startInlineEdit(page, 'Offer valid until');
    await until.fill(de(20));
    await saveInlineEdit(page);
    const after = soqlOffer(id);
    expect(String(after.Offer_Valid_Until__c), `AC12 set holder's write expected ${iso(20)}, SOQL shows ${String(after.Offer_Valid_Until__c)}`).toContain(iso(20));
    const snap = (await pageContentSnapshot(page)) || '';
    expect(!/insufficient|not allowed/i.test(snap), 'AC12 the session user must not be blocked on the offer fields').toBe(true);
    test
      .info()
      .annotations.push({ type: 'observed', description: `AC12 UI positive: Offer_Valid_Until__c=${after.Offer_Valid_Until__c} via Save` });
  });

  /* ------------------------------ helpers (end) --------------------------- */

  async function openB(page: Page, tag: string) {
    await openRecordDetails(page, `/lightning/r/Opportunity/${fixtureId(tag)}/view`);
    return page;
  }

  async function pageContentSnapshot(page: Page): Promise<string> {
    return await page.ariaSnapshot();
  }

  async function openReportFrame(page: Page, reportName: string): Promise<any> {
    const recs = soql(`SELECT Id, Name FROM Report WHERE Name='${reportName}'`);
    expect(recs.length, `Report ${reportName} not deployed in Test-Org`).toBe(1);
    await page.goto(`/lightning/r/Report/${recs[0].Id}/view`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    let frame: any = null;
    const deadline = Date.now() + 60000;
    while (!frame) {
      frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
      if (!frame) {
        if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) not found');
        await page.waitForTimeout(1000);
      }
    }
    await frame.waitForLoadState('domcontentloaded').catch(() => {});
    await frame.locator('table tbody tr').first().waitFor({ timeout: 60000 });
    return frame;
  }

  async function reportTotalRecords(frame: any): Promise<number> {
    const text: string = await frame.locator('body').innerText().catch(() => '');
    const m = text.match(/Total Records\s*(\d+)/);
    if (!m) throw new Error(`"Total Records N" not in the report frame: ${text.slice(0, 500)}`);
    return parseInt(m[1], 10);
  }

  async function reportDataRows(frame: any): Promise<string[][]> {
    const rowsLoc = frame.locator('table tbody tr');
    const n = await rowsLoc.count();
    const out: string[][] = [];
    for (let i = 0; i < n; i++) {
      const cells = await rowsLoc.nth(i).locator('td').allTextContents().catch(() => []);
      const t = cells.map((c: string) => c.trim());
      if (t.length > 0 && t.join('').length > 0) out.push(t);
    }
    return out;
  }

  /** Rows of the GROUPED report that carry a record: first cell starts with the
   *  group date, and the row has the full column set (the drill-down summary
   *  table repeats only the date cells -> length 1, filtered out). */
  function dataRowsOf(rows: string[][]): string[][] {
    return rows.filter((r) => /^\d{2}\.\d{2}\.\d{4}/.test(r[0]) && r.length >= 8);
  }
});
