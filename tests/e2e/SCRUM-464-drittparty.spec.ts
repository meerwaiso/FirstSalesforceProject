import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-464] Drittparty-Produkt => Fabrikant from a controlled list — UI-E2E
 * against Test-Org (Lightning). Sibling pattern: SCRUM-461 (Competitor__c).
 *
 * Session: frontdoor.jsp globalSetup (auth.setup.ts → storage-state.json), baseURL
 * from org.ts — never a hardcoded host, never networkidle on Lightning.
 *
 * LOCATORS PROBED against this org on 2026-11-20 (browser_exec AX-tree probe on
 * the closed Case 500WU000031cANeYAM — not guessed):
 *   - Record page Details tab: 'Edit' button (full inline edit) opens a change
 *     form with comboboxes named exactly 'Ursache' and 'Fabrikant (Drittparty-Produkt)'
 *     plus buttons 'Save', 'Save & New', 'Cancel', 'Cancel and close'.
 *   - Per-field quick edits also exist ('Edit Ursache', 'Edit Fabrikant (Drittparty-Produkt)',
 *     'Edit Fixkosten (Teile + Spesen + Zusathre)') — the combined cause+Fabrikant
 *     save uses the full 'Edit' form so ONE Save applies both fields (AC2 refuses
 *     any save that has the third-party cause without a Fabrikant).
 *   - Picklist options live in a shadow root: ariaSnapshot('option "X"') only (SCRUM-417 trap).
 *   - Lookup picker: fill(query) THEN click() opens it; offered options readable
 *     only via ariaSnapshot (SCRUM-461 probe).
 *   - Refused save: dialog 'We hit a snag' naming the errorDisplayField
 *     'Fabrikant (Drittparty-Produkt)' (house SCRUM-461).
 *   - Report view: /lightning/r/Report/<id>/view, iframe 'lightningReportApp';
 *     group-row first cell '<name>, unchecked, Select row for Drill Down.<name>'.
 *
 * ORG DATA (measured 2026-11-20, Developer's fixtures stay untouched):
 *   Fabrikant__c: Siemens (a07WU00001VNfeUYAT), Miele (a07WU00001VNl6AYAT);
 *   4 closed third-party Cases all owned by the CLI session user 005WU000017tEKLYA2.
 *   My fixtures (Bosch 3 cases all cost-unknown, Atlas via one FOREIGN-owned case,
 *   plus the close-path and old-style cases) are deleted in afterAll — the org
 *   returns to the Developer's counts afterwards.
 *   Expected report rows are computed from live SOQL, never from numbers kept here.
 */

const ORG = 'Test-Org';
const P = 'TEST-SCRUM-464-';
const CAUSE_COMBO = 'Ursache';
const CAUSE_THIRDPARTY_LABEL = 'Drittparty / Fremdfabrik Produkt';
const LOOKUP_COMBO = 'Fabrikant (Drittparty-Produkt)';
const PICKER_HELPERS = ['Add New', 'Search Show more results', 'Search More'];

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}
function sfRun(args: string): any {
  return shellJson(
    execSync(`sf ${args} --target-org ${ORG} --json`, {
      encoding: 'utf-8',
      timeout: 180000,
      stdio: ['pipe', 'pipe', 'pipe'],
    }),
  );
}
function soql(query: string): any[] {
  const doc = sfRun(`data query -q "${query}"`);
  const result = doc?.result ?? doc;
  return result?.records ?? [];
}
function createRecord(sobject: string, values: string): string {
  const doc = sfRun(`data create record -s ${sobject} -v "${values}"`);
  const id = doc?.result?.id ?? doc?.id;
  if (!id) throw new Error(`Create ${sobject} lieferte keine Id`);
  return String(id);
}
function updateRecord(sobject: string, id: string, values: string): void {
  sfRun(`data update record -s ${sobject} -i ${id} -v "${values}"`);
}
function deleteRecord(sobject: string, id: string): void {
  try {
    sfRun(`data delete record -s ${sobject} -i ${id}`);
  } catch {
    /* best effort — fixtures are named TEST-SCRUM-464-* */
  }
}

// ── fixtures ────────────────────────────────────────────────────────────────

function ensureFabrikant(name: string): string {
  const found = soql(`SELECT Id FROM Fabrikant__c WHERE Name = '${name}' LIMIT 1`);
  if (found.length > 0) return String(found[0].Id);
  return createRecord('Fabrikant__c', `Name='${name}'`);
}

/** A closed Case that predates the new data style: normal cause, no Fabrikant/cost. */
function ensureOldStyleClosed(subjectTag: string, cause: string, score: string): string {
  const name = `${P}${subjectTag}`;
  const found = soql(`SELECT Id FROM Case WHERE Subject = '${name}' LIMIT 1`);
  if (found.length > 0) return String(found[0].Id);
  const id = createRecord('Case', `Subject='${name}' Status='Working' Origin='Web'`);
  updateRecord('Case', id, `Status='Closed' Ursache__c='${cause}' Customer_Satisfaction__c='${score}'`);
  return id;
}

/** A closed third-party Case: cause value + Fabrikant set atomically (AC2 rule). */
function ensureThirdPartyClosed(subjectTag: string, fabrikantId: string, cost: number | null): string {
  const name = `${P}${subjectTag}`;
  const found = soql(`SELECT Id FROM Case WHERE Subject = '${name}' LIMIT 1`);
  if (found.length > 0) return String(found[0].Id);
  const id = createRecord('Case', `Subject='${name}' Status='Working' Origin='Web'`);
  const costPart = cost === null ? '' : ` Drittparty_Fixkosten__c=${cost}`;
  updateRecord(
    'Case',
    id,
    `Status='Closed' Ursache__c='DrittpartyProdukt' Customer_Satisfaction__c='Score_4'` +
      ` Drittparty_Fabrikant__c=${fabrikantId}${costPart}`,
  );
  return id;
}

/** Foreign-owned closed third-party Case: created by the session user, then OwnerId reassigned (verified working 2026-11-20). */
function ensureForeignThirdParty(fabrikantId: string, foreignUserId: string): string {
  const name = `${P}FOREIGN`;
  const found = soql(`SELECT Id, OwnerId FROM Case WHERE Subject = '${name}' LIMIT 1`);
  if (found.length > 0) {
    if (String(found[0].OwnerId) !== foreignUserId) updateRecord('Case', String(found[0].Id), `OwnerId='${foreignUserId}'`);
    return String(found[0].Id);
  }
  const id = ensureThirdPartyClosed('FOREIGN', fabrikantId, null);
  updateRecord('Case', id, `OwnerId='${foreignUserId}'`);
  return id;
}

/** What the reports must show, computed from the org — not from this file. */
function expectedRows(ownOnly: boolean, sessionOwner: string): Record<string, { count: number; sum: number | null; avg: number | null }> {
  const deals = soql(
    `SELECT Id, OwnerId, Closed_Last_12M__c, Drittparty_Fabrikant__c, Drittparty_Fixkosten__c, Drittparty_Fixkosten_Known__c ` +
    `FROM Case WHERE IsClosed = true AND Ursache__c = 'DrittpartyProdukt'`,
  );
  const names: Record<string, string> = {};
  for (const f of soql('SELECT Id, Name FROM Fabrikant__c')) names[String(f.Id)] = String(f.Name);

  const acc: Record<string, { count: number; sum: number | null; known: number[] }> = {};
  for (const d of deals) {
    if (d.Closed_Last_12M__c !== true) continue;
    if (!d.Drittparty_Fabrikant__c) continue;
    if (ownOnly && String(d.OwnerId) !== sessionOwner) continue;
    const name = names[String(d.Drittparty_Fabrikant__c)];
    if (!name) continue;
    const row = acc[name] ?? { count: 0, sum: null as number | null, known: [] as number[] };
    row.count += 1;
    if (d.Drittparty_Fixkosten__c !== null && d.Drittparty_Fixkosten__c !== undefined) {
      row.sum = (row.sum ?? 0) + Number(d.Drittparty_Fixkosten__c);
      if (d.Drittparty_Fixkosten_Known__c === 1) row.known.push(Number(d.Drittparty_Fixkosten__c));
    }
    acc[name] = row;
  }
  const out: Record<string, { count: number; sum: number | null; avg: number | null }> = {};
  for (const key of Object.keys(acc)) {
    const a = acc[key];
    out[key] = {
      count: a.count,
      sum: a.sum,
      avg: a.known.length === 0 ? null : a.known.reduce((x, y) => x + y, 0) / a.known.length,
    };
  }
  return out;
}

function sessionOwner(): string {
  const mine = soql(`SELECT OwnerId FROM Case WHERE Subject = '464 Org Siemens dishwasher' LIMIT 1`);
  expect(mine.length, 'precondition: the Developers fixture case exists').toBeGreaterThan(0);
  return String(mine[0].OwnerId);
}

function foreignUserId(sessionOwner: string): string {
  const doc = sfRun('data query -q "SELECT Id, Username FROM User" --use-tooling-api');
  const users = (doc?.result ?? doc)?.records ?? [];
  const others = users.filter((u: any) => String(u.Id) !== sessionOwner);
  expect(others.length, 'precondition: another user exists for the foreign-owned fixture').toBeGreaterThan(0);
  return String(others[0].Id);
}

// ── report helpers (house SCRUM-434 / SCRUM-461) ────────────────────────────

function resolveReportId(name: string): string {
  const found = soql(`SELECT Id FROM Report WHERE Name = '${name}' LIMIT 1`);
  expect(found.length, `Report '${name}' is not deployed in Test-Org`).toBeGreaterThan(0);
  return String(found[0].Id);
}

async function boundedSnap(node, ms = 20000): Promise<string> {
  // An unguarded ariaSnapshot() on a Lightning record page hung (measured in
  // SCRUM-417 and again 2026-11-20 in AC10, where it burned the whole test
  // timeout). Every read of a big subtree goes through this cap.
  return await Promise.race([
    node.ariaSnapshot(),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error(`ariaSnapshot exceeded ${ms}ms`)), ms)),
  ]);
}

async function reportFrame(page: Page, reportName: string): Promise<Frame> {
  await page.goto(`/lightning/r/Report/${resolveReportId(reportName)}/view`, {
    waitUntil: 'domcontentloaded', timeout: 60000,
  });
  await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
  const deadline = Date.now() + 90000;
  for (;;) {
    const frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) {
      await frame.locator('td').first().waitFor({ timeout: 60000 });
      return frame;
    }
    if (Date.now() > deadline) throw new Error('report iframe never appeared');
    await page.waitForTimeout(1000);
  }
}

async function groupRows(frame: Frame, knownNames: string[]): Promise<Array<{ label: string; cells: string[] }>> {
  const rows: Array<{ label: string; cells: string[] }> = [];
  for (const tr of await frame.locator('tr').all()) {
    const cells = await tr.locator('td, th').allTextContents();
    if (cells.length === 0) continue;
    const label = cells[0].replace(/\s+/g, ' ').trim();
    const hit = knownNames.find((n) => label === `${n}, unchecked, Select row for Drill Down.${n}`);
    if (hit) rows.push({ label, cells });
  }
  return rows;
}

/** German and US number rendering both parse: 1.450,00 € / 1,450.00 */
function toNumbers(texts: string[]): number[] {
  const out: number[] = [];
  for (const t of texts) {
    for (const raw of t.match(/-?\d[\d.,]*/g) ?? []) {
      let s = raw;
      const lastComma = s.lastIndexOf(',');
      const lastDot = s.lastIndexOf('.');
      if (lastComma > lastDot) s = s.replace(/\./g, '').replace(/,/, '.');
      else if (lastDot > lastComma) {
        if (/\.\d{3}(\D|$)/.test(s) && !/\.\d{1,2}(\D|$)/.test(s)) s = s.replace(/\./g, '');
        else s = s.replace(/,/g, '');
      }
      const n = Number(s);
      if (!Number.isNaN(n)) out.push(n);
    }
  }
  return out;
}
function hasNumber(list: number[], wanted: number): boolean {
  return list.some((n) => Math.abs(n - wanted) < 0.51);
}

// ── form helpers (house SCRUM-461, probed locators above) ───────────────────

async function dismissGuidance(page: Page) {
  const dlg = page.getByRole('dialog', { name: /Try the new Salesforce Setup/i });
  if ((await dlg.count()) > 0) {
    await dlg.getByRole('button').first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

async function pickOption(page: Page, comboName: string, optionName: string) {
  const combo = page.getByRole('combobox', { name: comboName, exact: true }).first();
  await expect(await combo.count(), `combobox "${comboName}" is not on the page`).toBeGreaterThan(0);
  for (let attempt = 0; attempt < 6; attempt++) {
    const els = await page.locator('[role=option]').all();
    for (const el of els) {
      const snap = await el.ariaSnapshot().catch(() => '');
      if (snap.includes(`option "${optionName}"`)) {
        await el.click({ force: true });
        await page.waitForTimeout(700);
        return;
      }
    }
    await combo.click({ timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(900);
  }
  throw new Error(`Picker "${comboName}" never offered "${optionName}"`);
}

async function offeredLookups(page: Page): Promise<string[]> {
  const els = await page.locator('[role=option]').all();
  const names: string[] = [];
  for (const el of els) {
    const snap = await el.ariaSnapshot().catch(() => '');
    const m = snap.match(/option "([^"]+)"/);
    if (m && !PICKER_HELPERS.some((h) => m[1].startsWith(h))) names.push(m[1]);
  }
  return names;
}

async function openLookupPicker(page: Page, query: string): Promise<string[]> {
  const combo = page.getByRole('combobox', { name: LOOKUP_COMBO, exact: true }).first();
  await expect(await combo.count(), `the Lookup picker "${LOOKUP_COMBO}" is not on the form`).toBeGreaterThan(0);
  await combo.fill(query);
  await page.waitForTimeout(1500);
  for (let attempt = 0; attempt < 8; attempt++) {
    await combo.click({ timeout: 15000 });
    await page.waitForTimeout(2000);
    const names = await offeredLookups(page);
    if (names.length > 0) return names;
  }
  return [];
}

async function pickLookup(page: Page, query: string, wanted: string) {
  const combo = page.getByRole('combobox', { name: LOOKUP_COMBO, exact: true }).first();
  await expect(await combo.count(), `the Lookup picker "${LOOKUP_COMBO}" is not on the form`).toBeGreaterThan(0);
  await combo.fill(query);
  await page.waitForTimeout(1200);
  for (let attempt = 0; attempt < 5; attempt++) {
    await combo.click({ timeout: 15000 });
    await page.waitForTimeout(1200);
    for (const el of await page.locator('[role=option]').all()) {
      const snap = await el.ariaSnapshot().catch(() => '');
      if (!snap.includes(`option "${wanted}"`)) continue;
      const box = await el.boundingBox();
      if (!box) continue;
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      await page.mouse.down();
      await page.mouse.up();
      await page.waitForTimeout(1500);
      return;
    }
  }
  throw new Error(`Lookup picker never offered "${wanted}" for query "${query}"`);
}

async function openEditForm(page: Page, caseId: string) {
  await openRecordDetails(page, `/lightning/r/Case/${caseId}/view`);
  await dismissGuidance(page);
  const edit = page.getByRole('button', { name: 'Edit', exact: true }).first();
  await expect(edit, 'the record page offers no full inline edit').toBeVisible({ timeout: 20000 });
  await edit.click({ timeout: 15000 });
  const save = page.getByRole('button', { name: 'Save', exact: true }).first();
  await expect(save, 'the inline edit form shows no Save button').toBeVisible({ timeout: 20000 });
}

async function expectRefusalDialog(page: Page, namesField: string) {
  const dialog = page.getByRole('dialog').first();
  await expect(dialog, 'the refusal shows no error dialog').toBeVisible({ timeout: 20000 });
  const aria = await dialog.ariaSnapshot();
  expect(aria, `the error dialog does not name "${namesField}"`).toContain(namesField);
}

// ── the suite ───────────────────────────────────────────────────────────────

test.describe('[SCRUM-464] Drittparty-Fabrikant (UI)', () => {
    test.describe.configure({ timeout: 900000 }); // AC10 needs the record+edit+list round trip; 300s expired mid-test (measured 2026-11-20)

  const createdCases: string[] = [];
  const createdFabrikants: string[] = [];
  let closeCaseId = '';
  let boschId = '';
  let atlasId = '';
  let foreignCaseId = '';

  test.beforeAll(() => {
    const owner = sessionOwner();
    const foreign = foreignUserId(owner);
    closeCaseId = ensureOldStyleClosed('CLOSE-PATH', 'TechnischerFehler', 'Score_4');
    createdCases.push(closeCaseId);
    boschId = ensureFabrikant('Bosch');
    createdFabrikants.push(boschId);
    for (const tag of ['B1', 'B2', 'B3']) {
      createdCases.push(ensureThirdPartyClosed(tag, boschId, null));
    }
    atlasId = ensureFabrikant('Atlas');
    createdFabrikants.push(atlasId);
    foreignCaseId = ensureForeignThirdParty(atlasId, foreign);
    if (!createdCases.includes(foreignCaseId)) createdCases.push(foreignCaseId);
  });

  // AC1: the picker offers the third-party value. AC2: closing it without a
  // Fabrikant is refused and the message names the field (single save attempt).
  test('AC1+AC2: cause picker offers the third-party value; save without Fabrikant refused, message names it', async ({ page }) => {
    await openEditForm(page, closeCaseId);
    await pickOption(page, CAUSE_COMBO, CAUSE_THIRDPARTY_LABEL);

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    await expectRefusalDialog(page, LOOKUP_COMBO);
    const after = soql(`SELECT Id, Ursache__c, Drittparty_Fabrikant__c FROM Case WHERE Id = '${closeCaseId}' LIMIT 1`);
    expect(String(after[0].Ursache__c), 'AC2: the save went through despite the missing Fabrikant').not.toBe('DrittpartyProdukt');
    expect(after[0].Drittparty_Fabrikant__c, 'AC2: a Fabrikant was demanded by the save').toBeNull();
  });

  // AC5: the picker offers list entries only (typed free text is not offered).
  // AC1/AC7: the third-party cause saves with a Fabrikant and no cost.
  test('AC5+AC1/AC7: picker offers only list entries; combined save persists, cost stays blank', async ({ page }) => {
    const list = soql('SELECT Name FROM Fabrikant__c').map((r) => String(r.Name));

    await openEditForm(page, closeCaseId);
    const offered = await openLookupPicker(page, 'Siemens');
    expect(offered.filter((o) => o === 'Siemens').length, 'AC5: the list entry "Siemens" is not offered by the picker').toBeGreaterThan(0);
    const loose = offered.filter((o) => o !== 'Siemens' && !list.includes(o));
    expect(loose.length, `AC5: the picker offers "${loose.join(', ')}", which is not a list entry`).toBe(0);

    const second = await openLookupPicker(page, 'Siemens AG');
    for (const fake of ['Siemens AG', 'Siemens GmbH']) {
      expect(second.filter((o) => o === fake).length, `AC5: "${fake}" is not on the list and must not be offered`).toBe(0);
    }

    await pickLookup(page, 'Siemens', 'Siemens');
    await pickOption(page, CAUSE_COMBO, CAUSE_THIRDPARTY_LABEL);
    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const after = soql(
      `SELECT Id, Ursache__c, Drittparty_Fabrikant__c, Drittparty_Fixkosten__c, Drittparty_Fixkosten_Known__c, Customer_Satisfaction__c ` +
      `FROM Case WHERE Id = '${closeCaseId}' LIMIT 1`,
    );
    expect(String(after[0].Ursache__c), 'AC1: the third-party cause did not save').toBe('DrittpartyProdukt');
    expect(String(after[0].Drittparty_Fabrikant__c), 'AC1: no Fabrikant saved').toBeTruthy();
    expect(after[0].Drittparty_Fixkosten__c, 'AC7: a cost demanded without one entered').toBeNull();
    expect(after[0].Drittparty_Fixkosten_Known__c, 'AC7: unknown cost must be counted as 0 in the denominator').toBe(0);
  });

  // AC8: org-wide overview — one row per company, count/total/average, most cases first.
  test('AC8: org overview shows every company once, count/total/average, the most-cases maker on top', async ({ page }) => {
    const expected = expectedRows(false, sessionOwner());
    const names = Object.keys(expected);
    expect(names.length, 'AC8 precondition: no third-party Fabrikant has a case in the window').toBeGreaterThan(0);

    const frame = await reportFrame(page, 'Faelle_Drittparty_Fabrikante');
    const rows = await groupRows(frame, names);
    expect(rows.length, `AC8: the report shows ${rows.length} rows for ${names.length} companies`).toBe(names.length);
    const seenLabels = new Set<string>();
    for (const r of rows) {
      expect(seenLabels.has(r.label), `AC5: "${r.label}" appears more than once in the overview`).toBe(false);
      seenLabels.add(r.label);
    }

    const order: number[] = [];
    for (const r of rows) {
      const want = expected[names.find((n) => r.label === `${n}, unchecked, Select row for Drill Down.${n}`)!];
      const nums = toNumbers(r.cells);
      console.log(`AC8 rendered row: ${r.label} -> ${JSON.stringify(r.cells)}`);
      expect(hasNumber(nums, want.count), `AC8: row "${r.label}" does not show its case count ${want.count}`).toBe(true);
      if (want.sum !== null) {
        expect(hasNumber(nums, want.sum), `AC8: row "${r.label}" does not show the total ${want.sum}`).toBe(true);
      }
      if (want.avg !== null) {
        // Falsifier: the average is over KNOWN costs only — a group mixing a
        // 1450.00 cost with a blank one must NOT show the halved figure.
        expect(hasNumber(nums, want.avg), `AC8: row "${r.label}" shows no average over known costs (expected ${want.avg})`).toBe(true);
      } else {
        const zeros = nums.filter((n) => Math.abs(n) < 0.51);
        expect(zeros.length, `AC8: row "${r.label}" prints a zero although no cost is known (PO rule: never zero)`).toBe(0);
        expect(nums.length, `AC8: row "${r.label}" carries ${nums.length} numbers although no cost is known (count only expected)`).toBe(1);
      }
      order.push(want.count);
    }
    for (let i = 1; i < order.length; i++) {
      expect(order[i] <= order[i - 1], `AC8: rows are not sorted by case count at row ${i}`).toBe(true);
    }
    const top = names.slice().sort((a, b) => expected[b].count - expected[a].count)[0];
    expect(rows[0].label.startsWith(top), `AC8: the company with the most cases (${top}) is not on top`).toBe(true);
  });

  // AC9/AC11: the user-scoped overview counts only the viewer's own cases.
  test('AC9+AC11: the user overview counts only own cases, the org one includes the foreign-owned case', async ({ page }) => {
    const owner = sessionOwner();
    const all = expectedRows(false, owner);
    const own = expectedRows(true, owner);
    const foreign = Object.keys(all).filter((n) => all[n].count > (own[n]?.count ?? 0));
    expect(foreign.length, 'AC9 precondition: no case is owned by another user').toBeGreaterThan(0);

    const orgFrame = await reportFrame(page, 'Faelle_Drittparty_Fabrikante');
    const orgRows = await groupRows(orgFrame, Object.keys(all));
    const myFrame = await reportFrame(page, 'Faelle_Drittparty_Fabrikante_Meine');
    const myRows = await groupRows(myFrame, [...Object.keys(all), ...Object.keys(own)]);

    for (const name of foreign) {
      const orgRow = orgRows.find((r) => r.label.startsWith(name));
      const myRow = myRows.find((r) => r.label.startsWith(name));
      expect(orgRow, `AC11: ${name} missing from the org overview`).toBeTruthy();
      expect(hasNumber(toNumbers(orgRow!.cells), all[name].count), `AC11: org row for ${name} does not show ${all[name].count}`).toBe(true);
      expect(myRow, `AC9: ${name} must NOT be counted in the own overview`).toBeUndefined();
    }
    for (const name of Object.keys(own)) {
      if (foreign.includes(name)) continue;
      const row = myRows.find((r) => r.label.startsWith(name));
      expect(row, `AC9: ${name} missing from the own overview`).toBeTruthy();
      const nums = toNumbers(row!.cells);
      const want = own[name];
      console.log(`AC9 rendered own row: ${name} -> ${JSON.stringify(row!.cells)}`);
      expect(hasNumber(nums, want.count), `AC9: own row ${name} misses its count ${want.count}`).toBe(true);
      if (want.sum !== null) expect(hasNumber(nums, want.sum), `AC9: own row ${name} misses its total ${want.sum}`).toBe(true);
      if (want.avg === null) {
        const zeros = nums.filter((n) => Math.abs(n) < 0.51);
        expect(zeros.length, `AC9: own row ${name} prints a zero although no own cost is known`).toBe(0);
      }
    }
  });

  // AC10: a closed case without the new data opens, lists and re-saves — the
  // new rules must not demand anything.
  test('AC10: old-style closed case opens, re-saves unflagged, new fields stay blank', async ({ page }) => {
    // `Cause__c` does not exist on Case (measured 2026-11-20: INVALID_FIELD "No such
  // column 'Cause__c' on entity 'Case'"); the picklist is Ursache__c.
  const before = soql(`SELECT Id, Subject, Ursache__c FROM Case WHERE Subject = '${P}OLD-SAVES' LIMIT 1`);
    const targetId = before[0]?.Id ?? ensureOldStyleClosed('OLD-SAVES', 'RechnungAbrechnung', 'Score_3');
    if (!createdCases.includes(targetId)) createdCases.push(targetId);

    await openRecordDetails(page, `/lightning/r/Case/${targetId}/view`);
    const body = await boundedSnap(page.locator('body').first());
    expect(body.includes('We hit a snag'), 'AC10: opening the case demanded something').toBe(false);

    await openEditForm(page, targetId);
    const subject = page.getByLabel('Subject', { exact: true }).first();
    await expect(subject, 'AC10: the edit form has no Subject input').toBeVisible({ timeout: 20000 });
    await subject.fill(`${P}OLD-SAVES`);
    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const dialog = page.getByRole('dialog').first();
    const aria = await boundedSnap(dialog).catch(() => '');
    expect(aria.includes('We hit a snag'), 'AC10: the re-save was refused').toBe(false);

    const after = soql(
      `SELECT Subject, Ursache__c, Drittparty_Fabrikant__c, Drittparty_Fixkosten__c FROM Case WHERE Id = '${targetId}' LIMIT 1`,
    );
    expect(String(after[0].Subject), 'AC10: the re-save did not persist').toBe(`${P}OLD-SAVES`);
    expect(after[0].Drittparty_Fabrikant__c, 'AC10: the re-save demanded a Fabrikant').toBeNull();
    expect(after[0].Drittparty_Fixkosten__c, 'AC10: the re-save demanded a cost').toBeNull();
    expect(String(after[0].Ursache__c), 'AC10: the cause was not preserved').toBe('RechnungAbrechnung');

    // The "lists" half moved to its own test (AC10b) with a fresh page:
    // on this page the EDIT FORM was the last thing open, and page.goto from
    // there died with "Target page, context or browser has been closed"
    // (measured 2026-11-20, run 15,6 min, log scratch/e2e-464-ac10.log).
  });

  // AC10b: after the re-save the old-style closed case is listed in the Cases list.
  test('AC10b: the re-saved old-style case is listed in the Cases list view', async ({ page }) => {
    const listed = soql(`SELECT Id, Subject FROM Case WHERE Subject = '${P}OLD-SAVES' LIMIT 1`);
    expect(listed.length, 'AC10b: the re-saved case is not in the org at all').toBe(1);

    await page.goto('/lightning/o/Case/list?filterName=Recent', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
    // The list rows are NOT anchors in the light DOM (measured 2026-11-20:
    // locator('a[href*="/lightning/r/Case/"]') -> 0). Like the SCRUM-417 related
    // list, the rows live in a shadow subtree that only the ARIA snapshot reads.
    const aria = await boundedSnap(page.locator('body').first(), 30000);
    expect(aria.includes('We hit a snag'), 'AC10b: the Cases list view hit a snag').toBe(false);
    expect(aria.length, 'AC10b: the Cases list view rendered no content at all').toBeGreaterThan(2000);
    const hit = aria.indexOf(`${P}OLD-SAVES`);
    console.log(`AC10b aria len=${aria.length} subject found at=${hit} context=${hit >= 0 ? aria.slice(Math.max(0, hit - 120), hit + 60) : 'n/a'}`);
    expect(hit >= 0, 'AC10b: the re-saved case is not listed in the Cases list').toBe(true);
  });

  test.afterEach(() => {});

  // Fixtures stay until the last report test has run, then the org returns to
  // the Developers counts — nothing of this suite survives.
  test.afterAll(() => {
    for (const id of createdCases.splice(0)) deleteRecord('Case', id);
    for (const id of createdFabrikants.splice(0)) deleteRecord('Fabrikant__c', id);
  });
});
