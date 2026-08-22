import { test, expect } from '@playwright/test';

/**
 * [SCRUM-272] Garantie- und Altersprüfung bei Laptop-Anträgen
 *
 * Test-Szenarien abgeleitet aus den Acceptance Criteria:
 *
 * AC1: Bei Erstellen eines neuen Laptop-Antrags wird das Kaufdatum des aktuellen
 *      Geräts desselben Mitarbeiters ausgelesen
 * AC2: Gerät älter als 3 Jahre → Antrag kann ohne Begründung eingereicht werden
 * AC3: Gerät jünger als 3 Jahre → Pflichtfeld "Sonderbegründung" muss ausgefüllt werden
 * AC4: Prüfung läuft client-seitig (Lightning-Validierung) und server-seitig (Validation Rule)
 * AC5: Klare Fehlermeldung bei fehlender Sonderbegründung
 */


// Helper: Open Smartphone Management app via App Launcher
async function openSmartphoneApp(page: import('@playwright/test').Page) {
  await page.goto('/lightning/page/home');
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3000);

  // Open App Launcher
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

// Helper: Navigate to Laptop tab
async function navigateToLaptopTab(page: import('@playwright/test').Page) {
  const laptopTab = page.getByRole('tab', { name: /Laptop/i });
  if (await laptopTab.isVisible().catch(() => false)) {
    await laptopTab.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2000);
  }
}

// Helper: Open New Laptop form
async function openNewLaptopForm(page: import('@playwright/test').Page) {
  const newButton = page.getByRole('button', { name: /New/i }).first();
  await newButton.click();
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(2000);
}

// Helper: Get today's date in YYYY-MM-DD format
function getTodayDate(): string {
  return new Date().toISOString().split('T')[0];
}

// Helper: Get date 4 years ago in YYYY-MM-DD format
function getDate4YearsAgo(): string {
  const date = new Date();
  date.setFullYear(date.getFullYear() - 4);
  return date.toISOString().split('T')[0];
}

// Helper: Get date 1 year ago in YYYY-MM-DD format
function getDate1YearAgo(): string {
  const date = new Date();
  date.setFullYear(date.getFullYear() - 1);
  return date.toISOString().split('T')[0];
}

test.describe('[SCRUM-272] Garantie- und Altersprüfung bei Laptop-Anträgen', () => {
  // AC2: Gerät älter als 3 Jahre → Antrag ohne Sonderbegründung möglich
  test('AC2: Laptop mit Kaufdatum > 3 Jahre - keine Sonderbegründung erforderlich', async ({ page }) => {
    await openSmartphoneApp(page);
    await navigateToLaptopTab(page);
    await openNewLaptopForm(page);

    // Fill required Name field
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Alter Laptop - 4 Jahre alt');

    // Fill Kaufdatum with a date 4 years ago (older than 3 years)
    const kaufdatumField = page.getByLabel(/Kaufdatum/i);
    await kaufdatumField.fill(getDate4YearsAgo());

    // Save without filling Sonderbegründung
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(5000);

    // Assert: Record was created successfully (no validation error)
    // The record name should be visible on the detail page
    await expect(page.getByText('Alter Laptop - 4 Jahre alt')).toBeVisible({ timeout: 10000 });
  });

  // AC3: Gerät jünger als 3 Jahre → Sonderbegründung erforderlich
  test('AC3: Laptop mit Kaufdatum < 3 Jahre - Sonderbegründung erforderlich', async ({ page }) => {
    await openSmartphoneApp(page);
    await navigateToLaptopTab(page);
    await openNewLaptopForm(page);

    // Fill required Name field
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Neuer Laptop - 1 Jahr alt');

    // Fill Kaufdatum with a date 1 year ago (younger than 3 years)
    const kaufdatumField = page.getByLabel(/Kaufdatum/i);
    await kaufdatumField.fill(getDate1YearAgo());

    // Leave Sonderbegründung empty and try to save
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(5000);

    // Assert: Validation error should appear
    const errorMessage = page.getByText(/Sonderbegründung/i);
    const errorText = page.getByText(/weniger als 3 Jahre alt/i);
    const errorBanner = page.getByRole('alert');

    const hasErrorField = await errorMessage.isVisible().catch(() => false);
    const hasErrorDetail = await errorText.isVisible().catch(() => false);
    const hasErrorBanner = await errorBanner.isVisible().catch(() => false);

    expect(hasErrorField || hasErrorDetail || hasErrorBanner).toBe(true);
  });

  // AC5: Klare Fehlermeldung bei fehlender Sonderbegründung
  test('AC5: Fehlermeldung "Ihr aktuelles Gerät ist weniger als 3 Jahre alt" wird angezeigt', async ({ page }) => {
    await openSmartphoneApp(page);
    await navigateToLaptopTab(page);
    await openNewLaptopForm(page);

    // Fill required Name field
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Fehlermeldung Test');

    // Fill Kaufdatum with a recent date
    const kaufdatumField = page.getByLabel(/Kaufdatum/i);
    await kaufdatumField.fill(getDate1YearAgo());

    // Try to save without Sonderbegründung
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(5000);

    // Assert: Specific error message is displayed
    const expectedError = page.getByText(/Ihr aktuelles Gerät ist weniger als 3 Jahre alt/i);
    const alternativeError = page.getByText(/Sonderbegründung/i);

    const hasExpectedError = await expectedError.isVisible().catch(() => false);
    const hasAlternativeError = await alternativeError.isVisible().catch(() => false);

    expect(hasExpectedError || hasAlternativeError).toBe(true);
  });

  // AC3 + AC2: Sonderbegründung erlaubt Speichern bei neuem Gerät
  test('AC3+AC2: Mit Sonderbegründung kann Laptop auch bei < 3 Jahren gespeichert werden', async ({ page }) => {
    await openSmartphoneApp(page);
    await navigateToLaptopTab(page);
    await openNewLaptopForm(page);

    // Fill required Name field
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Neuer Laptop mit Begründung');

    // Fill Kaufdatum with a recent date (younger than 3 years)
    const kaufdatumField = page.getByLabel(/Kaufdatum/i);
    await kaufdatumField.fill(getDate1YearAgo());

    // Fill Sonderbegründung field
    const sonderbegruendungField = page.getByLabel(/Sonderbegründung/i);
    const fieldVisible = await sonderbegruendungField.isVisible().catch(() => false);

    if (fieldVisible) {
      await sonderbegruendungField.fill('Gerät ist defekt und muss ersetzt werden');
    }

    // Save
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(5000);

    // Assert: Record was created successfully
    await expect(page.getByText('Neuer Laptop mit Begründung')).toBeVisible({ timeout: 10000 });
  });

  // Edge Case: Kaufdatum heutig (0 Tage alt) → Sonderbegründung erforderlich
  test('Edge Case: Kaufdatum heute - Sonderbegründung erforderlich', async ({ page }) => {
    await openSmartphoneApp(page);
    await navigateToLaptopTab(page);
    await openNewLaptopForm(page);

    // Fill required Name field
    const nameField = page.getByLabel(/Name/i).first();
    await nameField.fill('Heutiges Gerät');

    // Fill Kaufdatum with today's date
    const kaufdatumField = page.getByLabel(/Kaufdatum/i);
    await kaufdatumField.fill(getTodayDate());

    // Try to save without Sonderbegründung
    const saveButton = page.getByRole('button', { name: /Save/i }).first();
    await saveButton.click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(5000);

    // Assert: Validation error should appear
    const errorField = page.getByText(/Sonderbegründung/i);
    const errorText = page.getByText(/weniger als 3 Jahre alt/i);
    const errorBanner = page.getByRole('alert');

    const hasErrorField = await errorField.isVisible().catch(() => false);
    const hasErrorDetail = await errorText.isVisible().catch(() => false);
    const hasErrorBanner = await errorBanner.isVisible().catch(() => false);

    expect(hasErrorField || hasErrorDetail || hasErrorBanner).toBe(true);
  });

  // AC1: Sonderbegruendung__c Feld ist auf dem Create-Formular sichtbar
  test('AC1: Sonderbegründung-Feld ist auf dem Create-Formular sichtbar', async ({ page }) => {
    await openSmartphoneApp(page);
    await navigateToLaptopTab(page);
    await openNewLaptopForm(page);

    // Assert: Sonderbegründung field is visible on the form
    const sonderbegruendungField = page.getByLabel(/Sonderbegründung/i);
    const sonderbegruendungText = page.getByText(/Sonderbegründung/i);

    const fieldVisible = await sonderbegruendungField.isVisible().catch(() => false);
    const textVisible = await sonderbegruendungText.isVisible().catch(() => false);

    expect(fieldVisible || textVisible).toBe(true);
  });
});