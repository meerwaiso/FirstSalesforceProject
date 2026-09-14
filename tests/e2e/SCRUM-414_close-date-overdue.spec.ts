import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-414] "Abschlusstermin überfällig" — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). Lightning: domcontentloaded + explicit waits,
 * NEVER networkidle (continuous polling would only time out).
 *
 * Scope (UI-side ACs only):
 *   TC11  List view "Überfällige Chancen" (Ueberfaellige_Chancen):
 *         filter + sort "schlimmste zuerst" (asc/desc on the days column) +
 *         Bestand (existing overdue records are visible immediately).
 *   TC11  Record page: both read-only formula fields render in the Lightning
 *         layout section "Überschrittene Abschlüsse" and are NOT editable.
 *   TC12-14  Rename regression (SCRUM-319 Is_Overdue__c -> Is_Inactive__c):
 *         the renamed field renders under its NEW label "Inaktiv" and stays
 *         editable; the new SCRUM-414 fields coexist.
 *
 * Value logic (formula branches, closed->NULL, strict-today, Bestand-TAG,
 * bulk) is covered by the Apex class SCRUM414CloseDateOverdueTest (7/7).
 * NEGATIVE FLS (TC8) is the mandatory real-org test via Apex System.runAs
 * with a temp Standard User (route a, the DE-org default — no second
 * licensed licence is available for a route-b UI session). This spec covers
 * the POSITIVE UI side; TC8's Apex test is the authoritative negative.
 *
 * Reference data is resolved from the org at run time (never hardcoded IDs /
 * never a hardcoded day count — CloseDate-based values roll daily).
 */

function sfJson(command: string): any {
  const raw = execSync(command, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
}

/** The list view we test (label "Überfällige Chancen"). */
const LIST_VIEW = '/lightning/o/Opportunity/list?filterName=Ueberfaellige_Chancen';

/** SOQL: an open Opportunity whose close date has passed (worst first). */
const OVERDUE_SOQL =
  `SELECT Id, Name, Days_Close_Date_Overdue__c FROM Opportunity ` +
  `WHERE Is_Close_Date_Overdue__c = true AND StageName NOT IN ('Closed Won','Closed Lost') ` +
  `ORDER BY Days_Close_Date_Overdue__c DESC LIMIT 1`;

/** SOQL: count of open+overdue opportunities (the list view must show exactly these). */
const OVERDUE_COUNT_SOQL =
  `SELECT Id FROM Opportunity WHERE Is_Close_Date_Overdue__c = true ` +
  `AND StageName NOT IN ('Closed Won','Closed Lost')`;

/** One live overdue opportunity (open), resolved per run. */
function overdueRecord() {
  const r = sfJson(`sf data query --json -q "${OVERDUE_SOQL}"`).result;
  if (!r.records.length) throw new Error('no open overdue Opportunity found in Test-Org');
  return r.records[0];
}

/** Count of open+overdue opportunities the list view must show. */
function overdueCount() {
  const r = sfJson(`sf data query --json -q "${OVERDUE_COUNT_SOQL}"`).result;
  return r.totalSize;
}

test.describe('[SCRUM-414] Absatz-termin-überfällig (Test-Org, Lightning)', () => {
  test('TC11 list: filter + sort "schlimmste zuerst", existing records visible (Bestand)', async ({ page }) => {
    const expected = overdueCount();

    await page.goto(LIST_VIEW, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page
      .locator('div.slds-global-header, one-appnav')
      .first()
      .waitFor({ state: 'visible', timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    // The org itself reports the active filter + item count in the list header.
    const header = page.getByText(/^\d+ items/).first();
    await expect(header).toBeVisible({ timeout: 30000 });
    const headerText = (await header.innerText()).trim();
    expect(headerText, 'list header must report the overdue count').toMatch(
      new RegExp(`^${expected}\\s+items`),
    );
    // The list carries both filters (not closed + overdue == true).
    expect(headerText).toContain('Filtered by Stage');
    expect(headerText).toContain('Überfällig (Abschluss)');

    // ---- Sort "schlimmste zuerst": drive the days column to DESCENDING ----
    const dayTh = page.locator('th[aria-label="Tage überfällig (Abschluss)"]').first();
    await expect(dayTh).toBeVisible({ timeout: 15000 });
    const sortLink = dayTh.locator('a[role="button"], [role="button"]').first();
    const direction = async () => {
      const cls = (await dayTh.getAttribute('class')) || '';
      if (/slds-is-sorted_desc/.test(cls)) return 'desc';
      if (/slds-is-sorted\b/.test(cls)) return 'asc';
      return 'none';
    };
    // Click until the days column sorts descending (worst / most days first).
    let d = await direction();
    if (d === 'none') {
      await sortLink.click({ force: true });
      await page.waitForTimeout(2500);
      d = await direction();
    }
    if (d === 'asc') {
      await sortLink.click({ force: true });
      await page.waitForTimeout(2500);
      d = await direction();
    }
    expect(d, 'days column must sort descending (schlimmste zuerst)').toBe('desc');

    // The org's own header text names the active sort column.
    await expect(page.getByText('Sorted by Tage überfällig (Abschluss)').first()).toBeVisible({
      timeout: 15000,
    });

    // ---- Bestand: every listed row is genuinely overdue, value present ----
    const rows = page.locator('table[role="grid"] tbody tr[role="row"], table[role="grid"] tbody tr');
    const rowCount = await rows.count();
    expect(rowCount, 'one row per open+overdue opportunity').toBe(expected);
    const first = rows.first().locator('td');
    // Row shows the overdue checkbox value and a positive day count (≥ 1 day).
    const firstCells = (await first.allInnerTexts()).map((s) => s.replace(/\n/g, ' ').trim());
    expect(firstCells.join(' ')).toContain('True');
    expect(firstCells.some((c) => /^\d+$/.test(c) && Number(c) >= 1)).toBe(true);
  });

  test('TC11 record: both formula fields render, read-only, no manual control', async ({ page }) => {
    const rec = overdueRecord();

    await page.goto(`/lightning/r/Opportunity/${rec.Id}/view`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    await page
      .locator('div.slds-global-header, one-appnav')
      .first()
      .waitFor({ state: 'visible', timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    // Details tab holds the new section.
    const details = page.getByRole('tab', { name: 'Details' });
    await expect(details.first()).toBeVisible({ timeout: 30000 });
    await details.first().click();
    await page.waitForTimeout(3000);

    // Section "Überschrittene Abschlüsse" + both field labels present.
    await expect(page.getByText('Überschrittene Abschlüsse', { exact: true }).first()).toBeVisible({
      timeout: 20000,
    });
    await expect(page.getByText('Überfällig (Abschluss)', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('Tage überfällig (Abschluss)', { exact: true }).first()).toBeVisible();

    // The checkbox renders the computed value; the days value equals the formula
    // result read back from the org (robust vs. a hardcoded number).
    await expect(page.getByText('True', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    const days = String(rec.Days_Close_Date_Overdue__c);
    await expect(page.getByText(days, { exact: true }).first()).toBeVisible({ timeout: 15000 });

    // Read-only: neither field is an editable control, and neither has an
    // "Edit" affordance (computed by the org — nothing manual).
    const overName = /Überfällig \(Abschluss\)/;
    const daysName = /Tage überfällig \(Abschluss\)/;
    await expect(page.getByRole('checkbox', { name: overName })).toHaveCount(0);
    await expect(page.getByRole('textbox', { name: overName })).toHaveCount(0);
    await expect(page.getByRole('radio', { name: overName })).toHaveCount(0);
    await expect(page.getByRole('checkbox', { name: daysName })).toHaveCount(0);
    await expect(page.getByRole('textbox', { name: daysName })).toHaveCount(0);
    await expect(page.getByRole('radio', { name: daysName })).toHaveCount(0);
    await expect(page.getByText(/Edit\s+Überfällig/i)).toHaveCount(0);
    await expect(page.getByText(/Edit\s+Tage überfällig/i)).toHaveCount(0);
  });

  test('TC12-14 rename: Is_Inactive__c ("Inaktiv") renders + editable, coexists with new fields', async ({ page }) => {
    const rec = overdueRecord();

    await page.goto(`/lightning/r/Opportunity/${rec.Id}/view`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    await page
      .locator('div.slds-global-header, one-appnav')
      .first()
      .waitFor({ state: 'visible', timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    const details = page.getByRole('tab', { name: 'Details' });
    await expect(details.first()).toBeVisible({ timeout: 30000 });
    await details.first().click();
    await page.waitForTimeout(3000);

    // The renamed SCRUM-319 field now renders under its NEW label "Inaktiv"
    // (no longer "Is_Overdue" / the old German "Überfällig"), and it stays the
    // user-editable checkbox it always was — an "Edit Inaktiv" affordance.
    await expect(page.getByText('Inaktiv', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText(/Edit\s+Inaktiv/i).first()).toBeVisible({ timeout: 15000 });

    // The new SCRUM-414 section coexists on the same record page.
    await expect(page.getByText('Überschrittene Abschlüsse', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('Tage überfällig (Abschluss)', { exact: true }).first()).toBeVisible();
  });
});
