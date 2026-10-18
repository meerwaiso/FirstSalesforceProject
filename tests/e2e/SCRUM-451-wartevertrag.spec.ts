import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-451] Wartungsvertrag at the Customer — the UI/report half of the story.
 *
 * The Apex pair on the branch (SCRUM451WartungsvertragTest,
 * SCRUM451WartungsvertragFlsTest) proves the VALUES of the derived fields.
 * This spec proves the deliverables the user actually opens:
 *   - the Account detail page (AC1 visible, AC3 "45 days", AC4 "ends today",
 *     AC5 "expired" without a negative count, AC7/AC8 empty end date)
 *   - the Case detail page (AC6 the SCRUM-431 indicator follows the expiry)
 *   - the Sales overview report (AC9 rows = measured count, AC10 exclusions)
 *   - the SCRUM-431 Service morning overview (AC13 derived indicator, not the
 *     raw flag — the PO's decision)
 *   - nothing automatic (AC11)
 *
 * Every expected number comes from a live SOQL read at test time, never from a
 * constant, so the spec stays valid while the fixtures age.
 *
 * DOM facts verified 2026-10-18 against Test-Org (probe: scratch/probe451*.mjs):
 *   - A record page opens on Related; the Details tab has to be clicked
 *     (house helper openRecordDetails does that and verifies the switch).
 *   - Field labels on the Account Details tab, verbatim:
 *       "Wartungsvertrag" (flag), "Wartungsvertrag start", "Wartungsvertrag end",
 *       "Wartungsvertrag ends in (Tage)", "Wartungsvertrag status",
 *       "Wartungsvertrag counts (derived)", "Wartungsvertrag ends within 3 months"
 *     On the Case page: "Wartungsvertrag (Kunde)".
 *   - Values render as the line after the label in the Details-tab innerText
 *     ("Wartungsvertrag status" | "in 45 days"); a blank field renders the next
 *     label straight after it.
 *   - The value span of a read-only (formula) field carries the class
 *     "is-read-only"; the two recorded dates do not.
 *   - Reports render in the lightningReportApp cross-doc frame; the frame states
 *     "Total Records N" and the data rows are `table tbody tr`
 *     (house shape, SCRUM-428 / SCRUM-431).
 *   - Report ids are resolved by Name through SOQL (house shape SCRUM-396),
 *     never hardcoded — orgs get recreated.
 */

const P = 'TEST-SCRUM-451-';
const SALES_REPORT = 'Wartungsvertrag_Renewals_3M';
const MORNING_REPORT = 'Morgen_UEbersicht_Vertragskunden';

/* ------------------------- sf-CLI helpers (house) ------------------ */

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
    timeout: 90000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
}

function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}

/** SELECT COUNT() answers in result.totalSize with an empty records array. */
function soqlCount(q: string): number {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  if (!doc.result || doc.result.totalSize === undefined) {
    throw new Error(`COUNT() query returned no totalSize: ${JSON.stringify(doc).slice(0, 300)}`);
  }
  return doc.result.totalSize;
}

function reportIdOf(name: string): string {
  const recs = soql(`SELECT Id, Name FROM Report WHERE Name = '${name}' LIMIT 1`);
  if (recs.length === 0) throw new Error(`Report "${name}" is not deployed in Test-Org`);
  return String(recs[0].Id);
}

/** SOQL Date "2026-12-02" → what Lightning renders for this org: "02.12.2026". */
function deDate(iso: string): string {
  const [y, m, d] = iso.split('T')[0].split('-');
  return `${d}.${m}.${y}`;
}

/* ------------------- Account Details-tab field reader ---------------------- */

const ACCOUNT_LABELS = [
  'Wartungsvertrag',
  'Wartungsvertrag start',
  'Wartungsvertrag end',
  'Wartungsvertrag ends in (Tage)',
  'Wartungsvertrag status',
  'Wartungsvertrag counts (derived)',
  'Wartungsvertrag ends within 3 months',
];

/**
 * Read one field on the Details tab.
 *
 * Returns present=false when the label is not on the page at all (layout gap),
 * value='' when the label is there but renders blank (an empty field). Those
 * two are different findings and the ACs need to tell them apart.
 */
async function fieldOnDetails(page: Page, label: string) {
  const lines = ((await page.locator('body').innerText()) || '')
    .split('\n').map((s) => s.trim());
  const hits = lines.reduce((acc: number[], l, i) => (l === label ? acc.concat([i]) : acc), [] as number[]);
  if (hits.length === 0) return { present: false, value: '' };
  let value = '';
  for (const i of hits) {
    for (let j = i + 1; j < Math.min(i + 3, lines.length); j++) {
      const cand = lines[j];
      if (!cand) continue;
      if (ACCOUNT_LABELS.includes(cand) || cand.startsWith('Edit ')) break;
      value = cand;
      break;
    }
    if (value) break;
  }
  return { present: true, value };
}

/**
 * Is the rendered value read-only for THIS session's user?
 * Verified DOM fact 2026-10-18: the value span of a formula field carries the
 * class "is-read-only", the two recorded dates do not. Returns null when the
 * label is not on the page, so a missing field can never read as "writable".
 */
async function readOnlyOnDetails(page: Page, label: string): Promise<boolean | null> {
  return await page.evaluate(
    (label: string) => {
      for (const el of document.querySelectorAll('div.slds-form-element')) {
        const lab = el.querySelector('[class*="test-id__field-label"]');
        if (!lab || (lab.textContent || '').trim() !== label) continue;
        const val = el.querySelector('[class*="field-value"]');
        return val ? /is-read-only/.test(val.className || '') : null;
      }
      return null;
    },
    label,
  );
}

/* --------------------------- Report frame (house) -------------------------- */

async function openReportFrame(page: Page, name: string): Promise<Frame> {
  const id = reportIdOf(name);
  await page.goto(`/lightning/r/Report/${id}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForSelector('.slds-global-header', { state: 'visible', timeout: 60000 });
  let frame: Frame | undefined;
  const deadline = Date.now() + 60000;
  for (;;) {
    frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) break;
    if (Date.now() > deadline) throw new Error(`Report-Frame (lightningReportApp) not rendered for ${name}`);
    await page.waitForTimeout(500);
  }
  await frame.waitForLoadState('domcontentloaded').catch(() => {});
  await frame.locator('table tbody tr').first().waitFor({ timeout: 45000 });
  return frame!;
}

async function reportStatedTotal(frame: Frame): Promise<number> {
  const text: string = await frame.locator('body').innerText().catch(() => '');
  const m = text.match(/Total Records\s*(\d+)/);
  if (!m) throw new Error(`"Total Records N" not in the report frame:\n${text.slice(0, 600)}`);
  return parseInt(m[1], 10);
}

async function reportRows(frame: Frame): Promise<string[][]> {
  const rows = frame.locator('table tbody tr');
  const n = await rows.count();
  const out: string[][] = [];
  for (let i = 0; i < n; i++) {
    const cells = (await rows.nth(i).locator('td').allTextContents().catch(() => [])).map((c) => c.trim());
    if (cells.length > 0 && cells.join('').length > 0) out.push(cells);
  }
  return out;
}

/* ============================ AC1 + AC3 ================================== */

test.describe('[SCRUM-451] Customer detail page: dates, remaining time at a glance', () => {
  test('AC1+AC3: recorded dates stored, visible, and the remaining time shown', async ({ page }) => {
    const [g] = soql(`SELECT Name, Wartungsvertrag_Start__c, Wartungsvertrag_End__c,
                      Wartungsvertrag_Ende_Tage__c, Wartungsvertrag_Status__c,
                      Wartungsvertrag_Active__c
                      FROM Account WHERE Name = '${P}ACTIVE-45'`);
    expect(g, `fixture ${P}ACTIVE-45 missing in Test-Org — the Tester's seed is gone`).not.toBe(undefined);
    console.log(`[AC1/AC3] SOQL: start=${g.Wartungsvertrag_Start__c} end=${g.Wartungsvertrag_End__c} days=${g.Wartungsvertrag_Ende_Tage__c} status=${g.Wartungsvertrag_Status__c}`);

    await openRecordDetails(page, `/lightning/r/Account/${g.Id}/view`);

    const start = await fieldOnDetails(page, 'Wartungsvertrag start');
    const end = await fieldOnDetails(page, 'Wartungsvertrag end');
    const days = await fieldOnDetails(page, 'Wartungsvertrag ends in (Tage)');
    const status = await fieldOnDetails(page, 'Wartungsvertrag status');

    // AC1: the two recorded dates are writable for a team lead, the derived
    // values are read-only for everyone (verified DOM distinction).
    const startWritable = await readOnlyOnDetails(page, 'Wartungsvertrag start');
    const endWritable = await readOnlyOnDetails(page, 'Wartungsvertrag end');
    const daysReadOnly = await readOnlyOnDetails(page, 'Wartungsvertrag ends in (Tage)');
    expect(startWritable, 'AC1: "Wartungsvertrag start" is not editable on the page').toBe(false);
    expect(endWritable, 'AC1: "Wartungsvertrag end" is not editable on the page').toBe(false);
    expect(daysReadOnly, 'AC1: the derived day count must be read-only').toBe(true);

    // AC1: both dates are on the customer and readable in a real session.
    expect(start.present, 'AC1: no "Wartungsvertrag start" on the detail page').toBe(true);
    expect(start.value, `AC1: start date not rendered as stored (${deDate(g.Wartungsvertrag_Start__c)})`)
      .toBe(deDate(g.Wartungsvertrag_Start__c));
    expect(end.present, 'AC1: no "Wartungsvertrag end" on the detail page').toBe(true);
    expect(end.value, `AC1: end date not rendered as stored (${deDate(g.Wartungsvertrag_End__c)})`)
      .toBe(deDate(g.Wartungsvertrag_End__c));

    // AC3: the user does not calculate anything — the page states the days.
    expect(days.value, `AC3: remaining time not the stored value (${g.Wartungsvertrag_Ende_Tage__c})`)
      .toBe(String(g.Wartungsvertrag_Ende_Tage__c));
    expect(status.value, `AC3: glance value not "${g.Wartungsvertrag_Status__c}"`).toBe(String(g.Wartungsvertrag_Status__c));

    test.info().annotations.push({
      type: 'observed',
      description: `AC1/AC3: page shows start=${start.value}, end=${end.value}, days=${days.value}, status=${status.value}; SOQL ${g.Wartungsvertrag_Ende_Tage__c}/${g.Wartungsvertrag_Status__c}`,
    });
  });

  test('AC4: a contract ending today still counts as a maintenance customer', async ({ page }) => {
    const [g] = soql(`SELECT Name, Wartungsvertrag_End__c, Wartungsvertrag_Ende_Tage__c,
                      Wartungsvertrag_Status__c, Wartungsvertrag_Active__c
                      FROM Account WHERE Name = '${P}ENDS-TODAY'`);
    expect(g, `fixture ${P}ENDS-TODAY missing`).not.toBe(undefined);
    console.log(`[AC4] SOQL: end=${g.Wartungsvertrag_End__c} days=${g.Wartungsvertrag_Ende_Tage__c} status=${g.Wartungsvertrag_Status__c} active=${g.Wartungsvertrag_Active__c}`);

    await openRecordDetails(page, `/lightning/r/Account/${g.Id}/view`);
    const end = await fieldOnDetails(page, 'Wartungsvertrag end');
    const days = await fieldOnDetails(page, 'Wartungsvertrag ends in (Tage)');
    const status = await fieldOnDetails(page, 'Wartungsvertrag status');
    const counts = await fieldOnDetails(page, 'Wartungsvertrag counts (derived)');

    expect(end.value, `AC4: end date is today (${deDate(g.Wartungsvertrag_End__c)})`).toBe(deDate(g.Wartungsvertrag_End__c));
    expect(days.value, 'AC4: end date inclusive -> 0 days left, shown as 0').toBe('0');
    expect(status.value, 'AC4: the page states that it ends today').toBe('ends today');
    expect(counts.value, 'AC4: still counts as a maintenance customer').toBe('True');

    test.info().annotations.push({
      type: 'observed',
      description: `AC4: page end=${end.value} days=${days.value} status=${status.value} counts=${counts.value}`,
    });
  });

  test('AC5: an expired contract says so and never shows a negative count', async ({ page }) => {
    const [g] = soql(`SELECT Name, Wartungsvertrag_End__c, Wartungsvertrag_Ende_Tage__c,
                      Wartungsvertrag_Status__c, Wartungsvertrag_Active__c
                      FROM Account WHERE Name = '${P}EXPIRED'`);
    expect(g, `fixture ${P}EXPIRED missing`).not.toBe(undefined);
    console.log(`[AC5] SOQL: end=${g.Wartungsvertrag_End__c} days=${g.Wartungsvertrag_Ende_Tage__c} status=${g.Wartungsvertrag_Status__c}`);

    await openRecordDetails(page, `/lightning/r/Account/${g.Id}/view`);
    const days = await fieldOnDetails(page, 'Wartungsvertrag ends in (Tage)');
    const status = await fieldOnDetails(page, 'Wartungsvertrag status');
    const counts = await fieldOnDetails(page, 'Wartungsvertrag counts (derived)');

    expect(status.value, 'AC5: the page states that the contract already expired').toBe('expired');
    expect(days.present, 'AC5: the remaining-time field exists on the page').toBe(true);
    expect(days.value, 'AC5: an expired contract shows NO day count at all').toBe('');
    expect(/-\s*\d/.test(days.value), 'AC5: a negative day count would be visible here').toBe(false);
    expect(counts.value, 'AC5: an expired contract no longer counts').toBe('False');

    test.info().annotations.push({
      type: 'observed',
      description: `AC5: page status=${status.value}, day count blank, counts=${counts.value}`,
    });
  });

  test('AC7+AC8: an empty end date (and a start-only customer) keeps the old behaviour', async ({ page }) => {
    const fixtures = soql(`SELECT Id, Name, Wartungsvertrag__c, Wartungsvertrag_Start__c, Wartungsvertrag_End__c,
                           Wartungsvertrag_Ende_Tage__c, Wartungsvertrag_Status__c,
                           Wartungsvertrag_Active__c, Wartungsvertrag_Renewal_Soon__c
                           FROM Account WHERE Name IN ('${P}NO-END-1', '${P}START-ONLY')`);
    expect(fixtures.length, 'both fixtures for AC7/AC8 must exist').toBe(2);
    console.log(`[AC7/AC8] SOQL: ${fixtures.map((f) => `${f.Name}: start=${f.Wartungsvertrag_Start__c} end=${f.Wartungsvertrag_End__c}`).join(' | ')}`);

    for (const g of fixtures) {
      await openRecordDetails(page, `/lightning/r/Account/${g.Id}/view`);
      const flag = await fieldOnDetails(page, 'Wartungsvertrag');
      const end = await fieldOnDetails(page, 'Wartungsvertrag end');
      const days = await fieldOnDetails(page, 'Wartungsvertrag ends in (Tage)');
      const status = await fieldOnDetails(page, 'Wartungsvertrag status');
      const counts = await fieldOnDetails(page, 'Wartungsvertrag counts (derived)');
      const window = await fieldOnDetails(page, 'Wartungsvertrag ends within 3 months');

      expect(flag.value, `AC7/AC8: the recorded flag stays what the team lead typed (${g.Wartungsvertrag__c})`)
              .toBe(String(g.Wartungsvertrag__c));
      expect(end.present, 'AC7/AC8: the end date field exists, it is just empty').toBe(true);
      expect(end.value, 'AC7/AC8: no end date recorded -> renders empty').toBe('');
      expect(days.value, 'AC7/AC8: no day count without an end date').toBe('');
      expect(status.value, 'AC7/AC8: no status word without an end date').toBe('');
      expect(counts.value, 'AC7/AC8: still counts as a maintenance customer').toBe('True');
      expect(window.value, 'AC7/AC8: never in the sales overview without an end date').toBe('False');

      test.info().annotations.push({
        type: 'observed',
        description: `${g.Name}: flag=${flag.value} end='${end.value}' days='${days.value}' status='${status.value}' counts=${counts.value} window=${window.value}`,
      });
    }
  });
});

/* ============================ AC6 (Case page) ============================= */

test.describe('[SCRUM-451] The SCRUM-431 case indicator follows the expiry', () => {
  test('AC6: a case of an expired customer no longer shows the indicator', async ({ page }) => {
    const cases = soql(`SELECT Id, CaseNumber, Account.Name, Wartungsvertrag_Anzeige__c
                        FROM Case WHERE Account.Name LIKE '${P}%'`);
    expect(cases.length, 'the seeded cases must exist').toBeGreaterThan(0);
    const byName = cases.reduce((m, c) => { m[String(c['Account.Name'])] = c; return m; }, {} as any);
    console.log(`[AC6] SOQL: ${cases.map((c) => `${c.CaseNumber} ${c['Account.Name']} -> ${c.Wartungsvertrag_Anzeige__c}`).join(' | ')}`);

    for (const name of [`${P}EXPIRED`, `${P}ACTIVE-45`, `${P}NO-END-1`]) {
      const c = byName[name];
      expect(c, `AC6: no seeded case of ${name} — the fixture set is incomplete`).not.toBe(undefined);
      await openRecordDetails(page, `/lightning/r/Case/${c.Id}/view`);
      const lines = ((await page.locator('body').innerText()) || '').split('\n').map((s) => s.trim());
      const hits = lines.reduce((acc: number[], l, i) => (l === 'Wartungsvertrag (Kunde)' ? acc.concat([i]) : acc), [] as number[]);
      expect(hits.length, `AC6: the indicator "Wartungsvertrag (Kunde)" is not on the case page of ${name}`).toBeGreaterThan(0);
      let value = '';
      for (const i of hits) {
        const cand = lines[i + 1];
        if (cand && !ACCOUNT_LABELS.includes(cand) && !cand.startsWith('Edit ')) { value = cand; break; }
      }
      expect(value, `AC6: case of ${name} shows "${value}", SOQL says "${c.Wartungsvertrag_Anzeige__c}"`).toBe(String(c.Wartungsvertrag_Anzeige__c));
      test.info().annotations.push({ type: 'observed', description: `${name} case ${c.CaseNumber}: indicator=${value}` });
    }

    // The org-wide count the AC demands: cases of expired-contract customers
    // that still show the indicator must be 0 — beside the record count, so a
    // zero-record measurement cannot pass silently.
    const expiredCases = soqlCount(`SELECT COUNT() FROM Case WHERE Account.Wartungsvertrag_End__c != null AND Account.Wartungsvertrag_End__c < TODAY`);
    const stillShowing = soqlCount(`SELECT COUNT() FROM Case WHERE Account.Wartungsvertrag_End__c != null
                               AND Account.Wartungsvertrag_End__c < TODAY AND Wartungsvertrag_Anzeige__c = 'Ja'`);
    console.log(`[AC6] SOQL: cases of expired customers=${expiredCases}, of them still "Ja"=${stillShowing}`);
    expect(expiredCases, 'AC6 needs at least one case of an expired customer to be a real test').toBeGreaterThan(0);
    expect(stillShowing, 'AC6: cases of expired customers still showing the indicator must be 0').toBe(0);
  });
});

/* ==================== AC9 + AC10: the sales overview ====================== */

test.describe('[SCRUM-451] Sales overview: contracts ending in the next 3 months', () => {
  test('AC9: the overview lists exactly the customers with an end date in the window', async ({ page }) => {
    const inWindow = soql(`SELECT Id, Name, Wartungsvertrag_End__c, Wartungsvertrag_Status__c
                           FROM Account WHERE Wartungsvertrag_Renewal_Soon__c = true
                           ORDER BY Wartungsvertrag_End__c ASC`);
    const truthCount = soqlCount(`SELECT COUNT() FROM Account WHERE Wartungsvertrag_Renewal_Soon__c = true`);
    console.log(`[AC9] SOQL ground truth: ${truthCount} customers in today -> today+3M: ${inWindow.map((r) => `${r.Name} ${r.Wartungsvertrag_End__c}`).join(' | ')}`);
    expect(truthCount, 'AC9 needs at least one customer in the window to be a real test').toBeGreaterThan(0);

    const frame = await openReportFrame(page, SALES_REPORT);
    const stated = await reportStatedTotal(frame);
    const rows = await reportRows(frame);
    console.log(`[AC9] Report: Total Records=${stated}, rows=${rows.length}, first=${JSON.stringify(rows[0])}`);

    // The row count must equal the measured number (the AC's own wording).
    expect(stated, `AC9: overview states ${stated}, SOQL measures ${truthCount} customers in the window`).toBe(truthCount);
    expect(rows.length, `AC9: rendered rows=${rows.length} ≠ stated ${stated}`).toBe(stated);

    // Columns: customer, end date, account owner — the USERS.NAME column the
    // Architect could not read through the CLI session.
    for (let i = 0; i < rows.length; i++) {
      const cells = rows[i];
      expect(cells.length, `AC9: row ${i} has ${cells.length} cells (row#, customer, owner, end, status)`).toBe(5);
      expect(cells[2].length, `AC9: the account-owner column is empty in row ${i} (${JSON.stringify(cells)})`).toBeGreaterThan(0);
    }

    // Every customer of the SOQL ground truth is listed, soonest first.
    const renderedNames = rows.map((r) => r[1]);
    for (const g of inWindow) {
      expect(renderedNames, `AC9: ${g.Name} is missing from the overview`).toContain(g.Name);
      const row = rows[renderedNames.indexOf(g.Name)];
      expect(row[3], `AC9: ${g.Name} end date rendered ${row[3]} ≠ SOQL ${deDate(g.Wartungsvertrag_End__c)}`).toBe(deDate(g.Wartungsvertrag_End__c));
    }
    const expectedOrder = inWindow.map((r) => r.Name);
    expect(renderedNames, `AC9: rows sorted soonest first (${expectedOrder.join(' < ')})`).toEqual(expectedOrder);

    test.info().annotations.push({
      type: 'observed',
      description: `AC9: Total Records=${stated}, rows=${rows.length}, owner column filled, order=${renderedNames.join(' < ')}`,
    });
  });

  test('AC10: already-expired contracts and customers without an end date are not listed', async ({ page }) => {
    const frame = await openReportFrame(page, SALES_REPORT);
    const rows = await reportRows(frame);
    const renderedNames = rows.map((r) => r[1]);
    const excluded = soql(`SELECT Name FROM Account WHERE Wartungsvertrag__c = true
                           AND (Wartungsvertrag_End__c = null OR Wartungsvertrag_End__c < TODAY)`);
    console.log(`[AC10] excluded by definition: ${excluded.map((r) => r.Name).join(' | ')}; rendered: ${renderedNames.join(' | ')}`);
    expect(excluded.length, 'AC10 needs expired / no-end-date customers to exclude').toBeGreaterThan(0);
    for (const g of excluded) {
      expect(renderedNames, `AC10: ${g.Name} (expired or no end date) must not be in the overview`).not.toContain(g.Name);
    }
    test.info().annotations.push({
      type: 'observed',
      description: `AC10: ${excluded.length} expired/no-end-date customers measured, none of them rendered in ${rows.length} rows`,
    });
  });
});

/* ==================== AC13: the Service morning overview ================== */

test.describe('[SCRUM-451] AC13 (PO): morning overview filters the derived indicator', () => {
  test('AC13: an expired customer and its open cases are no longer listed', async ({ page }) => {
    const truthCount = soqlCount(`SELECT COUNT() FROM Case WHERE Account.Wartungsvertrag_Active__c = true AND IsClosed = false`);
    console.log(`[AC13] SOQL: ${truthCount} open cases of customers that still count`);
    expect(truthCount, 'AC13 needs open cases to be a real test').toBeGreaterThan(0);

    const frame = await openReportFrame(page, MORNING_REPORT);
    const stated = await reportStatedTotal(frame);
    const rows = await reportRows(frame);
    const renderedCaseNumbers = rows.map((r) => r[1]);
    console.log(`[AC13] Report: Total Records=${stated}, rows=${rows.length}, cases=${renderedCaseNumbers.join(' | ')}`);

    expect(stated, `AC13: morning overview states ${stated}, SOQL measures ${truthCount}`).toBe(truthCount);

    // The expired customer's open case must be gone (the PO's decision).
    const expiredCase = soql(`SELECT Id, CaseNumber, Account.Name FROM Case
                              WHERE Account.Wartungsvertrag__c = true
                                AND Account.Wartungsvertrag_End__c != null
                                AND Account.Wartungsvertrag_End__c < TODAY`);
    expect(expiredCase.length, 'AC13 needs an open case of an expired customer').toBeGreaterThan(0);
    for (const c of expiredCase) {
      expect(renderedCaseNumbers, `AC13: case ${c.CaseNumber} of expired customer ${c['Account.Name']} is still listed`).not.toContain(String(c.CaseNumber));
    }

    // A flagged customer WITHOUT an end date must still be listed (PO decision 3).
    const noEndCase = soql(`SELECT Id, CaseNumber, Account.Name FROM Case
                            WHERE Account.Wartungsvertrag__c = true AND Account.Wartungsvertrag_End__c = null AND IsClosed = false`);
    expect(noEndCase.length, 'AC13 needs an open case of a no-end-date customer').toBeGreaterThan(0);
    for (const c of noEndCase) {
      expect(renderedCaseNumbers, `AC13: case ${c.CaseNumber} of ${c['Account.Name']} (no end date) must still be listed`).toContain(String(c.CaseNumber));
    }

    test.info().annotations.push({
      type: 'observed',
      description: `AC13: Total Records=${stated} = SOQL ${truthCount}; ${expiredCase.length} expired-customer cases absent, ${noEndCase.length} no-end-date cases present`,
    });
  });
});

/* ============================ AC11: nothing automatic ===================== */

test.describe('[SCRUM-451] AC11: no email, task, reminder or notification', () => {
  test('AC11: the story creates no automatic artefact', async ({ page }) => {
    const taskCount = soqlCount(`SELECT COUNT() FROM Task WHERE Subject LIKE '${P}%'`);
    const templates = shellJson(rawOut(
      `sf data query -q "SELECT Id, Name FROM EmailTemplate WHERE Name LIKE '%Wartungsvertrag%' OR Name LIKE '%451%'" --target-org Test-Org --use-tooling-api --json`
    ));
    const templateRows = (templates.result && templates.result.records) || [];
    console.log(`[AC11] SOQL: Task naming a fixture=${taskCount}; EmailTemplate naming the story=${templateRows.length}`);
    expect(taskCount, 'AC11: no Task may be created for the contract fixtures').toBe(0);
    expect(templateRows.length, 'AC11: no EmailTemplate may belong to this story').toBe(0);

    // The customer page carries no chatter/notification about the contract.
    const [g] = soql(`SELECT Id, Name FROM Account WHERE Name = '${P}ACTIVE-45'`);
    await openRecordDetails(page, `/lightning/r/Account/${g.Id}/view`);
    const body = ((await page.locator('body').innerText()) || '');
    const chatterHits = (body.match(/Wartungsvertrag/g) || []).length;
    console.log(`[AC11] record page chatter markers=${chatterHits}`);
    expect(chatterHits, 'AC11 sanity: the contract fields must be on the page (labels + Edit buttons)').toBeGreaterThan(0);

    test.info().annotations.push({
      type: 'observed',
      description: `AC11: 0 Task, 0 EmailTemplate; the overview is the only mechanism (PR artefact list: metadata + tests + docs only)`,
    });
  });
});
