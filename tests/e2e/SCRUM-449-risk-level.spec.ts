import { test, expect } from '@playwright/test';
import { openRecordDetails } from './record-page';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-449] E2E: automatic Risk Level on Opportunity — the UI half of the
 * acceptance criteria (Apex SCRUM449OpportunityRiskTest / SCRUM449OpportunityRiskFlsTest
 * cover the rule engine, the bulk path and the FLS pair).
 *
 * Covered here (UI only):
 *   AC1/AC2/AC3/AC4/AC5  the risk assessment is VISIBLE on the Opportunity record
 *                        (label + value + reason text) — the PO demands it
 *                        "directly on the Opportunity record".
 *   AC7/AC8              closed / healthy records carry no risk level and never
 *                        appear in the High-risk list.
 *   AC10/AC12            the fields are usable as filter: the deployed list view
 *                        lists EVERY High-risk open record organisation-wide.
 *
 * NOT here (Apex, with my name on it):
 *   AC6 (recalculation on user change), AC9 (nobody can write the fields),
 *   AC11 (bulk 200), plus the C1..C4 rule table and the stage-order map.
 *
 * Locators VERIFIED via probe on 2026-10-15 (record 006WU00000Q2RZqYAN):
 *   - Details tab: house helper openRecordDetails.
 *   - List view: /lightning/o/Opportunity/list?filterName=Hoeh_Risk_Chancen
 *   - Rows live in a CLOSED shadow root: innerTxt() returns "" for them, ariaSnapshot()
 *     is the read that works. Each cell renders VALUE BEFORE LABEL
 *     ("24 Locked Inactive Days High Locked Risk Level"), so no adjacency regex.
 *   - Row 0 is the header row; 14 records => 15 rows.
 */

const RISK_LEVEL_LABEL = 'Risk Level';
const RISK_REASON_LABEL = 'Risk Reason';
const INACTIVE_DAYS_LABEL = 'Inactive Days';
const LIST_VIEW = 'Hoeh_Risk_Chancen';

function soql(q: string): any[] {
  const out = execSync(`sf data query --query "${q}" --target-org Test-Org --json`, {
    encoding: 'utf-8',
    timeout: 180000,
    env: { ...process.env, FORCE_COLOR: '0' },
  });
  const clean = out.replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  return JSON.parse(clean.slice(clean.indexOf('{'), clean.lastIndexOf('}') + 1)).result.records;
}

async function listRows(page: any) {
  await page.goto(
    `/lightning/o/Opportunity/list?filterName=${LIST_VIEW}`,
    { waitUntil: 'domcontentloaded', timeout: 60000 },
  );
  const rows = page.getByRole('row');
  let rowCount = 0;
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    rowCount = await rows.count();
    if (rowCount > 1) break;
    await page.waitForTimeout(3000);
  }
  return rows;
}

test.describe('[SCRUM-449] AC1 — the risk assessment is shown on the record', () => {
  test.setTimeout(180000);
  test('an at-risk open record shows level, reason and inactive days', async ({ page }) => {
    // A record the org itself flagged: the data is already there, so a red run
    // can only mean the record PAGE does not show it.
    const rec = soql(
      "SELECT Id, Name, Risk_Level__c, Risk_Reason__c, Inactive_Days__c " +
      "FROM Opportunity WHERE IsClosed = false AND Risk_Level__c = 'High' AND Inactive_Days__c > 14 LIMIT 1",
    )[0];
    expect(rec.Risk_Level__c).toBe('High');
    expect(Number(rec.Inactive_Days__c)).toBeGreaterThan(14);

    await openRecordDetails(page, `/lightning/r/Opportunity/${rec.Id}/view`);
    const snap = await page.locator('body').first().ariaSnapshot();

    // Absence IS the failure — no conditional skip.
    expect(snap).toContain(RISK_LEVEL_LABEL);
    expect(snap).toContain(RISK_REASON_LABEL);
    expect(snap).toContain(INACTIVE_DAYS_LABEL);
    // The VALUE and the REASON text must be rendered, not just the labels.
    expect(snap).toContain(rec.Risk_Reason__c.slice(0, 40));
    expect(snap).toMatch(new RegExp(`${INACTIVE_DAYS_LABEL}\\D+${rec.Inactive_Days__c}|${rec.Inactive_Days__c}\\D+${INACTIVE_DAYS_LABEL}`));
    expect(snap).toMatch(new RegExp(`${RISK_LEVEL_LABEL}\\D+High|High\\D+${RISK_LEVEL_LABEL}`));
  });
});

test.describe('[SCRUM-449] AC7/AC8 — closed or healthy records carry no risk level', () => {
  test.setTimeout(240000);
  test('no closed record appears in the High-risk list', async ({ page }) => {
    // Org-level: the closed records must hold no assessment at all.
    const closedWithRisk = soql(
      "SELECT Id, Name, StageName, Risk_Level__c FROM Opportunity WHERE IsClosed = true AND Risk_Level__c != null",
    );
    expect(closedWithRisk.length).toBe(0);
    const closedTotal = soql("SELECT Id, Name, StageName FROM Opportunity WHERE IsClosed = true");
    expect(closedTotal.length).toBeGreaterThan(0); // the criterion is exercised on real records

    // UI-level: the list view must not leak a closed record.
    const rows = await listRows(page);
    const rowCount = await rows.count();
    expect(rowCount).toBeGreaterThan(1);

    const closedNames = new Set(closedTotal.map((r) => r.Name));
    const leaked: string[] = [];
    for (let i = 1; i < rowCount; i++) {
      const snap = await rows.nth(i).ariaSnapshot();
      for (const name of closedNames) {
        if (snap.includes(name)) leaked.push(name);
      }
    }
    expect(leaked).toEqual([]);
  });
});

test.describe('[SCRUM-449] AC10/AC12 — usable as filter, organisation-wide', () => {
  test.setTimeout(240000);
  test('the deployed list view lists every High-risk open record', async ({ page }) => {
    const recs = soql(
      "SELECT Id, Name, Risk_Reason__c FROM Opportunity WHERE Risk_Level__c = 'High' AND IsClosed = false",
    );
    expect(recs.length).toBeGreaterThan(0);
    const expectedNames = new Set(recs.map((r) => r.Name));
    const reasonTexts = new Set(recs.map((r) => r.Risk_Reason__c.slice(0, 40)));

    const rows = await listRows(page);
    const rowCount = await rows.count();
    // Absence of the rows IS the failure.
    expect(rowCount).toBeGreaterThan(1);
    // The view must show the SAME records the org holds — not a user-scoped subset.
    expect(rowCount).toBe(recs.length + 1); // +1 header row

    const header = await rows.nth(0).ariaSnapshot();
    expect(header).toContain(RISK_LEVEL_LABEL);
    expect(header).toContain(INACTIVE_DAYS_LABEL);
    expect(header).toContain(RISK_REASON_LABEL);

    // Every listed record is one of the org's High-risk open records, and it
    // carries the level, the days and the reason text.
    for (let i = 1; i < rowCount; i++) {
      const snap = await rows.nth(i).ariaSnapshot();
      expect([...expectedNames].some((n) => snap.includes(n))).toBe(true);
      expect(snap).toContain('High');
      expect(snap).toContain('Inactive Days');
      expect([...reasonTexts].some((t) => snap.includes(t))).toBe(true);
    }
  });
});
