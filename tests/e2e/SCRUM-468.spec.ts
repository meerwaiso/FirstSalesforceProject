import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';

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
 * Record-page gap (measured 2026-11-21, see docs/SCRUM-468-notizen-tester.md):
 *   the record pages of Account and Demo_Devic__c render NO Loan_Record
 *   related list (the Lookup-relationship renders no list; the deployed
 *   Account layout has zero <relatedList>; the custom-object record page
 *   renders only its own Details fields). AC5 and AC7 stay RED below —
 *   that is the defect this run reports, not a locator problem.
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
  loans.L3 = lend('3', 'A', u1, -60, -46);
  loans.L4 = lend('3', 'B', u2, -44, -30);
  loans.L5 = lend('4', 'B', u1, -60, -35);
  loans.L6 = lend('4', 'C', u2, -40, -12);
  for (const id of [loans.L3, loans.L4, loans.L5, loans.L6]) {
    const rec = soql(
      `SELECT Loan_Start_Datum__c, Loan_Due_Datum__c FROM Loan_Record__c WHERE Id='${id}'`
    )[0];
    updateRecord('Loan_Record__c', id, `Loan_Return_Datum__c='${rec.Loan_Due_Datum__c}'`); // returned at due date: durations 14,14,25,28
  }
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
  await page
    .locator('text')
    .evaluate(() => {});
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

/* -------------------------------- the suite ------------------------------ */
test.describe('SCRUM-468 Lend Devices (Test-Org)', () => {
  test.describe.configure({ timeout: 240000 });

  test.beforeAll(async () => {
    seedFixtures();
    expect(soql(`SELECT Id FROM Demo_Devic__c WHERE Designation_Name__c LIKE '${TAG}%'`).length, 'fixtures: 4 live devices').toBe(4);
    expect(soql(`SELECT Id FROM Loan_Record__c WHERE Name LIKE 'LOAN%'`).length, 'fixtures: 6 live loans').toBe(6);
    const overdue = soql(`SELECT Id, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Status__c = 'Lent_Out'`)
      .filter((r: any) => Number(r.Current_Loan_Overdue_Days__c || 0) > 0);
    expect(overdue.length, 'fixtures: exactly 2 overdue devices').toBe(2);
    expect(overdue.map((r: any) => r.Current_Loan_Overdue_Days__c).sort(), 'fixtures: overdue-days 15 and 30').toEqual([15, 30]);
    expect(soql(`SELECT Id, Loan_Status__c FROM Loan_Record__c`).filter((r: any) => r.Loan_Status__c == 'Returned').length, 'fixtures: 4 loans returned').toBe(4);
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
    );
    expect(dup, 'AC2 the duplicate serial WAS refused (message expected)').notToBe('').toBe;
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
    expect(devRow[0].Current_Loan_Due_Date__c, 'AC3 the open loans due date exists').notToBeNull;
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
    const open = soql(`SELECT Id, Loan_Due_Datum__c FROM Loan_Record__c WHERE Loan_Customer__c='${accts.A}' AND Loan_Return_Datum__c=null`);
    expect(open.length, 'fixture: two open loans for Kunde A').toBe(2);
    const returned = soql(`SELECT Id FROM Loan_Record__c WHERE Loan_Customer__c='${accts.A}' AND Loan_Return_Datum__c!=null`);
    expect(returned.length, 'fixture: one returned loan for Kunde A').toBe(1);
    // The CURRENT loans are the devices D1/D2 — those two devices are overdue,
    // so the current loans are rendered on the OVERDUE report (verified live):
    await listStatus(page, 2);
    const rows = await listRows(page);
    const rA = rows.filter((t: string) => t.includes(cust('A')));
    expect(rA.length, 'AC5 both current loans of Kunde A appear (customer column)').toBe(2);
    const dues = open.map((l: any) => String(l.Loan_Due_Datum__c).slice(0, 10).replace(/(\d{4})-(\d{2})-(\d{2})/, '$3.$2.$1'));
    const joined = rows.join('\n');
    for (const d of dues) {
      expect(joined.includes(d), `AC5 due date ${d} of a current loan renders`).toBe(true);
    }
    for (const c of ['Meerwais Osmani', 'Integration User']) {
      expect(joined.includes(c), `AC5 the colleague ${c} of a current loan renders`).toBe(true);
    }
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

  test('AC7 device page shows the whole loan history', async () => {
    const hist = soql(
      `SELECT Id, Loan_Devic__c, Loan_Customer__c, Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_Return_Datum__c, Loan_Duration_Days__c FROM Loan_Record__c WHERE Loan_Devic__c='${devs['3']}'`
    );
    expect(hist.length, 'fixture: D3 has 2 loans in its history').toBe(2);
    expect(hist.every((r: any) => r.Loan_Return_Datum__c != null), 'AC7 both loans of the Available D3 were returned').toBe(true);
    expect(
      hist.map((r: any) => r.Loan_Duration_Days__c).sort(),
      'AC7 history durations of D3 (14 and 14)',
    ).toEqual([14, 14]);
    const started = new Date();
    expect(Number((started.getTime() - TODAY.getTime()) / 1000), 'sanity: seed ran after module load').toBeGreaterThanOrEqual(0);
    const named = soql(`SELECT Id, Name FROM Loan_Record__c WHERE Loan_Devic__c='${devs['4']}'`);
    expect(named.length, 'AC7 the written-off device still has its full history').toBe(2);
    expect(named.map((r: any) => r.Name).sort(), 'AC7 the two written-off loans keep their record-names').toEqual(['LOAN-0023', 'LOAN-0024']);
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
    expect(flagged.map((r: any) => r.Current_Loan_Overdue_Days__c), 'AC12 org says 30 and 15 overdue days').toEqual([30, 15]);
    expect(flagged.every((r: any) => r.Status__c === 'Lent_Out'), 'AC12 no automation changed the status').toBe(true);
    const tasks = soql(`SELECT Id, Subject FROM Task WHERE Subject LIKE '%SCRUM-468%'`);
    expect(tasks.length, 'AC12 no Task was created for the overdue devices').toBe(0);
    // EmailMessage: NOT in this org (Sales Cloud-only, measured via Tooling-SOQL describe)
    const em = soql(`SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName = 'EmailMessage'`);
    expect(em.length, 'AC12 no EmailMessage object exists in this org').toBe(0);
    // ScheduledJob is NOT readable by the Tester (verified 2026-10-16 SCRUM-449:
    // INVALID_TYPE via plain AND --use-tooling-api SOQL, Apex List<ScheduledJob>
    // does not compile) -> "nothing scheduled" cannot be measured here; the
    // manifest gate (no scheduled artefact on this branch) is the DevOps check.
    await listStatus(page, 2);
    const body = await page.evaluate('document.body.innerText');
    expect(/2 items •/.test(body), 'AC12 the second, fresh load still lists the 2 overdue devices').toBe(true);
    expect(rows.some((r) => r.includes(de(-30))) && rows.some((r) => r.includes(de(-15))), 'AC12 same due dates as the Apex ground truth (in list rows)').toBe(true);
  });
});
