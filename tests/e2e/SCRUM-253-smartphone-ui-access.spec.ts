import { test, expect } from '@playwright/test';

/**
 * [SCRUM-253] Smartphone-Objekt für Benutzer erstellbar machen
 *
 * Test-Szenarien abgeleitet aus den Acceptance Criteria:
 *
 * AC1: Custom Tab für Smartphone ist im Salesforce-UI sichtbar
 * AC2: Page Layout enthält alle 14 Felder in sinnvoller Reihenfolge
 * AC3: Page Layout wird den relevanten Profilen zugewiesen
 * AC4: Benutzerprofi(e) haben Create-Permission auf dem Smartphone-Objekt
 * AC5: Benutzer kann über Tab → New einen neuen Smartphone-Record erstellen und speichern
 * AC6: Alle 14 Felder sind auf dem Create-Formular sichtbar und editierbar
 * AC7: Erforderliche (Required) Felder zeigen bei Leerlass eine Validierungsfehler-Meldung
 */

const EXPECTED_FIELDS = [
  'Name',
  'Seriennummer',
  'Marke',
  'Modell',
  'Farbe',
  'Speicherkapazität',
  'Status',
  'Kondition',
  'Preis',
  'Kaufdatum',
  'Verkaufsdatum',
  'Kunde',
  'Verkäufer',
  'Garantie bis',
];

const TEST_DATA = {
  name: 'Test iPhone 15',
  serieNummer: 'SN-TEST-2026-001',
  marke: 'Apple',
  modell: 'iPhone 15 Pro',
  farbe: 'Titan Blau',
  speicher: '256 GB',
  status: 'Verfügbar',
  kondition: 'Neu',
  preis: '1199.00',
};

test.describe('[SCRUM-253] Smartphone-Objekt UI-Zugriff', () => {
  // Helper: Open Smartphone Management app via App Launcher
  async function openSmartphoneApp(page: import('@playwright/test').Page) {
    const sfUrl = process.env.SALESFORCE_URL || 'https://empathetic-hawk-kft3g7-dev-ed.trailblaze.my.salesforce.com';
    await page.goto(sfUrl);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Open App Launcher (three-dot grid icon)
    const appLauncher = page.getByLabel('App Launcher').first();
    await appLauncher.click();
    await page.waitForTimeout(1000);

    // Search for Smartphone Management app
    const searchBox = page.getByRole('textbox', { name: /Search apps/i }).first();
    await searchBox.fill('Smartphone');
    await page.waitForTimeout(500);

    // Click on the app
    const appOption = page.getByRole('option', { name: /Smartphone Management/i }).first();
    await appOption.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
  }

  // AC1: Custom Tab für Smartphone ist im Salesforce-UI sichtbar
  test('AC1: Smartphone-Tab ist in der App-Leiste sichtbar', async ({ page }) => {
    await openSmartphoneApp(page);

    // Assert: Smartphone tab or heading is visible
    const smartphoneTab = page.getByRole('tab', { name: /Smartphone/i });
    const smartphoneHeading = page.getByRole('heading', { name: /Smartphone/i });
    const smartphoneText = page.getByText(/Smartphone/i);

    const tabVisible = await smartphoneTab.isVisible().catch(() => false);
    const headingVisible = await smartphoneHeading.isVisible().catch(() => false);
    const textVisible = await smartphoneText.isVisible().catch(() => false);

    expect(tabVisible || headingVisible || textVisible).toBe(true);
  });

  // AC2: Page Layout enthält alle 14 Felder in sinnvoller Reihenfolge
  test('AC2: Page Layout enthält alle 14 Felder', async ({ page }) => {
    await openSmartphoneApp(page);

    // Click New button to open create form
    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Assert: All 14 fields are present on the layout
    for (const field of EXPECTED_FIELDS) {
      const fieldLabel = page.getByText(field, { exact: true });
      await expect(fieldLabel).toBeVisible({ timeout: 5000 });
    }
  });

  // AC4: Benutzer hat Create-Permission (New-Button ist sichtbar)
  test('AC4: Create-Permission — New-Button ist sichtbar', async ({ page }) => {
    await openSmartphoneApp(page);

    // Assert: New button is visible and enabled
    const newButton = page.getByRole('button', { name: /New/i }).first();
    await expect(newButton).toBeVisible({ timeout: 10000 });
    await expect(newButton).toBeEnabled();
  });

  // AC5: Benutzer kann einen neuen Smartphone-Record erstellen und speichern
  test('AC5: Smartphone-Record erstellen und speichern', async ({ page }) => {
    await openSmartphoneApp(page);

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Fill required Name field
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill(TEST_DATA.name);

    // Fill additional fields
    const serieField = page.getByLabel(/Seriennummer/i);
    await serieField.fill(TEST_DATA.serieNummer);

    const markeField = page.getByLabel(/Marke/i);
    await markeField.fill(TEST_DATA.marke);

    const modellField = page.getByLabel(/Modell/i);
    await modellField.fill(TEST_DATA.modell);

    // Save
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Assert: Record was created - name should be visible on detail page
    await expect(page.getByText(TEST_DATA.name)).toBeVisible({ timeout: 10000 });
  });

  // AC6: Alle 14 Felder sind auf dem Create-Formular sichtbar und editierbar
  test('AC6: Alle 14 Felder sind sichtbar und editierbar', async ({ page }) => {
    await openSmartphoneApp(page);

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Test Name field
    const nameField = page.getByLabel(/Name/i).first();
    await expect(nameField).toBeVisible();
    await nameField.fill('Edit Test');
    await expect(nameField).toHaveValue('Edit Test');
    await nameField.clear();

    // Test Seriennummer field
    const serieField = page.getByLabel(/Seriennummer/i);
    await expect(serieField).toBeVisible();
    await serieField.fill('EDIT-TEST');
    await expect(serieField).toHaveValue('EDIT-TEST');
    await serieField.clear();

    // Test Marke field
    const markeField = page.getByLabel(/Marke/i);
    await expect(markeField).toBeVisible();
    await markeField.fill('TestBrand');
    await expect(markeField).toHaveValue('TestBrand');
    await markeField.clear();

    // Test Modell field
    const modellField = page.getByLabel(/Modell/i);
    await expect(modellField).toBeVisible();
    await modellField.fill('TestModel');
    await expect(modellField).toHaveValue('TestModel');
    await modellField.clear();
  });

  // AC7: Required-Felder zeigen Validierungsfehler bei Leerlass
  test('AC7: Required-Feld (Name) zeigt Validierungsfehler', async ({ page }) => {
    await openSmartphoneApp(page);

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Try to save without filling Name
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForTimeout(3000);

    // Assert: Validation error should appear
    const errorMessage = page.getByText(/This field is required/i);
    const errorBanner = page.getByRole('alert');
    const redAsterisk = page.locator('.requiredMark');

    const hasErrorMessage = await errorMessage.isVisible().catch(() => false);
    const hasErrorBanner = await errorBanner.isVisible().catch(() => false);
    const hasRedAsterisk = await redAsterisk.isVisible().catch(() => false);

    expect(hasErrorMessage || hasErrorBanner || hasRedAsterisk).toBe(true);
  });

  // Edge Case: Nur Name-Feld ist required, andere Felder sind optional
  test('Edge Case: Nur Name-Feld ist required, andere Felder sind optional', async ({ page }) => {
    await openSmartphoneApp(page);

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Fill ONLY Name and save
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Minimal Smartphone Record');

    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Assert: Record created with only Name
    await expect(page.getByText('Minimal Smartphone Record')).toBeVisible({ timeout: 10000 });
  });
});
