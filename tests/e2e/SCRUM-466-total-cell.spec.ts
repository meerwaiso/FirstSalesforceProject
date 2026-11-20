import { test, expect, afterAll, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-466] Report total cell must be EMPTY when every cost in the group is
 * unknown — never "0,00 EUR" (PO rule in SCRUM-464: an unknown cost is never
 * printed as zero, and never counted into total/average).
 *
 * Reproduction comes from the bug ticket (Test-Org, no fixture needed for the
 * all-unknown half): Fabrikant "Miele" a07WU00001VNl6AYAT has 2 closed
 * third-party Cases (500WU000031cANeYAM, 500WU000031c0XyYAI) with empty
 * Drittparty_Fixkosten__c and Drittparty_Fixkosten_Known__c = 0.
 *
 * Session: frontdoor.jsp globalSetup (auth.setup.ts → storage-state.json),
 * baseURL from tests/e2e/org.ts. Never networkidle on Lightning.
 *
 * LOCATORS PROBED 2026-11-20 (house SCRUM-434/461 pattern, AX-tree probe):
 *   - /lightning/r/Report/<id>/view → iframe whose url contains lightningReportApp
 *   - group row first cell: '<fabrikant name>, unchecked, Select row for Drill Down.<name>'
 *   - column order in the row: label, count, sum ("Total Fixkosten (known)"),
 *     average ("Durchschnitt Fixkosten (known)")
 */

const ORG = 'Test-Org';
const P = 'TEST-466-';
const REPORTS = ['Faelle_Drittparty_Fabrikante', 'Faelle_Drittparty_Fabrikante_Meine'];

function shellJson(out: string): any {
  const i = out.indexOf('{');
  if (i < 0) throw new Error(`no json: ${out.slice(0, 400)}`);
  return JSON.parse(out.slice(i));
}
function sfRun(args: string): any {
  return shellJson(
    execSync(`export FORCE_COLOR=0; sf ${args} -o ${ORG} --json`, { maxBuffer: 1 << 26 }).toString(),
  ).result;
}
function soql(query: string): any[] {
  return sfRun(`data query --use-tooling-api -q "${query}"`).records;
}

// The Developer's all-unknown fixtures: never touched, only counted.
const MIELE_ID = 'a07WU00001VNl6AYAT';

async function reportFrame(page: Page, reportName: string) {
  const found = soql(`SELECT Id FROM Report WHERE Name = '${reportName}' LIMIT 1`);
  expect(found.length, `report '${reportName}' is not deployed in Test-Org`).toBeGreaterThan(0);
  await page.goto(`/lightning/r/Report/${found[0].Id}/view`, {
    waitUntil: 'domcontentloaded', timeout: 60_000,
  });
  await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60_000 });
  const deadline = Date.now() + 90_000;
  for (;;) {
    const frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) {
      await frame.locator('tr').first().waitFor({ timeout: 60_000 });
      return frame;
    }
    if (Date.now() > deadline) throw new Error('report iframe never appeared');
    await page.waitForTimeout(1000);
  }
}

async function rowCells(frame: any, fabrikantName: string): Promise<string[]> {
  for (const tr of await frame.locator('tr').all()) {
    const cells = await tr.locator('td, th').allTextContents();
    if (cells.length === 0) continue;
    const label = cells[0].replace(/\s+/g, ' ').trim();
    if (label === `${fabrikantName}, unchecked, Select row for Drill Down.${fabrikantName}`) return cells;
  }
  throw new Error(`no group row for '${fabrikantName}' in the report`);
}

/** German and US number rendering both parse. */
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

const fixtureIds: string[] = [];

function createCase(subjectTag: string, fabrikantId: string, cost: number | null): string {
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

function createRecord(sobject: string, values: string): string {
  const doc = sfRun(`data create record -s ${sobject} -v "${values}"`);
  const id = doc?.result?.id ?? doc?.id;
  if (!id) throw new Error(`create ${sobject} lieferte keine Id`);
  return String(id);
}
function updateRecord(sobject: string, id: string, values: string): void {
  sfRun(`data update record -s ${sobject} -i ${id} -v "${values}"`);
}
function deleteRecord(id: string): void {
  try {
    sfRun(`data delete record -s Case -i ${id}`);
  } catch {
    /* best effort — fixtures are named TEST-466-* */
  }
}

/** What the org says about one Fabrikant right now — the expectation, never a constant. */
function orgRow(fabrikantId: string): { count: number; sum: number | null; avg: number | null } {
  const rows = soql(
    `SELECT Closed_Last_12M__c, Drittparty_Fabrikant__c, Drittparty_Fixkosten__c, Drittparty_Fixkosten_Known__c ` +
    `FROM Case WHERE IsClosed = true AND Ursache__c = 'DrittpartyProdukt'`,
  ).filter((r) => String(r.Drittparty_Fabrikant__c) === fabrikantId && r.Closed_Last_12M__c === true);
  const known = rows.filter((r) => Number(r.Drittparty_Fixkosten_Known__c ?? 0) === 1);
  const sum = known.reduce((acc, r) => acc + Number(r.Drittparty_Fixkosten__c ?? 0), 0);
  return {
    count: rows.length,
    sum: known.length === 0 ? null : sum,
    avg: known.length === 0 ? null : sum / known.length,
  };
}

test.describe('SCRUM-466 — the report total cell never prints 0,00 for an all-unknown group');

test('[SCRUM-466][AC-total] all costs unknown => total cell empty, count and average still right', async ({ page }) => {
  const org = orgRow(MIELE_ID);
  expect(org.count, 'precondition: Miele must have closed all-unknown third-party cases in the window').toBeGreaterThan(0);
  expect(org.sum, 'precondition: every cost of the group is unknown (the NULL branch of the formula)').toBeNull();

  for (const reportName of REPORTS) {
    const frame = await reportFrame(page, reportName);
    const cells = await rowCells(frame, 'Miele');
    console.log(`SCRUM-466 rendered Miele row (${reportName}): ${JSON.stringify(cells)}`);
    const nums = toNumbers(cells.slice(1));
    // The count must be there (otherwise a missing row could pass silently)…
    expect(nums.includes(org.count), `${reportName}: Miele row does not show its case count ${org.count}`).toBe(true);
    // …and it must be the ONLY number: the average renders '-' and the total
    // cell must be empty. A rendered "0,00 EUR" adds a second number => red.
    expect(nums.length,
      `${reportName}: Miele row carries ${nums.length} numbers although every cost is unknown (only the count is allowed; a cost is never printed as 0,00)`).toBe(1);
  }
});

test('[SCRUM-466][control] one known cost in the group => the total cell prints that sum (blank would be the red)', async ({ page }) => {
  const id = await createCase('MIXED', MIELE_ID, 500);
  fixtureIds.push(id);
  const org = orgRow(MIELE_ID);
  expect(org.sum, 'precondition: the group now has a known cost').notToBeNull();

  for (const reportName of REPORTS) {
    const frame = await reportFrame(page, reportName);
    const cells = await rowCells(frame, 'Miele');
    console.log(`SCRUM-466 mixed Miele row (${reportName}): ${JSON.stringify(cells)}`);
    const nums = toNumbers(cells.slice(1));
    expect(nums.includes(org.count), `${reportName}: count after the known-cost fixture`).toBe(true);
    expect(nums.includes(org.sum as number),
      `${reportName}: a group with a known cost must print the total ${org.sum}`).toBe(true);
    expect(nums.includes(org.avg as number), `${reportName}: the average over known costs (${org.avg}) is printed`).toBe(true);
  }
});

afterAll(async () => {
  for (const id of fixtureIds) await deleteRecord(id);
  const left = soql(`SELECT Id FROM Case WHERE Subject LIKE '${P}%'`);
  expect(left.length, `fixtures ${P}* still in Test-Org after cleanup`).toBe(0);
});
