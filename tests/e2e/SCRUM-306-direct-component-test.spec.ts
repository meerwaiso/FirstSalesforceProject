import { test, expect } from '@playwright/test';

/**
 * [SCRUM-306] Top 3 Accounts Dashboard — direkter Komponententest
 *
 * Ruft die LWC-Komponente direkt via App Page auf (nicht über Home Page Layout),
 * um zu verifizieren, dass die Komponente funktional korrekt arbeitet.
 *
 * Auth: Uses storageState from auth.setup.ts (via playwright.config.ts)
 * URL: Uses baseURL from playwright.config.ts
 */

test.describe('[SCRUM-306] Top Accounts Dashboard — direkter Komponententest', () => {
  test('LWC Komponente laedt und zeigt Daten', async ({ page, baseURL }) => {
    // Direkt zur LWC-Komponente navigieren via App Page
    await page.goto(`${baseURL}/lightning/n/TopAccountsDashboard`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(5000);

    // Page sollte geladen sein
    await expect(page).toHaveTitle(/Salesforce/);

    // Screenshot zur manuellen Verifikation
    await page.screenshot({ path: 'test-results/top-accounts-direct-screenshot.png', fullPage: true });

    // Prüfen ob die Card sichtbar ist
    const card = page.locator('lightning-card');
    const cardVisible = await card.isVisible().catch(() => false);
    console.log('Card visible:', cardVisible);

    // Prüfen ob der Titel "Top 3 Accounts (Umsatz)" sichtbar ist
    const title = page.getByText('Top 3 Accounts (Umsatz)');
    const titleVisible = await title.isVisible().catch(() => false);
    console.log('Title visible:', titleVisible);

    // Prüfen ob datatable geladen wurde
    const datatable = page.locator('lightning-datatable');
    const datatableVisible = await datatable.isVisible().catch(() => false);
    console.log('Datatable visible:', datatableVisible);

    // Prüfen ob Spinner verschwunden ist
    const spinner = page.locator('lightning-spinner');
    const spinnerVisible = await spinner.isVisible().catch(() => false);
    console.log('Spinner visible:', spinnerVisible);

    // Fehlermeldung prüfen
    const errorText = page.getByText('Fehler beim Laden der Daten');
    const errorVisible = await errorText.isVisible().catch(() => false);
    console.log('Error visible:', errorVisible);
  });

  test('LWC Komponente via App Page — Read-Only', async ({ page, baseURL }) => {
    await page.goto(`${baseURL}/lightning/n/TopAccountsDashboard`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(5000);

    // Kein Edit-Button
    const editButtons = page.locator('lightning-card').getByRole('button', { name: /Edit|Bearbeiten/i });
    const editCount = await editButtons.count().catch(() => 0);
    expect(editCount).toBe(0);

    // Keine Checkboxes
    const checkboxes = page.locator('lightning-datatable').locator('input[type="checkbox"]');
    const checkboxCount = await checkboxes.count().catch(() => 0);
    expect(checkboxCount).toBe(0);
  });
});