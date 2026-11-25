import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import * as fs from 'fs';
import { openRecordPage, openDetailsTab } from './record-page';
import { requireData } from './preflight';

/**
 * [SCRUM-477] Tage jetzige Stage — days an open deal sits in its current Stage,
 * plus the Report "Sales/Chancen_Over_30_Tage" (open deals, strictly over 30 days,
 * longest stuck first).
 *
 * Covered here (E2E, Test-Org): AC1 age on the record, AC2 reset on a forward
 * Stage change, AC3 reset on a backward Stage change, AC4 current without
 * maintenance, AC5 pre-existing record carries its real stage-change date,
 * AC6 the stuck list (rows, five values, longest first), AC7 Won/Lost never
 * listed, AC8 the counter cannot be edited, AC10 nothing else happens.
 *
 * NOT here — Apex classes run by the Tester (see the Jira report):
 *   AC9 negative FLS access (needs a user without the Permission Set; both
 *      Salesforce licences of this Developer Edition org are held by System
 *      Administrators, so a second UI session is impossible — System.runAs is
 *      the house route), plus the formula/boundary semantics of AC6.
 *
 * Locators VERIFIED on this org (probe run 2026-11-25, this ticket):
 *   - Record page Details tab renders the counter as a listitem:
 *     "Tage jetzige Stage 40"; the field has NO "Edit Tage jetzige Stage"
 *     button (count 0) while the mutable Stage field in the same section has
 *     "Edit Stage" (count 1).
 *   - Stage inline edit (house, verified SCRUM-459 on this same object):
 *     button 'Edit Stage' -> getByLabel('Stage', {exact:true}).nth(0) combobox
 *     -> getByRole('option', {name:'<value>', exact:true}) -> button 'Save'.
 *   - Report: /lightning/r/Report/00OWU00000RnrLN2AZ/view, frame url contains
 *     'lightningReportApp'; header row 'th' cells carry the column labels;
 *     group rows carry the day count in a 'th' cell
 *     ("144, unchecked, Select row for Drill Down.144(13)") and their detail
 *     rows follow as 4 'td' cells [opportunity, owner, stage, amount].
 *     The frame header states "Total Records 76" (the org's own row count).
 *   - Amount renders in the German locale ("250.000,00 €"; "-" when null).
 *
 * Fixtures are NOT seeded: the day counts of this story are anchored on record
 * history (LastStageChangeDate / CreatedDate) and a record created today would
 * show 0 days, which cannot prove a reset. So the spec picks still-aged records
 * by SOQL at run time and records the ones it mutates in a used-list, so a re-run
 * takes the next record instead of re-testing an already-reset one.
 */

const FIELD_LABEL = 'Tage jetzige Stage';
const API_FIELD = 'Stage_Days_In_Current_Stage__c';
const REPORT_ID = '00OWU00000RnrLN2AZ';
const USED_FILE = '.e2e-run/scrum477-used.json';
const GO_LIVE = '2026-11-25'; // field deployed to Test-Org on this date (Developer deploy log)

function shell(cmd: string): string {
  return execSync(cmd, {
    encoding: 'utf-8',
    timeout: 240000,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
}
function soql(q: string): any[] {
  const out = shell(`sf data query --query ${JSON.stringify(q)} --target-org Test-Org --json`);
  const clean = out.replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  return JSON.parse(clean.slice(clean.indexOf('{'), clean.lastIndexOf('}') + 1)).result.records;
}

/** Calendar date (YYYY-MM-DD) the org evaluates TODAY() in — user tz is Europe/Berlin. */
function orgDateOf(iso: string): string {
  const d = new Date(iso);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Berlin' }).format(d);
}
function orgToday(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Berlin' }).format(new Date());
}
function dayDiff(fromIso: string, toIso: string): number {
  const a = new Date(orgDateOf(fromIso) + 'T00:00:00');
  const b = new Date(toIso + 'T00:00:00');
  return Math.round((b.getTime() - a.getTime()) / 86400000);
}
function todayMinus(anchorIso: string): number {
  return dayDiff(anchorIso, orgToday());
}

function readUsed(): string[] {
  try {
    return JSON.parse(fs.readFileSync(USED_FILE, 'utf-8'));
  } catch {
    return [];
  }
}
function markUsed(id: string) {
  const used = readUsed();
  if (!used.includes(id)) {
    used.push(id);
    fs.writeFileSync(USED_FILE, JSON.stringify(used));
  }
}

/** The aged record this spec may mutate: open, >30 days, not already used. */
function pickAged(stage: string | null): any {
  const used = readUsed();
  const stageClause = stage ? ` AND StageName = ${JSON.stringify(stage).replace(/"/g, "'")}` : '';
  const rows = soql(
    `SELECT Id, Name, StageName, Amount, OwnerId, CreatedDate, LastStageChangeDate, ${API_FIELD} ` +
    `FROM Opportunity WHERE ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'${stageClause}`
  );
  const fresh = rows.filter((r) => !used.includes(r.Id));
  const where = stage ? `in stage ${stage} ` : '';
  expect(fresh.length, `AC-Fixture: kein open record ${where}with days>30 left that this spec has not mutated already`).toBeGreaterThan(0);
  return fresh[0];
}

async function readCounter(page: any): Promise<number> {
  const forms = page.locator('div.slds-form-element');
  const n = await forms.count();
  for (let i = 0; i < n; i++) {
    const el = forms.nth(i);
    const inner = (await el.innerText().catch(() => '')).replace(/\s+/g, ' ').trim();
    if (inner.includes(FIELD_LABEL)) {
      const m = inner.match(/Tage jetzige Stage\s*([\d.,-]+)/);
      if (m) return parseInt(m[1].replace(/[^\d-]/g, ''), 10);
      throw new Error(`"${FIELD_LABEL}" renders ohne数字 — innerText: ${inner}`);
    }
  }
  throw new Error(`kein slds-form-element with "${FIELD_LABEL}" — Details-Tab not open or field missing`);
}

async function openCounterPage(page: any, id: string): Promise<number> {
  await openRecordPage(page, `/lightning/r/Opportunity/${id}/view`);
  await openDetailsTab(page as any);
  return await readCounter(page);
}

async function changeStage(page: any, id: string, targetStage: string) {
  await openRecordPage(page, `/lightning/r/Opportunity/${id}/view`);
  await openDetailsTab(page as any);
  const editBtn = page.getByRole('button', { name: 'Edit Stage', exact: true });
  await expect(editBtn, `no 'Edit Stage' button on ${id}`).toBeVisible({ timeout: 20000 });
  await editBtn.click();
  await page.waitForTimeout(1500);
  const combo = page.getByLabel('Stage', { exact: true }).nth(0);
  await expect(combo).toBeVisible({ timeout: 20000 });
  await combo.click();
  await page.waitForTimeout(1500);
  const option = page.getByRole('option', { name: targetStage, exact: true });
  await expect(option, `stage option '${targetStage}' not offered`).toBeVisible({ timeout: 20000 });
  await option.click();
  await page.waitForTimeout(1000);
  const save = page.getByRole('button', { name: 'Save', exact: true });
  await expect(save).toBeVisible({ timeout: 20000 });
  await save.click();
  await page.waitForTimeout(4000);
}

async function reportFrame(page: any): Promise<any> {
  await openRecordPage(page, `/lightning/r/Report/${REPORT_ID}/view`);
  let frame = null;
  const deadline = Date.now() + 90000;
  while (!frame && Date.now() < deadline) {
    frame = page.frames().find((f: any) => f.url().includes('lightningReportApp'));
    if (!frame) await page.waitForTimeout(1000);
  }
  expect(frame, 'no report frame (lightningReportApp)').toBeTruthy();
  await frame.waitForLoadState('domcontentloaded');
  await frame.locator('table tbody tr').first().waitFor({ timeout: 60000 });
  // The widget loads its rows lazily; poll until the row count stops growing.
  let prev = -1;
  for (let i = 0; i < 12; i++) {
    await page.waitForTimeout(4000);
    const c = await frame.locator('table tbody tr').count();
    if (c === prev && i > 1) break;
    prev = c;
  }
  return frame;
}

/** {groups:[{day,count}], rows:[{name,owner,stage,amount,underDay}]} from the rendered grid. */
async function readReport(frame: any) {
  const tables = await frame.locator('table').count();
  const grid = frame.locator('table').nth(tables - 1);
  const rowsLoc = grid.locator('tbody tr');
  const n = await rowsLoc.count();
  const groups: { day: number; count: number }[] = [];
  const rows: { name: string; owner: string; stage: string; amount: string; underDay: number }[] = [];
  let currentDay = Number.NaN;
  for (let i = 0; i < n; i++) {
    const th = (await rowsLoc.nth(i).locator('th').allTextContents()).map((c: string) => c.replace(/\s+/g, ' ').trim());
    const td = (await rowsLoc.nth(i).locator('td').allTextContents()).map((c: string) => c.replace(/\s+/g, ' ').trim());
    const groupHeader = th.filter((t: string) => /^\d+/.test(t) && /\((\d+)\)/.test(t) && !/Subtotal|Total/i.test(t));
    if (groupHeader.length > 0) {
      const h = groupHeader[0];
      const day = parseInt(h.match(/^(\d+)/)![1], 10);
      const cnt = parseInt(h.match(/\((\d+)\)/)![1], 10);
      groups.push({ day, count: cnt });
      currentDay = day;
    }
    if (td.length >= 4 && td[0]) rows.push({ name: td[0], owner: td[1], stage: td[2], amount: td[3], underDay: currentDay });
  }
  const bodyText = await frame.locator('body').innerHtml();
  const totalMatch = bodyText.replace(/\s+/g, ' ').match(/Total Records\s*(\d+)/);
  const headerCells = grid.locator('thead tr th');
  const headerRow = (await headerCells.allTextContents()).map((c: string) => c.replace(/\s+/g, ' ').trim());
  return { groups, rows, total: totalMatch ? parseInt(totalMatch[1], 10) : -1, headerRow };
}

/* =========================== preconditions, once ========================== */

test.beforeAll(async () => {
  await requireData([
    {
      ac: 'AC1/AC5',
      what: 'an open record with a REAL earlier stage change (LastStageChangeDate set) and days>30',
      soql: `SELECT Id FROM Opportunity WHERE LastStageChangeDate != null AND ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'`,
      min: 1,
    },
    {
      ac: 'AC4',
      what: 'an open record with no stage change at all (counter anchored on CreatedDate) and days>30',
      soql: `SELECT Id FROM Opportunity WHERE LastStageChangeDate = null AND ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'`,
      min: 1,
    },
    {
      ac: 'AC2',
      what: 'an aged open record in stage Prospecting to move forward',
      soql: `SELECT Id FROM Opportunity WHERE ${API_FIELD} > 30 AND StageName = 'Prospecting'`,
      min: 1,
    },
    {
      ac: 'AC3',
      what: 'an aged open record in a later stage (Qualification) to move backward',
      soql: `SELECT Id FROM Opportunity WHERE ${API_FIELD} > 30 AND StageName = 'Qualification'`,
      min: 1,
    },
    {
      ac: 'AC10',
      what: 'aged open records left for the mutation tests (3 needed)',
      soql: `SELECT Id FROM Opportunity WHERE ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'`,
      min: 3,
    },
    {
      ac: 'AC6',
      what: 'open records strictly over 30 days for the stuck list',
      soql: `SELECT Id FROM Opportunity WHERE ${API_FIELD} > 30`,
      min: 1,
    },
    {
      ac: 'AC7',
      what: 'closed (Won/Lost) records whose stage age is over 30 days',
      soql: "SELECT Id FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost') AND LastStageChangeDate != null",
      min: 1,
    },
  ]);
});

/* ============================ the acceptance tests ======================== */

test.describe('[SCRUM-477] AC6 — stuck list: rows, five values, longest first', () => {
  test('AC6: Report row count = SOQL count, day group = the record counter, Desc order', async ({ page }) => {
    const truth = soql(`SELECT Id, Name, StageName, Amount, OwnerId, ${API_FIELD} FROM Opportunity WHERE ${API_FIELD} > 30`);
    const closed = soql(`SELECT Id FROM Opportunity WHERE ${API_FIELD} > 30 AND (StageName = 'Closed Won' OR StageName = 'Closed Lost')`);
    const byName: Record<string, number[]> = {};
    for (const r of truth) byName[r.Name] = [...(byName[r.Name] || []), r[API_FIELD]];
    const countByDay: Record<number, number> = {};
    for (const r of truth) countByDay[r[API_FIELD]] = (countByDay[r[API_FIELD]] || 0) + 1;

    const frame = await reportFrame(page);
    const grid = await readReport(frame);
    console.log(`[AC6] SOQL=${truth.length} closed-in-filter=${closed.length}; UI total=${grid.total}; groups=${JSON.stringify(grid.groups)}; rows=${grid.rows.length}`);

    // exactly M rows, M counted in Test-Org at this moment
    expect(grid.total, `Report "Total Records ${grid.total}" ≠ SOQL ${truth.length} open records over 30 days`).toBe(truth.length);
    expect(grid.rows.length > 0, 'no detail row rendered at all').toBe(true);

    // the day counter is the group label and its count matches the org
    expect(grid.groups.length > 0, 'no group header rendered — the day count is not shown').toBe(true);
    const maxDay = Math.max(...truth.map((r) => r[API_FIELD]));
    expect(grid.groups[0].day, `first group ${grid.groups[0].day} ≠ org max ${maxDay} (longest stuck must be first)`).toBe(maxDay);
    expect(grid.groups[0].count, `group ${grid.groups[0].day} shows ${grid.groups[0].count} records, SOQL says ${countByDay[grid.groups[0].day]}`).toBe(countByDay[grid.groups[0].day]);
    for (let i = 1; i < grid.groups.length; i++) {
      expect(grid.groups[i].day < grid.groups[i - 1].day, `group order not descending: ${grid.groups[i - 1].day} then ${grid.groups[i].day}`).toBe(true);
      expect(grid.groups[i].day > 30, `a group of ${grid.groups[i].day} days is listed — the filter is strictly over 30`).toBe(true);
    }

    // every rendered row sits under the group of ITS OWN day count
    for (const row of grid.rows) {
      const days = byName[row.name];
      expect(days, `rendered row "${row.name}" is not an org record with days>30`).toBeTruthy();
      expect(days!.includes(row.underDay), `"${row.name}" (org days ${JSON.stringify(days)}) listed under group ${row.underDay}`).toBe(true);
    }

    // the five values: four detail columns + the day count as the group label
    const headerText = JSON.stringify(grid.headerRow);
    for (const label of ['Opportunity Name', 'Opportunity Owner', 'Stage', 'Amount', FIELD_LABEL]) {
      expect(headerText.includes(label), `column/group label "${label}" missing in the header row`).toBe(true);
    }
  });
});

test.describe('[SCRUM-477] AC7 — Won/Lost never on the list', () => {
  test('AC7: no Closed Won/Lost stage cell, no closed deal named', async ({ page }) => {
    const closedOld = soql(`SELECT Id, Name, StageName, Amount, CreatedDate, LastStageChangeDate FROM Opportunity WHERE (StageName = 'Closed Won' OR StageName = 'Closed Lost') AND ${API_FIELD} > 30`);
    const closedAged = soql(`SELECT Id, Name, StageName, Amount, CreatedDate, LastStageChangeDate FROM Opportunity WHERE (StageName = 'Closed Won' OR StageName = 'Closed Lost')`);
    const aged = closedAged.filter((r) => {
      const anchor = r.LastStageChangeDate || r.CreatedDate;
      return anchor && todayMinus(anchor) > 30;
    });
    const closedNames = new Set(aged.map((r) => r.Name));
    const counterOnClosed = closedOld.length;

    const frame = await reportFrame(page);
    const grid = await readReport(frame);
    const names = grid.rows.map((r) => r.name);
    const hitClosedStage = grid.rows.filter((r) => r.stage === 'Closed Won' || r.stage === 'Closed Lost');
    const hitClosedName = names.filter((nm) => closedNames.has(nm));
    console.log(`[AC7] closed deals aged>30=${aged.length}; counter!=null on closed=${counterOnClosed}; rendered rows=${grid.rows.length}; rows with closed stage=${JSON.stringify(hitClosedStage.map((r) => r.name))}; closed names on list=${JSON.stringify(hitClosedName)}`);

    expect(aged.length, 'AC7 precondition: no closed deal in Test-Org has an age over 30 days — nothing to exclude').toBeGreaterThan(0);
    expect(hitClosedStage.length, `a rendered row shows a closed stage (${JSON.stringify(hitClosedStage.map((r) => r.name))})`).toBe(0);
    expect(hitClosedName.length, `a closed deal aged over 30 days is on the list (${JSON.stringify(hitClosedName)})`).toBe(0);
    expect(counterOnClosed, `${counterOnClosed} closed records carry a day counter — closed deals must never be listable`).toBe(0);
  });
});

test.describe('[SCRUM-477] AC1 — age of the current stage on the record page', () => {
  test('AC1: open deal last changed on D shows today minus D', async ({ page }) => {
    const rows = soql(`SELECT Id, Name, StageName, Amount, CreatedDate, LastStageChangeDate, ${API_FIELD} FROM Opportunity WHERE LastStageChangeDate != null AND ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'`);
    const rec = rows[0];
    expect(rec, 'AC1 precondition: no open record with a real LastStageChangeDate').toBeTruthy();
    const expected = todayMinus(rec.LastStageChangeDate);

    const ui = await openCounterPage(page, rec.Id);
    console.log(`[AC1] ${rec.Name}: LastStageChangeDate=${rec.LastStageChangeDate} SOQL counter=${rec[API_FIELD]} expected today-D=${expected} UI=${ui}`);

    expect(ui, `UI shows ${ui}, today minus ${rec.LastStageChangeDate} = ${expected}`).toBe(expected);
    expect(rec[API_FIELD], `SOQL counter ${rec[API_FIELD]} ≠ today minus D (${expected})`).toBe(expected);
    expect(ui !== 0, 'a record whose stage changed in the past shows 0').toBe(true);
  });
});

test.describe('[SCRUM-477] AC4 — current without maintenance (nobody touched the record)', () => {
  test('AC4: untouched deal shows today minus its last stage change', async ({ page }) => {
    const rows = soql(`SELECT Id, Name, StageName, CreatedDate, LastStageChangeDate, ${API_FIELD} FROM Opportunity WHERE LastStageChangeDate = null AND ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'`);
    const rec = rows[0];
    expect(rec, 'AC4 precondition: no aged record without a stage change exists').toBeTruthy();
    expect(rec.LastStageChangeDate, `fixture already carries a stage change (${rec.LastStageChangeDate}) — the anchor is not CreatedDate`).toBeFalsy();
    const expected = todayMinus(rec.CreatedDate); // stage never changed: it began at creation

    const ui = await openCounterPage(page, rec.Id);
    console.log(`[AC4] ${rec.Name}: created=${rec.CreatedDate} LastStageChangeDate=${rec.LastStageChangeDate} SOQL=${rec[API_FIELD]} UI=${ui} expected=${expected}`);
    expect(ui, `UI ${ui} ≠ today minus CreatedDate (${expected}) — nobody edited the record`).toBe(expected);
    expect(rec[API_FIELD], `SOQL ${rec[API_FIELD]} ≠ ${expected}`).toBe(expected);
    expect(ui !== 0, 'an aged record shows 0 without being touched').toBe(true);
  });
});

test.describe('[SCRUM-477] AC5 — existing record carries its real stage-change date', () => {
  test('AC5: counter reflects a change made before go-live, not the go-live date', async ({ page }) => {
    const rows = soql(`SELECT Id, Name, StageName, CreatedDate, LastStageChangeDate, ${API_FIELD} FROM Opportunity WHERE LastStageChangeDate != null AND ${API_FIELD} > 30 AND StageName != 'Closed Won' AND StageName != 'Closed Lost'`);
    const rec = rows[0];
    expect(rec, 'AC5 precondition: no record with a real stage-change history').toBeTruthy();
    expect(rec.LastStageChangeDate.slice(0, 10) < GO_LIVE, `the change (${rec.LastStageChangeDate}) is not older than go-live ${GO_LIVE}`).toBe(true);
    const byChange = todayMinus(rec.LastStageChangeDate);
    const byCreated = todayMinus(rec.CreatedDate);

    const ui = await openCounterPage(page, rec.Id);
    console.log(`[AC5] ${rec.Name}: change=${rec.LastStageChangeDate} created=${rec.CreatedDate} UI=${ui} byChange=${byChange} byCreated=${byCreated} goLive=0`);

    expect(ui, `UI ${ui} ≠ today minus the real change date (${byChange})`).toBe(byChange);
    expect(rec[API_FIELD], `counter ${rec[API_FIELD]} ≠ today minus change date (${byChange})`).toBe(byChange);
    expect(byCreated === byChange, 'the anchor is ambiguous (change date = created date) — this proves nothing').not.toBe(true);
    expect(ui !== 0, 'the counter restarted at go-live instead of carrying the real history').not.toBe(true);
  });
});

test.describe('[SCRUM-477] AC2 — reset on a forward Stage change (UI save)', () => {
  test('AC2: Prospecting → Proposal/Price Quote restarts the counter at 0', async ({ page }) => {
    const rec = pickAged('Prospecting');
    const before = rec[API_FIELD];
    expect(before > 30, `fixture shows ${before} days — must be over 30 to prove a reset`).toBe(true);
    markUsed(rec.Id);

    await changeStage(page, rec.Id, 'Proposal/Price Quote');

    const after = soql(`SELECT Id, Name, StageName, LastStageChangeDate, ${API_FIELD} FROM Opportunity WHERE Id = '${rec.Id}'`)[0];
    const ui = await openCounterPage(page, rec.Id);
    console.log(`[AC2] ${rec.Name}: ${before} days at Prospecting → UI ${ui}, StageName=${after.StageName}, LastStageChangeDate=${after.LastStageChangeDate}, SOQL counter=${after[API_FIELD]}`);

    expect(after.StageName, `Stage did not move: still ${after.StageName}`).toBe('Proposal/Price Quote');
    expect(after.LastStageChangeDate != null, 'no LastStageChangeDate after a Stage change').toBe(true);
    expect(after.LastStageChangeDate.slice(0, 10)).toBe(orgToday());
    expect(after[API_FIELD], `counter ${after[API_FIELD]} ≠ 0 after a change today`).toBe(0);
    expect(ui, `UI shows ${ui}, expected 0`).toBe(0);
    expect(ui < before, `counter kept the old age (${ui} ≥ ${before})`).toBe(true);
  });
});

test.describe('[SCRUM-477] AC3 — reset on a backward Stage change (UI save)', () => {
  test('AC3: Qualification → Prospecting (earlier) also restarts at 0', async ({ page }) => {
    const rec = pickAged('Qualification');
    const before = rec[API_FIELD];
    expect(before > 30, `fixture shows ${before} days — must be over 30`).toBe(true);
    markUsed(rec.Id);

    await changeStage(page, rec.Id, 'Prospecting');

    const after = soql(`SELECT Id, Name, StageName, LastStageChangeDate, ${API_FIELD} FROM Opportunity WHERE Id = '${rec.Id}'`)[0];
    const ui = await openCounterPage(page, rec.Id);
    console.log(`[AC3] ${rec.Name}: ${before} days at Qualification → UI ${ui}, StageName=${after.StageName}, LastStageChangeDate=${after.LastStageChangeDate}, SOQL=${after[API_FIELD]}`);

    expect(after.StageName, `Stage did not move back: still ${after.StageName}`).toBe('Prospecting');
    expect(after.LastStageChangeDate != null, 'no LastStageChangeDate after the backward change').toBe(true);
    expect(after.LastStageChangeDate.slice(0, 10)).toBe(orgToday());
    expect(after[API_FIELD], `counter ${after[API_FIELD]} ≠ 0`).toBe(0);
    expect(ui, `UI ${ui} ≠ 0 — a backward move kept the old count`).toBe(0);
  });
});

test.describe('[SCRUM-477] AC8 — nobody can edit the number', () => {
  test('AC8: the counter has no edit affordance while Stage has one, and shows its value', async ({ page }) => {
    const rec = pickAged(null);
    expect(rec[API_FIELD] > 30, 'fixture must show a number').toBe(true);

    await openRecordPage(page, `/lightning/r/Opportunity/${rec.Id}/view`);
    await openDetailsTab(page as any);

    const dayEditBtn = page.getByRole('button', { name: `Edit ${FIELD_LABEL}`, exact: true });
    const stageEditBtn = page.getByRole('button', { name: 'Edit Stage', exact: true });
    const dayInputs = page.getByRole('textbox', { name: FIELD_LABEL, exact: true });
    const dayCombo = page.getByRole('combobox', { name: FIELD_LABEL, exact: true });
    const uiValue = await readCounter(page);

    console.log(`[AC8] ${rec.Name}: 'Edit Tage jetzige Stage'=${await dayEditBtn.count()}, 'Edit Stage'=${await stageEditBtn.count()}, textbox=${await dayInputs.count()}, combobox=${await dayCombo.count()}, value=${uiValue} (SOQL ${rec[API_FIELD]})`);

    expect(await stageEditBtn.count(), 'the mutable Stage field itself has no Edit button — the probe is useless, the Details tab is not rendered as verified').toBeGreaterThan(0);
    expect(await dayEditBtn.count(), `the day counter offers an edit button (${await dayEditBtn.count()}) — it must not be writable`).toBe(0);
    expect(await dayCombo.count(), `a combobox for "${FIELD_LABEL}" exists`).toBe(0);
    expect(await dayInputs.count(), `a textbox for "${FIELD_LABEL}" exists`).toBe(0);
    expect(uiValue, `the value ${uiValue} is not the org value ${rec[API_FIELD]}`).toBe(rec[API_FIELD]);
  });
});

test.describe('[SCRUM-477] AC10 — a Stage change causes nothing else', () => {
  test('AC10: only Stage + platform fields move; no email, task, FeedItem or job', async ({ page }) => {
    const FIELDS = ['Name', 'Amount', 'Description', 'Owner', 'CreatedDate', 'StageName', 'LastStageChangeDate',
      API_FIELD, 'Risk_Reason__c', 'Risk_Level__c', 'Last_Risk_Evaluation__c', 'Last_User_Change__c',
      'Highest_Stage_Reached__c', 'Followup_Required__c', 'Followup_Status__c', 'Overdue_Followup_Count__c',
      'Next_Followup_Date__c', 'Is_Overdue__c', 'Days_Close_Date_Overdue__c', 'Is_Close_Date_Overdue__c',
      'Inactive_Days__c', 'Approval_Waiting_Days__c', 'Needs_Manager_Attention__c'];
    // Fields another story's automation owns: allowed to move, but they must be named.
    const FOREIGN_KNOWN = ['Risk_Reason__c', 'Risk_Level__c', 'Last_Risk_Evaluation__c', 'Last_User_Change__c',
      'Highest_Stage_Reached__c', 'Followup_Required__c', 'Followup_Status__c', 'Overdue_Followup_Count__c',
      'Next_Followup_Date__c', 'Is_Overdue__c', 'Days_Close_Date_Overdue__c', 'Is_Close_Date_Overdue__c',
      'Inactive_Days__c', 'Approval_Waiting_Days__c', 'Needs_Manager_Attention__c'];
    const sideEffects = (): Record<string, number> => ({
      email: soql('SELECT Id FROM EmailMessage').length,
      outbox: soql('SELECT Id FROM OutboxMessage').length,
      jobs: soql('SELECT Id FROM AsyncApexJob').length,
      flowJobs: soql('SELECT Id FROM ProcessAutomationJob').length,
      feed: soql('SELECT Id FROM FeedItem').length,
    });
    const rec = pickAged('Prospecting');
    expect(rec[API_FIELD] > 30, 'fixture must be aged before the change').toBe(true);
    const before = soql(`SELECT ${FIELDS.join(', ')} FROM Opportunity WHERE Id = '${rec.Id}'`)[0];
    const effectsBefore = sideEffects();
    markUsed(rec.Id);

    await changeStage(page, rec.Id, 'Needs Analysis');

    const after = soql(`SELECT ${FIELDS.join(', ')} FROM Opportunity WHERE Id = '${rec.Id}'`)[0];
    const effectsAfter = sideEffects();
    const changed = FIELDS.filter((f) => JSON.stringify(before[f]) !== JSON.stringify(after[f]));
    const own = new Set(['StageName', 'LastStageChangeDate', API_FIELD]);
    const foreignChanged = changed.filter((f) => !own.has(f));
    const unexpected = changed.filter((f) => !own.has(f) && !FOREIGN_KNOWN.includes(f));
    const growth: Record<string, number> = {};
    for (const k of Object.keys(effectsAfter)) growth[k] = effectsAfter[k] - effectsBefore[k];
    console.log(`[AC10] ${rec.Name}: changed fields=${JSON.stringify(changed)} unexpected=${JSON.stringify(unexpected)} foreignAutomation=${JSON.stringify(foreignChanged)} counter=${after[API_FIELD]} LastStageChangeDate=${after.LastStageChangeDate} sideEffectGrowth=${JSON.stringify(growth)}`);

    expect(after.StageName).toBe('Needs Analysis');
    expect(after[API_FIELD], `counter ${after[API_FIELD]} ≠ 0 after a change today`).toBe(0);
    expect(after.LastStageChangeDate!.slice(0, 10)).toBe(orgToday());
    expect(unexpected, `fields outside this feature's reach changed: ${JSON.stringify(unexpected)}`).toEqual([]);
    expect(growth.email, `EmailMessages grew by ${growth.email}`).toBe(0);
    expect(growth.outbox, `OutboxMessages grew by ${growth.outbox}`).toBe(0);
    expect(growth.jobs, `AsyncApexJobs grew by ${growth.jobs}`).toBe(0);
    expect(growth.flowJobs, `ProcessAutomationJobs grew by ${growth.flowJobs}`).toBe(0);
    expect(growth.feed, `FeedItems grew by ${growth.feed} — a stage save must not post to any feed`).toBe(0);
    // Nothing in the delta can cause side effects: no SCRUM-477 trigger, flow or
    // weblink exists (measured: ApexTrigger has no SCRUM477 name, FlowRecord = 0 rows).
    const ownTrigger = soql('SELECT Id FROM ApexTrigger').filter((t) => /477|StageDays|CurrentStageDays/i.test(String(t.Name)));
    expect(ownTrigger.length, `this feature shipped a trigger/flow (${JSON.stringify(ownTrigger.map((t) => t.Name))})`).toBe(0);
  });
});
