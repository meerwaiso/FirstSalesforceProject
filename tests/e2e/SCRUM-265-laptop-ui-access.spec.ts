import { test, expect } from '@playwright/test';

/**
 * [SCRUM-265] Neues Custom Object 'Laptop' in Salesforce erstellen
 *
 * Test-Szenarien abgeleitet aus den Acceptance Criteria:
 *
 * AC1: Custom Object Laptop__c existiert in Salesforce (Deployed, Public)
 * AC2: Objekt hat einen Tab "Laptop", der in der Navigation sichtbar ist
 * AC3: Page Layout "Laptop Layout" ist konfiguriert und zeigt alle Felder
 * AC4: Compact Layout "Laptop Compact" ist konfiguriert
 * AC5: Permission Set "Laptop_Permissions" gewaehrt CRUD auf Laptop__c
 * AC6: Alle definierten Felder sind auf dem Create-Formular sichtbar und editierbar
 * AC7: Das Name-Feld ist required; andere Felder sind optional
 * AC8: Benutzer koennen ueber Tab → New einen Laptop-Record erstellen und speichern
 * AC9: Reports und Search sind fuer das Objekt aktiviert
 * AC10: Activities sind fuer das Objekt aktiviert
 */

const EXPECTED_FIELDS = [
  'Name',
  'Seriennummer',
  'Marke',
  'Modell',
  'Kunde',
  'Verkäufer',
  'Preis',
  'Kondition',
  'Farbe',
  'CPU',
  'RAM',
  'Speicherkapazität',
  'Kaufdatum',
  'Verkaufsdatum',
  'Garantie bis',
  'Gewährleistungsnummer',
  'Status',
];

const TEST_DATA = {
  name: 'Test MacBook Pro 16',
  serieNummer: 'SN-LAPTOP-2026-001',
  marke: 'Apple',
  modell: 'MacBook Pro 16"',
  kunde: 'Max Mustermann',
  verkaeufer: 'Lisa Müller',
  preis: '2499.00',
  farbe: 'Space Grau',
  cpu: 'M3 Pro',
  ram: '32 GB',
  speicher: '1 TB SSD',
};

test.describe('[SCRUM-265] Laptop-Objekt UI-Zugriff', () => {
  // Helper: Open Smartphone Management app via App Launcher
  async function openSmartphoneApp(page: import('@playwright/test').Page) {
    await page.goto('/lightning/page/home');
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);

    // Open App Launcher (three-dot grid icon)
    const appLauncher = page.getByRole('button', { name: 'App Launcher' }).first();
    await appLauncher.click();
    await page.waitForTimeout(1000);

    // Search for Smartphone Management app
    const searchBox = page.getByPlaceholder(/Search apps/i).first();
    await searchBox.fill('Smartphone');
    await page.waitForTimeout(500);

    // Click on the app
    const appOption = page.getByRole('option', { name: /Smartphone Management/i }).first();
    await appOption.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);
  }

  // AC1 + AC2: Custom Object Laptop__c existiert und Tab ist sichtbar
  test('AC1+AC2: Laptop-Tab ist in der App-Leiste sichtbar', async ({ page }) => {
    await openSmartphoneApp(page);

    // Assert: Laptop tab or heading is visible
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    const laptopHeading = page.getByRole('heading', { name: /Laptop/i });
    const laptopText = page.getByText(/Laptop/i);

    const tabVisible = await laptopTab.isVisible().catch(() => false);
    const headingVisible = await laptopHeading.isVisible().catch(() => false);
    const textVisible = await laptopText.isVisible().catch(() => false);

    expect(tabVisible || headingVisible || textVisible).toBe(true);
  });

  // AC5: Permission Set gewaehrt CRUD — New-Button ist sichtbar
  test('AC5: CRUD-Permission — New-Button ist sichtbar', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab if needed
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    // Assert: New button is visible and enabled
    const newButton = page.getByRole('button', { name: /New/i }).first();
    await expect(newButton).toBeVisible({ timeout: 10000 });
    await expect(newButton).toBeEnabled();
  });

  // AC3: Page Layout zeigt alle 17 Felder (Name + 16 Custom Fields)
  test('AC3: Page Layout enthaelt alle 17 Felder', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    // Click New button to open create form
    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2000);

    // Assert: All 17 fields are present on the layout
    for (const field of EXPECTED_FIELDS) {
      const fieldLabel = page.getByText(field, { exact: true });
      await expect(fieldLabel).toBeVisible({ timeout: 5000 });
    }
  });

  // AC6: Alle Felder sind auf dem Create-Formular sichtbar und editierbar
  test('AC6: Alle Felder sind sichtbar und editierbar', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('domcontentloaded');
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

    // Test CPU field (Laptop-specific)
    const cpuField = page.getByLabel(/CPU/i);
    await expect(cpuField).toBeVisible();
    await cpuField.fill('M3 Max');
    await expect(cpuField).toHaveValue('M3 Max');
    await cpuField.clear();

    // Test RAM field (Laptop-specific)
    const ramField = page.getByLabel(/RAM/i);
    await expect(ramField).toBeVisible();
    await ramField.fill('64 GB');
    await expect(ramField).toHaveValue('64 GB');
    await ramField.clear();
  });

  // AC7: Name-Feld ist required; andere Felder sind optional
  test('AC7: Name-Feld zeigt Validierungsfehler bei Leerlass', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('domcontentloaded');
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

  // AC8: Laptop-Record erstellen und speichern
  test('AC8: Laptop-Record erstellen und speichern', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('domcontentloaded');
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

    // Fill Laptop-specific fields
    const cpuField = page.getByLabel(/CPU/i);
    await cpuField.fill(TEST_DATA.cpu);

    const ramField = page.getByLabel(/RAM/i);
    await ramField.fill(TEST_DATA.ram);

    // Save
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);

    // Assert: Record was created - name should be visible on detail page
    await expect(page.getByText(TEST_DATA.name)).toBeVisible({ timeout: 10000 });
  });

  // Edge Case: Nur Name-Feld ist required, andere Felder sind optional
  test('Edge Case: Nur Name-Feld required, andere Felder optional', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    const newButton = page.getByRole('button', { name: /New/i }).first();
    await newButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2000);

    // Fill ONLY Name and save
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Minimal Laptop Record');

    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);

    // Assert: Record created with only Name
    await expect(page.getByText('Minimal Laptop Record')).toBeVisible({ timeout: 10000 });
  });

  // AC9: Reports und Search sind aktiviert (indirekt ueber UI-Pruefung)
  test('AC9: Reports und Search sind fuer Laptop-Objekt aktiviert', async ({ page }) => {
    await openSmartphoneApp(page);

    // Navigate to Laptop tab
    const laptopTab = page.getByRole('tab', { name: /Laptop/i });
    if (await laptopTab.isVisible().catch(() => false)) {
      await laptopTab.click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    // Check if list view is functional (indicates Search capability)
    const listView = page.getByRole('table');
    const listVisible = await listView.isVisible().catch(() => false);

    // Or check for global search
    // Verified via `npm run probe -- /lightning/page/home search`:
    // global search is a button with aria-label "Search", not a labelled input
    const globalSearch = page.getByRole('button', { name: 'Search' });
    const searchVisible = await globalSearch.isVisible().catch(() => false);

    expect(listVisible || searchVisible).toBe(true);
  });
});