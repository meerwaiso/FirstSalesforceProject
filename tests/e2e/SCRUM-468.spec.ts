import { test, expect } from '@playwright/test';
import { type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { requireData } from './preflight';
import { openRecordPage } from './record-page';

/**
 * [SCRUM-468] Lend Devices — Tester E2E über Test-Org (branch 9f91b7b / PR #190).
 *
 * Playwright-BDD: beforeAll löscht älter Fixture-Sets und SEENDETT die
 * Measured-Fixture-Set (PO-specified: 4 devices, 6 loans — 2 open and both
 * PAST DUE (30 and 15 days), 4 returned (one 14 days), 1 Written_Off,
 * 3 customers, 2 colleagues); afterAll keeps the org's 0-lending baseline.
 * The Fixture-values are read back via SOQL (ids, overdue-days, durations) —
 * the org IS the artifact asserted below, never the assumption.
 *
 * Guard-refusal texts (measured live via `sf data create record` 2026-11-21):
 *   AC2  Lend Devices: serial "<s>" is already on device DEV-xxxx - one serial number may belong to exactly one device.
 *   AC4  Lend Devices: device DEV-xxxx is already on loan to a customer not in this save - a device may be with exactly one customer at a time.
 *   AC9  Lend Devices: device DEV-xxxx is written off and can never be lent out again.
 *
 * Live ListView facts (measured 2026-11-21 via ariaSnapshot, /lightning/o/
 * Demo_Devic__c/list?filterName=SCRUM468_Overdue):
 *   status: "2 items • Sorted by Designation • Filtered by Overdue today"
 *   ONE `row "..."` per record in the aria tree whose accessible name carries
 *   EVERY cell in order: designation, serial, customer, colleague, due date
 *   (locale DD.MM.YYYY), days overdue  -> single locator: lines /^\s*- row "/
 *   columnheader buttons offer "Sort by: Days overdue" but "Sorted: None" —
 *   the rendered order (30 before 15) is the UI fact asserted here.
 *
 * Record-page related lists (re-measured 2026-11-22 with ariaSnapshot on the
 * RELATED tab — the earlier innerText read was blind to the closed Shadow-Root
 * and reported both lists as absent, which was wrong):
 *   Demo_Devic__c page: section "Loan records (2)" renders a grid whose rows
 *   carry the customer link plus the three dates. Rendered columnheaders:
 *   "Lent to customer | Loan start date | Loan due date | Return date |
 *   Action" — the layout's fifth <fields> Loan_Duration_Days__c (label
 *   "Loan duration in days") is NOT among them -> AC7 duration half is a gap.
 *   Account page: the section "Devices on loan" (layout
 *   <relatedList>Demo_Devic__c.Current_Customer__c) renders its HEADING only —
 *   no count, no /related/ link, no row — while the standard sections render
 *   "Contacts (0)" with a link. AC5 rows are missing.
 */

const TAG = '[TEST-SCRUM-468]';

/* ---------------------------- measured fixture ids ------------------------ */
// seeded by beforeAll below via SOQL-read ids; these consts exist ONLY for
// readability of the AC prose — the tests resolve ids from the seed read-back.

type Fix = { key: string; id: string };
const devs: Record<string, string> = {};   // '1'..'4' by designation suffix
const accts: Record<string, string> = {};  // 'A','B','C'
const loans: Record<string, string> = {};  // L1..L6

/* ---------------------------- sf-CLI helpers (house 467) ------------------ */
function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const s = clean.indexOf('{');
  const e = clean.lastIndexOf('}');
  if (s < 0 || e < s) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(s, e + 1));
}
function rawOut(command: string): string {
  return execSync(command, {
    encoding: 'utf-8',
    timeout: 120000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  }).toString();
}
function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}
function createRecord(type: string, fields: string): string {
  const doc = shellJson(rawOut(`sf data create record -s ${type} -v "${fields}" --target-org Test-Org --json`));
  const id = doc?.result?.id ?? doc?.id;
  if (!id) throw new Error(`Create ${type} lieferte keine Id: ${JSON.stringify(doc).slice(0, 300)}`);
  return String(id);
}
function updateRecord(type: string, id: string, fields: string): void {
  rawOut(`sf data update record -s ${type} -i ${id} -v "${fields}" --target-org Test-Org --json`);
}
function deleteRecord(type: string, id: string): void {
  try {
    rawOut(`sf data delete record -s ${type} -i ${id} --target-org Test-Org --json`);
  } catch {
    /* best effort */
  }
}
// execSync THROWS on a rejected save — the refusal text lives in the thrown
// error's stdout/stderr (verified 2026-11-21).
function failingRun(command: string): string {
  try {
    rawOut(command);
    return ''; // the save was NOT refused — the caller's assertion catches that
  } catch (err: any) {
    const e = err as any;
    const out = `${e.message || ''}\n${(e.stdout && String(e.stdout)) || ''}\n${(e.stderr && String(e.stderr)) || ''}`;
    const m = out.match(/"message"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    return m ? m[1].replace(/\\\\"/g, '"') : out;
  }
}

/* ------------------------------- fixtures ------------------------------- */
function cleanupFixtures(): void {
  for (const r of soql(`SELECT Id FROM Loan_Record__c WHERE Name LIKE 'LOAN%'`)) deleteRecord('Loan_Record__c', r.Id);
  for (const r of soql(`SELECT Id FROM Demo_Devic__c WHERE Designation_Name__c LIKE '${TAG}%'`)) deleteRecord('Demo_Devic__c', r.Id);
  for (const r of soql(`SELECT Id FROM Account WHERE Name LIKE '${TAG}%'`)) deleteRecord('Account', r.Id);
}
function dev(n: string): string {
  return `${TAG} Device ${n}`;
}
function cust(n: string): string {
  return `${TAG} Kunde ${n}`;
}
const TODAY = new Date();
function iso(off: number): string {
  const d = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + off);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function de(off: number): string {
  const d = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + off);
  return `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`;
}

// colleagues must be REAL users of the org (colleague = who lent it)
const colleagueNames = ['Meerwais Osmani', 'Integration User'];

function seedFixtures(): void {
  cleanupFixtures();
  for (const n of ['A', 'B', 'C']) accts[n] = createRecord('Account', `Name='${cust(n)}'`);
  const [u1, u2] = colleagueIds();
  for (const n of ['1', '2', '3', '4']) devs[n] = createRecord('Demo_Devic__c', `Designation_Name__c='${dev(n)}' Serial_Number__c='SCRUM468-TEST-${n}'`);
  const lend = (d: string, c: string, u: string, start: number, due: number) =>
    createRecord(
      'Loan_Record__c',
      `Loan_Devic__c='${devs[d]}' Loan_Customer__c='${accts[c]}' Loan_Colleague__c='${u}' Loan_Start_Datum__c='${iso(start)}' Loan_Due_Datum__c='${iso(due)}'`
    );
  loans.L1 = lend('1', 'A', u1, -60, -30); // open, overdue 30
  loans.L2 = lend('2', 'A', u2, -45, -15); // open, overdue 15
  // The one-customer guard refuses a SECOND open loan on a device (hard rule, AC4) -
  // the four historical loans must therefore be returned BEFORE the next one is lent.
  const lendReturned = (d: string, c: string, u: string, start: number, due: number) => {
    const id = lend(d, c, u, start, due);
    updateRecord('Loan_Record__c', id, `Loan_Return_Datum__c='${iso(due)}'`); // returned at due date
    return id;
  };
  loans.L3 = lendReturned('3', 'A', u1, -60, -46);
  loans.L4 = lendReturned('3', 'B', u2, -44, -30);
  loans.L5 = lendReturned('4', 'B', u1, -60, -35);
  loans.L6 = lendReturned('4', 'C', u2, -40, -12);
  updateRecord('Demo_Devic__c', devs['4'], `Status__c='Written_Off'`); // team-lead action (session user holds the marker set)
}
function colleagueIds(): string[] {
  const users = soql(`SELECT Id, Name FROM User WHERE Name = 'Meerwais Osmani' OR Name = 'Integration User'`);
  return colleagueNames.map((n) => {
    const hit = users.find((u) => u.Name === n);
    if (!hit) throw new Error(`colleague user ${n} not in org`);
    return hit.Id;
  });
}

/* ----------------------------- UI helpers ------------------------------- */
async function listStatus(page: any, items: number): Promise<void> {
  await page.goto('/lightning/o/Demo_Devic__c/list?filterName=SCRUM468_Overdue', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForSelector('table', { state: 'visible', timeout: 30000 });
  await page.waitForFunction(
    (n: number) => (document.body.innerText || '').includes(`${n} items •`),
    items,
    { timeout: 30000 },
  );
}
async function listRows(page: any): Promise<string[]> {
  const snap = await page.ariaSnapshot();
  return snap.split('\n').filter((l: string) => /^\s*- row "/.test(l) && !/Row Number/.test(l) && !/[0-9A-Z]{15}/.test(l));
}

/** Open a record page and land on its RELATED tab (house note 2026-08-23:
 * the record page does not open on Details; the related lists live under the
 * Related tab). Verified 2026-11-22 on Account 001WU00002LnLdHYAV (tablist
 * "Tabs": tab "Related" | tab "Details"). */
async function openRelatedTab(page: Page, path: string) {
  await openRecordPage(page, path);
  const tab = page.getByRole('tab', { name: 'Related' });
  await tab.waitFor({ state: 'visible', timeout: 30000 });
  await tab.click();
  await page.waitForTimeout(2500);
}

/** Aria lines of one related-list section, from its heading to the next
 * level-2 heading. ariaSnapshot pierces the closed Shadow-Root the record
 * body lives in (measured 2026-11-22: document.body.innerText 1.3 kB WITHOUT
 * any related-list content; the snapshot carries the whole section incl. the
 * grid rows). Section shape on this org:
 *   article "Loan records": / heading "Loan records (2)" / link + /url
 *   grid > rowgroup > row "<cells in order>" (rowheader + gridcell lines). */
function sectionRows(snap: string, heading: string): string[] {
  const lines = snap.split('\n');
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    // The heading line carries the related-list COUNT ("Loan records (2)"), so
    // the name is matched as a PREFIX — an exact match would never fire.
    if (new RegExp(`heading "${heading}`).test(lines[i].trim())) { start = i; break; }
  }
  if (start < 0) return [];
  const rows: string[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i].trim();
    if (/\[level=2\]$/.test(l) && /^- heading /.test(l)) break;
    if (/^- row "/.test(l)) rows.push(l);
  }
  return rows;
}

async function ariaOf(page: Page): Promise<string> {
  return await page.ariaSnapshot();
}

// Related-list rows paint AFTER the section heading (measured: the heading and
// the columnheader grid arrive before the row cells). Poll the ariaSnapshot
// until the section has rows; a section that is still empty after the budget
// is empty in the deployment, not unrendered.
async function sectionRowsPoll(page: Page, heading: string, budgetMs = 25000) {
  const started = Date.now();
  for (;;) {
    const rows = sectionRows(await ariaOf(page), heading);
    if (rows.length > 0) return rows;
    if (Date.now() - started > budgetMs) return rows;
    await page.waitForTimeout(1500);
  }
}

/* -------------------------------- the suite ------------------------------ */
test.describe('SCRUM-468 Lend Devices (Test-Org)', () => {
  test.describe.configure({ timeout: 240000 });

  test.beforeAll(async () => {
    seedFixtures();
    // PO (22.11.): "Put the PO's counts into requireData([...]) first" — a
    // gelatinent leerer Data Group turnt jede Count-Assertion green. Fail
    // before the first Assertion if die Testlage does not exist in Test-Org.
    await requireData(
        [
            { ac: 'AC5', what: 'current loans (open, with customer and device)',
              soql: `SELECT Id FROM Loan_Record__c WHERE Loan_Customer__c != null AND Loan_Devic__c != null AND Loan_Return_Datum__c = null`, min: 1 },
            { ac: 'AC7', what: 'returned loans (history for the device page)',
              soql: `SELECT Id FROM Loan_Record__c WHERE Loan_Devic__c != null AND Loan_Return_Datum__c != null`, min: 1 },
            { ac: 'AC9', what: 'a written-off device',
              soql: `SELECT Id FROM Demo_Devic__c WHERE Status__c = 'Written_Off'`, min: 1 },
            { ac: 'AC8', what: 'an overdue device (Overdue today)',
              soql: `SELECT Id FROM Demo_Devic__c WHERE Overdue_today__c = true`, min: 1 },
        ],
        'Test-Org',
    );
    expect(soql(`SELECT Id FROM Demo_Devic__c WHERE Designation_Name__c LIKE '${TAG}%'`).length, 'fixtures: 4 live devices').toBe(4);
    expect(soql(`SELECT Id FROM Loan_Record__c WHERE Name LIKE 'LOAN%'`).length, 'fixtures: 6 live loans').toBe(6);
    const overdue = soql(`SELECT Id, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Status__c = 'Lent_Out'`)
      .filter((r: any) => Number(r.Current_Loan_Overdue_Days__c || 0) > 0);
    expect(overdue.length, 'fixtures: exactly 2 overdue devices').toBe(2);
    expect(overdue.map((r: any) => r.Current_Loan_Overdue_Days__c).sort(), 'fixtures: overdue-days 15 and 30').toEqual([15, 30]);
    expect(soql(`SELECT Id, Loan_Return_Datum__c FROM Loan_Record__c`).filter((r: any) => r.Loan_Return_Datum__c != null).length, 'fixtures: 4 loans returned').toBe(4);
    expect(soql(`SELECT Id, Loan_Duration_Days__c FROM Loan_Record__c WHERE Loan_Devic__c='${devs['3']}' AND Loan_Return_Datum__c != null`).map((r: any) => r.Loan_Duration_Days__c), 'fixtures: one returned loan of 14 days (D3)').toContain(14);
  });

  test.afterAll(async () => {
    cleanupFixtures(); // org keeps its 0-lending baseline between runs
  });

  test('AC1 exactly one fresh device record with serial and status Available', async () => {
    const id = createRecord('Demo_Devic__c', `Designation_Name__c='${TAG} AC1-e2e' Serial_Number__c='SCRUM468-E2E-1'`);
    try {
      const rows = soql(
        `SELECT Id, Name, Status__c, Serial_Number__c FROM Demo_Devic__c WHERE Designation_Name__c = '${TAG} AC1-e2e'`
      );
      expect(rows.length, `AC1 exactly one record for the designation (${rows.length})`).toBe(1);
      expect(rows[0].Serial_Number__c, 'AC1 the serial number landed').toBe('SCRUM468-E2E-1');
      expect(rows[0].Status__c, 'AC1 fresh status label Available').toBe('Available');
      expect(rows[0].Id, 'AC1 the record read back is the created one').toBe(id);
    } finally {
      deleteRecord('Demo_Devic__c', id);
    }
  });

  test('AC2 used serial refused and the refusal names the device', async () => {
    const dup = failingRun(
      `sf data create record -s Demo_Devic__c -v "Designation_Name__c='${TAG} dup' Serial_Number__c='SCRUM468-TEST-1'" --target-org Test-Org --json`
    ).replace(/\\+/g, '');
    expect(dup.length, 'AC2 the duplicate serial WAS refused (message expected)').toBeGreaterThan(0);
    expect(/serial "SCRUM468-TEST-1" is already on device DEV-\d+/.test(dup), 'AC2 refusal names serial AND owning device').toBe(true);
    expect(/one serial number may belong to exactly one device/.test(dup), 'AC2 refusal wording (Lend Devices guard)').toBe(true);
    expect(soql(`SELECT Id FROM Demo_Devic__c WHERE Designation_Name__c = '${TAG} dup'`).length, 'AC2 the refused save stored nothing').toBe(0);
  });

  test('AC3 lending writes device side AND one loan record', async () => {
    const devRow = soql(
      `SELECT Id, Name, Status__c, Current_Customer__c, Current_Loan_Colleague__c, Current_Loan_Due_Date__c FROM Demo_Devic__c WHERE Id='${devs['1']}'`
    );
    expect(devRow.length, 'AC3 device readable').toBe(1);
    expect(devRow[0].Status__c, 'AC3 device shows status lent out').toBe('Lent_Out');
    expect(devRow[0].Current_Customer__c, 'AC3 device shows the customer').toBe(accts.A);
    const loanRows = soql(
      `SELECT Loan_Colleague__c, Loan_Customer__c, Loan_Start_Datum__c, Loan_Due_Datum__c FROM Loan_Record__c WHERE Id='${loans.L1}'`
    );
    expect(loanRows.length, 'AC3 exactly one lending record exists for that loan').toBe(1);
    expect(loanRows[0].Loan_Start_Datum__c, 'AC3 start date on the loan').toBe(iso(-60));
    expect(loanRows[0].Loan_Due_Datum__c, 'AC3 due date on the loan').toBe(iso(-30));
    const openForD1 = soql(`SELECT Id FROM Loan_Record__c WHERE Loan_Devic__c='${devs['1']}' AND Loan_Return_Datum__c=null`);
    expect(openForD1.length, 'AC3 one open loan on D1').toBe(1);
    expect(devRow[0].Current_Loan_Due_Date__c, 'AC3 the open loans due date exists').toBe(iso(-30));
  });

  test('AC4 second lending on a busy device refused, still one open loan', async () => {
    const msg = failingRun(
      `sf data create record -s Loan_Record__c -v "Loan_Devic__c='${devs['1']}' Loan_Customer__c='${accts.B}' Loan_Colleague__c='${colleagueIds()[1]}' Loan_Start_Datum__c='${iso(-3)}' Loan_Due_Datum__c='${iso(1)}'" --target-org Test-Org --json`
    );
    expect(msg.length, 'AC4 the second lending WAS refused').toBeGreaterThan(0);
    expect(/already on loan to a customer not in this save/.test(msg), 'AC4 refusal wording').toBe(true);
    const devRow = soql(`SELECT Status__c, Current_Customer__c FROM Demo_Devic__c WHERE Id='${devs['1']}'`);
    expect(devRow[0].Current_Customer__c, 'AC4 the device still shows customer A').toBe(accts.A);
    const open = soql(`SELECT Id FROM Loan_Record__c WHERE Loan_Devic__c='${devs['1']}' AND Loan_Return_Datum__c=null`);
    expect(open.length, 'AC4 open lending records for D1 still exactly one').toBe(1);
  });

  test('AC5 customer page lists the two current loans with due dates', async ({ page }) => {
    const open = soql(`SELECT Id, Loan_Devic__c, Loan_Due_Datum__c FROM Loan_Record__c WHERE Loan_Customer__c='${accts['A']}' AND Loan_Return_Datum__c=null`);
    expect(open.length, 'fixture: two open loans for Kunde A').toBe(2);
    const returned = soql(`SELECT Id, Loan_Devic__c FROM Loan_Record__c WHERE Loan_Customer__c='${accts['A']}' AND Loan_Return_Datum__c!=null`);
    expect(returned.length, 'fixture: one returned loan for Kunde A (must NOT be listed as current)').toBe(1);
    // The criterion is about the CUSTOMER'S RECORD PAGE: the layout's related
    // list "Devices on loan" (measured live 2026-11-22: heading present, rows
    // see below). The related list is read from the ariaSnapshot (closed
    // Shadow-Root, see sectionRows).
    await openRelatedTab(page, `/lightning/r/Account/${accts['A']}/view`);
    const snap = await ariaOf(page);
    console.log('DIAG acctpage aria len=' + snap.length + ' sections=' + JSON.stringify(snap.split('\n').map((l: string) => l.trim()).filter((l: string) => /heading|tab |row "/.test(l)).slice(0, 40)));
    expect(/heading "Devices on loan"/.test(snap), 'AC5 the customer page offers the Devices-on-loan related list').toBe(true);
    const rows = await sectionRowsPoll(page, 'Devices on loan');
    expect(rows.length, 'AC5 one row per CURRENT loan on the customer page (2 expected)').toBe(2);
    for (const [n, dueOff] of ([['1', -30], ['2', -15]] as Array<[string, number]>)) {
      const r = rows.find((t: string) => t.includes(dev(n)));
      expect(r != null, `AC5 device ${n} appears as a row on the customer page`).toBe(true);
      expect(String(r).includes(de(dueOff)), `AC5 the row for device ${n} carries its due date ${de(dueOff)}`).toBe(true);
      expect(String(r).includes(`SCRUM468-TEST-${n}`), `AC5 the row for device ${n} carries its serial`).toBe(true);
    }
    expect(rows.every((t: string) => !t.includes(dev('3'))), 'AC5 the returned loan of D3 is NOT listed as a current loan').toBe(true);
  });

  test('AC6 return clears the device side, loan keeps its three dates', async () => {
    const devRow = soql(`SELECT Status__c, Current_Customer__c FROM Demo_Devic__c WHERE Id='${devs['3']}'`);
    expect(devRow[0].Status__c, 'AC6 D3 shows status Available after the returns').toBe('Available');
    expect(devRow[0].Current_Customer__c, 'AC6 the current customer was cleared on D3').toBe(null);
    const loan = soql(
      `SELECT Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_Return_Datum__c, Loan_Duration_Days__c FROM Loan_Record__c WHERE Id='${loans.L3}'`
    );
    expect(loan.length, 'AC6 the returned loan still exists (history survives the return)').toBe(1);
    expect(loan[0].Loan_Start_Datum__c, 'AC6 start date kept').toBe(iso(-60));
    expect(loan[0].Loan_Due_Datum__c, 'AC6 due date kept').toBe(iso(-46));
    expect(loan[0].Loan_Return_Datum__c, 'AC6 actual return date recorded').toBe(iso(-46));
    expect(loan[0].Loan_Duration_Days__c, 'AC6 duration of a 14-day loan').toBe(14);
    const stillCurrent = soql(`SELECT Id FROM Loan_Record__c WHERE Loan_Customer__c='${accts.A}' AND Loan_Return_Datum__c=null`);
    expect(stillCurrent.map((r: any) => r.Id).sort(), 'AC6 only D1/D2 loans stay current for A').toEqual([loans.L1, loans.L2].sort());
  });

  test('AC7 device page shows the whole loan history', async ({ page }) => {
    const hist = soql(
      `SELECT Id, Loan_Customer__c, Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_Return_Datum__c, Loan_Duration_Days__c FROM Loan_Record__c WHERE Loan_Devic__c='${devs['3']}'`
    );
    expect(hist.length, 'fixture: D3 has 2 loans in its history').toBe(2);
    expect(hist.every((r: any) => r.Loan_Return_Datum__c != null), 'AC7 both loans of the Available D3 were returned').toBe(true);
    expect(
      hist.map((r: any) => r.Loan_Duration_Days__c).sort(),
      'AC7 history durations of D3 (14 and 14)',
    ).toEqual([14, 14]);
    // The criterion is the DEVICE RECORD PAGE: every loan the device ever had
    // must be listed there with its dates and the duration. Read from the
    // ariaSnapshot (the record body is a closed Shadow-Root).
    await openRelatedTab(page, `/lightning/r/Demo_Devic__c/${devs['3']}/view`);
    const snap = await ariaOf(page);
    console.log('DIAG devpage aria len=' + snap.length + ' lines=' + snap.split('\n').length + ' sections=' + JSON.stringify(snap.split('\n').map((l: string) => l.trim()).filter((l: string) => /heading|tab |row "/.test(l)).slice(0, 40)));
    const rows = await sectionRowsPoll(page, 'Loan records');
    const snap2 = await ariaOf(page);
    expect(rows.length, 'AC7 the device page lists one row per loan in its history (2 expected)').toBe(2);
    const isoToDe = (v: any) => String(v).slice(0, 10).replace(/(\d{4})-(\d{2})-(\d{2})/, '$3.$2.$1');
    for (const r of hist) {
      const who = Object.entries(accts).find(([, id]) => id === r.Loan_Customer__c)?.[0];
      expect(who != null, `AC7 fixture sanity: the loan's customer is one of ours`).toBe(true);
      const row = rows.find((t: string) => t.includes(cust(String(who))));
      expect(row != null, `AC7 the loan of customer ${who} appears in the device's history`).toBe(true);
      for (const label of ['start', 'due', 'return']) {
        const val = isoToDe(r[label === 'start' ? 'Loan_Start_Datum__c' : label === 'due' ? 'Loan_Due_Datum__c' : 'Loan_Return_Datum__c']);
        expect(String(row).includes(val), `AC7 the row of ${who} shows the ${label} date ${val}`).toBe(true);
      }
    }
    // AC7 also demands the DURATION of the loan (label measured via
    // FieldDefinition: "Loan duration in days").
    const cols = snap2.split('\n').map((l: string) => l.trim()).filter((l: string) => /columnheader/.test(l));
    expect(
      cols.some((c: string) => /duration/i.test(c)),
      `AC7 the loan history offers the duration column (columns rendered: ${JSON.stringify(cols).slice(0, 400)})`,
    ).toBe(true);
    // AC9 positive half stays here as the SOQL cross-check: the history of a
    // WRITTEN-OFF device survives its status change.
    const named = soql(`SELECT Id, Loan_Duration_Days__c, Loan_Return_Datum__c FROM Loan_Record__c WHERE Loan_Devic__c='${devs['4']}'`);
    expect(named.length, 'AC7 the written-off device still has its full history').toBe(2);
    expect(named.every((r: any) => r.Loan_Return_Datum__c != null), 'AC7 both written-off loans stay returned, not erased').toBe(true);
    expect(named.map((r: any) => r.Loan_Duration_Days__c).sort(), 'AC7 the two written-off loans keep their durations (25 and 28)').toEqual([25, 28]);
  });

  test('AC8+AC9 overdue ListView: exactly the overdue devices, all columns, longest first, no written-off row', async ({ page }) => {
    const flagged = soql(`SELECT Id, Name, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Status__c = 'Lent_Out'`)
      .filter((r: any) => Number(r.Current_Loan_Overdue_Days__c || 0) > 0);
    expect(flagged.length, 'org flags exactly 2 devices overdue').toBe(2);
    await listStatus(page, 2);
    const rows = await listRows(page);
    expect(rows.length, 'AC8 the list view shows exactly 2 record rows').toBe(2);
    const r1 = rows.find((t: string) => t.includes(dev('1')));
    const r2 = rows.find((t: string) => t.includes(dev('2')));
    expect(r1 != null && r2 != null, 'AC8 both overdue devices appear once').toBe(true);
    expect(rows.indexOf(String(r1)) < rows.indexOf(String(r2)), 'AC8 longest overdue first (30 days before 15)').toBe(true);
    for (const [row, serial, colleague, dueOff, days] of [
      [r1, 'SCRUM468-TEST-1', 'Meerwais Osmani', -30, '30'],
      [r2, 'SCRUM468-TEST-2', 'Integration User', -15, '15'],
    ] as Array<[string | null, string, string, number, string]>) {
      const rowText = String(row);
      expect(rowText.includes(serial), `AC8 row shows the serial (${serial})`).toBe(true);
      expect(rowText.includes(cust('A')), 'AC8 row shows the current customer').toBe(true);
      expect(rowText.includes(colleague), 'AC8 row shows the colleague who lent it').toBe(true);
      expect(rowText.includes(de(dueOff)), `AC8 row shows the due date ${de(dueOff)}`).toBe(true);
      expect(rowText.includes(days), `AC8 row shows days overdue ${days}`).toBe(true);
    }
    // AC9 negative half: written-off and available devices never in the view
    expect(rows.every((t: string) => !t.includes(dev('3')) && !t.includes(dev('4'))), 'AC9/AC8 no Available, no Written_Off row').toBe(true);
    // AC9 positive: D4 written off, history still there, lending refused
    expect(soql(`SELECT Status__c FROM Demo_Devic__c WHERE Id='${devs['4']}'`)[0].Status__c, 'AC9 D4 shows status Written_Off').toBe('Written_Off');
    const hist = soql(`SELECT Id FROM Loan_Record__c WHERE Loan_Devic__c='${devs['4']}'`);
    expect(hist.length, 'AC9 the written-off device still has its full history (2 loans)').toBe(2);
    const refused = failingRun(
      `sf data create record -s Loan_Record__c -v "Loan_Devic__c='${devs['4']}' Loan_Customer__c='${accts.C}' Loan_Colleague__c='${colleagueIds()[0]}' Loan_Start_Datum__c='${iso(-3)}' Loan_Due_Datum__c='${iso(1)}'" --target-org Test-Org --json`
    );
    expect(/written off and can never be lent out again/.test(refused), 'AC9 lending on the written-off device is refused').toBe(true);
    test
      .info()
      .annotations.push({
        type: 'observed',
        description: `AC8 list view: 2 rows (30 -> 15 days), ${flagged.length} org-flagged; DEV-0018/DEV-0019 absent; D4 history 2 loans, lend refused`,
      });
  });

  test('AC12 overdue stays put, nothing happens on its own', async ({ page }) => {
    const flagged = soql(`SELECT Id, Name, Status__c, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Status__c = 'Lent_Out'`)
      .filter((r: any) => Number(r.Current_Loan_Overdue_Days__c || 0) > 0);
    expect(flagged.map((r: any) => Number(r.Current_Loan_Overdue_Days__c)).sort(), 'AC12 org says 30 and 15 overdue days').toEqual([15, 30]);
    expect(flagged.length, 'AC12 still exactly 2 overdue devices').toBe(2);
    expect(flagged.every((r: any) => r.Status__c === 'Lent_Out'), 'AC12 no automation changed the status').toBe(true);
    const tasks = soql(`SELECT Id, Subject FROM Task WHERE Subject LIKE '%SCRUM-468%'`);
    expect(tasks.length, 'AC12 no Task was created for the overdue devices').toBe(0);
    // EmailMessage EXISTS in this org (Sales Cloud, measured via EntityDefinition) —
    // the negative test is therefore on the RECORDS: an overdue device must not have
    // generated one.
    const em = soql(`SELECT Id, Subject FROM EmailMessage`);
    expect(em.length, 'AC12 no EmailMessage record exists in Test-Org').toBe(0);
    // ScheduledJob is NOT readable by the Tester (verified 2026-10-16 SCRUM-449:
    // INVALID_TYPE via plain AND --use-tooling-api SOQL, Apex List<ScheduledJob>
    // does not compile) -> "nothing scheduled" cannot be measured here; the
    // manifest gate (no scheduled artefact on this branch) is the DevOps check.
    await listStatus(page, 2);
    const body = await page.evaluate('document.body.innerText');
    expect(/2 items •/.test(body), 'AC12 the second, fresh load still lists the 2 overdue devices').toBe(true);
    const rows12 = await listRows(page);
    expect(rows12.length, 'AC12 the fresh load still shows 2 rows').toBe(2);
    expect(rows12.some((r: string) => r.includes(de(-30))) && rows12.some((r: string) => r.includes(de(-15))), 'AC12 same due dates as the Apex ground truth (in list rows)').toBe(true);
  });
});
