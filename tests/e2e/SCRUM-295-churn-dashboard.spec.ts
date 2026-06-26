import { test, expect } from '@playwright/test';

test.describe('[SCRUM-295] Churn Prevention Reports & Dashboard', () => {
  // Acceptance Criterion 1: Report "Churn Gefahr Accounts" exists
  test('Acceptance Criterion 1: Report Churn_Gefahr_Accounts exists', async ({ page }) => {
    await page.goto('/lightning/o/Report/home');
    await expect(page).toHaveTitle(/Salesforce/);

    const response = await page.goto('/lightning/r/Report/Churn_Gefahr_Accounts/view');
    expect(response?.status()).toBe(200);
  });

  // Acceptance Criterion 2: Report "Offene Churn Aufgaben nach Owner" exists
  test('Acceptance Criterion 2: Report Offene_Churn_Aufgaben_nach_Owner exists', async ({ page }) => {
    await page.goto('/lightning/o/Report/home');
    await expect(page).toHaveTitle(/Salesforce/);

    const response = await page.goto('/lightning/r/Report/Offene_Churn_Aufgaben_nach_Owner/view');
    expect(response?.status()).toBe(200);
  });

  // Acceptance Criterion 3: Report "Churn Aufgaben Erledigt vs Offen pro Owner" exists
  test('Acceptance Criterion 3: Report Churn_Aufgaben_Erledigt_vs_Offen_pro_Owner exists', async ({ page }) => {
    await page.goto('/lightning/o/Report/home');
    await expect(page).toHaveTitle(/Salesforce/);

    const response = await page.goto('/lightning/r/Report/Churn_Aufgaben_Erledigt_vs_Offen_pro_Owner/view');
    expect(response?.status()).toBe(200);
  });

  // Acceptance Criterion 4: Report "Top 20 Inaktivste Kunden" exists
  test('Acceptance Criterion 4: Report Top_20_Inaktivste_Kunden exists', async ({ page }) => {
    await page.goto('/lightning/o/Report/home');
    await expect(page).toHaveTitle(/Salesforce/);

    const response = await page.goto('/lightning/r/Report/Top_20_Inaktivste_Kunden/view');
    expect(response?.status()).toBe(200);
  });

  // Acceptance Criterion 5: Dashboard "Churn Prevention Dashboard" exists
  test('Acceptance Criterion 5: Dashboard Churn_Prevention_Dashboard exists', async ({ page }) => {
    await page.goto('/lightning/o/Dashboard/home');
    await expect(page).toHaveTitle(/Salesforce/);

    const response = await page.goto('/lightning/r/Dashboard/Churn_Prevention_Dashboard/view');
    expect(response?.status()).toBe(200);
  });
});
