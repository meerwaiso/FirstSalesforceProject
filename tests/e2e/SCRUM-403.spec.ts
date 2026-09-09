import { test, expect } from '@playwright/test';

/**
 * [SCRUM-403] Letztes Anliegen + Dauer am Contact — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). Network never networkidle on Lightning.
 *
 * This is the PR-gate slice the Spec names for AC 8 (Classic/standard Record
 * View). In this org the Classic `one.app!` URL 302-redirects to the Lightning
 * shell (same as SCRUM-378: its record-page probe used the Lightning record
 * page via the Details tab), so the Record View is asserted on the Lightning
 * Record page — driven by `Contact-Contact Layout` (Phase 2), which is already
 * deployed, so nothing here waits on the DevOps FlexiPage step. The FlexiPage /
 * full Lightning layout placement stays with the tester (Spec §8).
 *
 * Locators used here were PROBED against this org on 2026-09-09:
 *   - Record view: /lightning/r/Contact/<Id>/view, fields live in the
 *     "Details" tab (getByRole('tab', { name: 'Details' })); the two field
 *     labels render as TEXT (read-only by design, never inputs).
 *   - List view: /lightning/o/Contact/list?filterName=Letztes_Anliegen.
 *     The org reports its own state: "Sorted by Letztes Anliegen" + "N items";
 *     dates render dd.mm.yyyy (e.g. 04.07.2026). The ListView carries
 *     `Last_Case_Date__c` as a column, which carries sort + date filter in the
 *     UI (PO: "keine Anliegen seit N Monaten herausfiltern").
 *
 * Fixtures (real org contacts that already carry a Case — stable, no DML;
 * Case.CreatedDate is not writeable so we cannot backdate our own):
 *   003WU00001kYIVsYAO  "ProbeCount"   Last_Case_Date__c=2026-08-28 -> "vor 12 Tagen"
 *   003WU00001l5jCEYAY  "SCR370 E2E"   Last_Case_Date__c=2026-09-07 -> "vor 2 Tagen"
 *
 * (Temporal-advance ACs — "vor N≥1" formula branches — were additionally
 * verified via SOQL against the org on 2026-09-09, because Case.CreatedDate
 * cannot be backdated in a test transaction: 520/532 contacts populated,
 * dates == MAX(CreatedDate) per contact, 12 NULL contacts == 0 cases.)
 */

// Real contacts with a case, read back from the org on 2026-09-09.
const CONTACT_PROBE = '003WU00001kYIVsYAO'; // Last_Case_Date__c=2026-08-28, formula "vor 12 Tagen"
const DATE_PROBE = '28.08.2026';
const FORMULA_PROBE = /vor 12 Tage/;

test.describe('[SCRUM-403] Letztes Anliegen + Dauer am Contact (Test-Org)', () => {
  // The two fields live in the "Details" tab of the Record Home page — open it
  // and wait for the org-specific field label to appear (robust vs. tab timing).
  async function openDetails(page: any): Promise<void> {
    // Lightning default tab is "Related"; switch to Details. Retry a few times —
    // the tab shell loads before the record content on this org.
    for (let attempt = 0; attempt < 5; attempt++) {
      const details = page.getByRole('tab', { name: 'Details' });
      if (await details.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        await details.first().click();
      }
      // Success = the org-specific field label has rendered.
      if (
        await page
          .getByText('Letztes Anliegen', { exact: true })
          .first()
          .isVisible({ timeout: 4000 })
          .catch(() => false)
      ) {
        return;
      }
      await page.waitForTimeout(1500);
    }
    // Let the final wait below surface the absence clearly.
  }

  test('AC8 record view: "Letztes Anliegen" + "Wie lange her" appear together on the Contact page', async ({ page }) => {
    await page.goto(`/lightning/r/Contact/${CONTACT_PROBE}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await openDetails(page);

    // Both fields of the "Letztes Anliegen" pair are present in the Details content.
    await expect(page.getByText('Letztes Anliegen', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('Wie lange her', { exact: true }).first()).toBeVisible({ timeout: 15000 });

    // The fixture has a real backdated case: the date cell + the formula text
    // render next to their labels (read-only values, never inputs).
    await expect(page.getByText(DATE_PROBE, { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.locator('body').getByText(FORMULA_PROBE).first()).toBeVisible({ timeout: 15000 });
  });

  test('AC8 list view: Last_Case_Date__c column is present and the list is sorted by it (filter/sort carrier)', async ({ page }) => {
    // Address the custom list view by name (the listViewId= param silently
    // reverts to __Recent on this org — see SCRUM-378 note).
    await page.goto('/lightning/o/Contact/list?filterName=Letztes_Anliegen');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    // The list-view body renders the custom column header (the org's own label).
    const body = page.locator('body');
    await expect(body.getByText('Letztes Anliegen').first()).toBeVisible({ timeout: 30000 });

    // The org reports the sort order itself: sorted by our field. That the list
    // is sorted by Last_Case_Date__c is what the PO's "nach Datum sortieren
    // + herausfiltern" requirement is about (silence-on-top via asc sort / a
    // date filter the column carries).
    await expect(body.getByText(/Sorted by Letztes Anliegen/).first()).toBeVisible({ timeout: 30000 });

    // Rows render with a value in the declared date column (dd.mm.yyyy) and the
    // org reports a non-empty result set — i.e. the backfill is visible in the UI.
    await expect(body.getByText(/\d{2}\.\d{2}\.\d{4}/).first()).toBeVisible({ timeout: 30000 });
    await expect(body.getByText(/items/).first()).toBeVisible({ timeout: 30000 });
  });
});
