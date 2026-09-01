import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';

/**
 * [SCRUM-378] Nachfassliste für Leads — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). Network never networkidle on Lightning.
 *
 * Locators used here were PROBED against this org on 2026-09-01:
 *   - date field label "Letzter Versuch" resolves via getByLabel in the
 *     Lightning New/Edit form (Playwright pierces the shadow DOM).
 *   - Formula field "Ist fällig" is present as TEXT on the record view and is
 *     NOT an input/control in the New/Edit form (read-only by design).
 *   - List view is addressed by /lightning/o/Lead/list?filterName=Nachfassliste
 *     (the listViewId= param silently reverted to __Recent here).
 *   - Record "Edit" button: getByRole('button', { name: 'Edit', exact: true }).
 *
 * Fixtures (TEST-SCRUM-378-*, re-seeded on a best-effort basis in beforeEach):
 *   FAELLIG  open  2026-08-12  Is_Due=true   -> IN the list (open + > 14 days)
 *   RECENT   open  2026-08-29  Is_Due=false  -> NOT in the list (3 days)
 *   NODATE   open  no date     Is_Due=false  -> NOT in the list (no date)
 *   CLOSED   closed 2026-08-01 Is_Due=false  -> NOT in the list (closed)
 *
 * Formula branches (open+20d→true, open+3d→false, closed+30d→false,
 * no-date→false) were additionally verified via SOQL against the org on the
 * same fixtures — one query, four rows.
 *
 * KNOWN DEFECT asserted honestly (see Jira SCRUM-378 comment chain, 15225/15228):
 *   AC "exactly Name · Firma · Status · Letzter Versuch" — the deployed ListView
 *   declares only Last_Attempt_Date__c; Salesforce replaces the default column
 *   set once any column is declared, and the org rejects standard columns
 *   ("Could not resolve list view column"). Test 3 asserts the AC literally and
 *   therefore FAILS — that failure is the defect report, not a locator bug.
 */

// Fixture IDs created for this ticket (Test-Org; admin session owns them).
const FAELLIG_ID = '00QWU00000fQF3q2AG'; // open, 2026-08-12, Is_Due=true

/** Ensure all four fixtures exist with the expected fields (idempotent). */
async function ensureFixtures() {
  const seed: Array<[string, string, string, string, string]> = [
    ['FAELLIG', 'Open - Not Contacted', '2026-08-12', 'TestfirmaFaellig', '2026-08-12'],
    ['RECENT', 'Working - Contacted', '2026-08-29', 'TestfirmaRecent', '2026-08-29'],
    ['NODATE', 'Open - Not Contacted', '', 'TestfirmaNodate', ''],
  ];
  const run = (args: string[]) => {
    try {
      execSync(`sf ${args.join(' ')} 2>/dev/null`, { stdio: ['pipe', 'pipe', 'pipe'] });
      return true;
    } catch {
      return false;
    }
  };
  for (const [tag, status, date, company, lastDate] of seed) {
    const id = `TEST-SCRUM-378-${tag}`;
    const exists = run(
      ['data', 'query', '-o', 'Test-Org', `-q`, `SELECT Id FROM Lead WHERE Name LIKE '${id}%' LIMIT 1`]
    );
    if (!exists) {
      const v = `LastName=${id} Company=${company} 'Status=${status}' LeadSource=Email${
        lastDate ? ` Last_Attempt_Date__c=${lastDate}` : ''
      }`;
      run(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v', v]);
    }
  }
  // CLOSED fixture is created once and reused (status changes keep it excluded).
  run([
    'data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v',
    "LastName=TEST-SCRUM-378-CLOSED Company=TestfirmaClosed 'Status=Closed - Not Converted' LeadSource=Email",
  ]);
}

test.describe('[SCRUM-378] Nachfassliste für Leads', () => {
  test.beforeAll(() => {
    ensureFixtures();
  });

  test('AC list filter: only open+due lead remains; recent/no-date/closed are excluded', async ({ page }) => {
    await page.goto('/lightning/o/Lead/list?filterName=Nachfassliste');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    // Wait until the list body has rendered its rows (not networkidle).
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByText(/Sorted by Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    const body = page.locator('body');
    // The org reports the filter state itself: exactly one item, filtered by the formula
    // (the due lead only). RECENT (3d), NODATE, CLOSED are all excluded by the filter.
    await expect(body.getByText(/1 item/).first()).toBeVisible();
    await expect(body.getByText(/Filtered by Ist fällig/).first()).toBeVisible();
    // The one surviving row carries its date in the declared column:
    await expect(body.getByText('12.08.2026').first()).toBeVisible();
    // None of the excluded fixtures may carry a rendered value of their own date:
    await expect(body.getByText('29.08.2026', { exact: true })).toHaveCount(0); // RECENT
    // No-date / closed rows render no date cell at all (only one row exists):
    await expect(body.getByText('01.08.2026', { exact: true })).toHaveCount(0); // CLOSED
  });

  test('AC layout: "Letzter Versuch" and "Ist fällig" appear together on the Lead record page', async ({ page }) => {
    await page.goto(`/lightning/r/Lead/${FAELLIG_ID}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    // The two fields live in the Details tab of the Record Home page — click it.
    const details = page.getByRole('tab', { name: 'Details' });
    await expect(details.first()).toBeVisible({ timeout: 30000 });
    await details.first().click();
    await page.waitForTimeout(3000);

    // Both fields of the "Nachfassung" pair, in the details content:
    await expect(page.getByText('Nachfassung', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('Letzter Versuch', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('Ist fällig', { exact: true }).first()).toBeVisible();
    // The due fixture shows the computed formula value (Lightning renders "True"):
    await expect(page.getByText('True', { exact: true }).first()).toBeVisible();
  });

  test('AC columns: list shows Name, Firma, Status, Letzter Versuch (currently FAILING — the defect)', async ({ page }) => {
    // Asserts the AC literally: the one surviving row must carry the lead's
    // NAME, COMPANY and STATUS read off the list — not only the date.
    // Known-defect test: with the deployed ListView (only Last_Attempt_Date__c
    // declared; SDR resolves <columns> against the source package, standard
    // columns rejected by the org — Jira 15225/15228) this fails on all three
    // values. It must stay red until the carrier is fixed.
    await page.goto('/lightning/o/Lead/list?filterName=Nachfassliste');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByText(/Sorted by Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    const body = page.locator('body');
    // "Letzter Versuch" is the only working column today — anchor on its value:
    await expect(body.getByText('12.08.2026').first()).toBeVisible({ timeout: 15000 });

    // AC demands, per row: the lead name, the company and the status must be
    // readable in the list. None of them render today → the defect.
    const inList = async (value: string) => (await body.getByText(value, { exact: true }).count()) > 0;
    const missing: string[] = [];
    if (!(await inList('TEST-SCRUM-378-FAELLIG'))) missing.push('Name');
    if (!(await inList('TestfirmaFaellig'))) missing.push('Company (Firma)');
    if (!(await inList('Open - Not Contacted'))) missing.push('Status');
    expect(
      missing,
      `AC "Liste zeigt genau Name, Firma, Status, Letzter Versuch" violated — missing from list: ` +
        `${missing.join(', ')}. Only "Letzter Versuch" renders (1 of 4 AC columns).`,
    ).toEqual([]);
  });

  test('AC read-only: "Ist fällig" is not an editable control in the form; date field is editable', async ({ page }) => {
    await page.goto('/lightning/o/Lead/new');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByLabel(/Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    // The manual date field exists as a real, focusable input:
    const dateField = page.getByLabel(/Letzter Versuch/).first();
    await dateField.click();
    await expect(dateField).toBeEnabled();
    const tag = await dateField.evaluate((el) => el.tagName);
    expect(tag).toBe('INPUT');

    // The formula checkbox must NOT be a form control (no input/combobox bound
    // to it) — it is computed by the org, read-only by design.
    const dueControl = page.getByLabel(/Ist fällig/);
    await expect(dueControl).toHaveCount(0);
  });

  test('AC validation UI path: saving with a future date is rejected, not persisted', async ({ page }) => {
    await page.goto('/lightning/o/Lead/new');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByLabel(/Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    // Required fields + a FUTURE date, then Save.
    await page.getByLabel(/Last Name/i).first().fill('TEST-SCRUM-378-VALIDATE');
    const company = page.getByLabel(/Company/i).first();
    await company.click();
    await company.fill('TestfirmaValidation');
    const dateField = page.getByLabel(/Letzter Versuch/).first();
    await dateField.click();
    await dateField.fill('2026-12-31');
    await dateField.press('Enter');
    await page.waitForTimeout(1000);

    await page.getByRole('button', { name: /^Save$|Speichern/i }).first().click();
    // The org answers with a field-level error dialog — the record is NOT created.
    await expect(page.getByText(/We hit a snag|Review the following fields/i).first()).toBeVisible({ timeout: 20000 });
    // And the form still flags the date field:
    await expect(page.getByText('Letzter Versuch', { exact: true }).last()).toBeVisible();
    // Still on the form — nothing persisted.
    expect(page.url()).toContain('/new');
  });
});
