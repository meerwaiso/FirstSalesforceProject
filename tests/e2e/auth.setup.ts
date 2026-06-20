import { test as setup } from '@playwright/test';

/**
 * Auth setup for Salesforce E2E tests.
 * Navigates to the Salesforce org and saves the authenticated state.
 * If already logged in, saves the session immediately.
 * If on the login page, waits for manual login by the user.
 */
setup('authenticate', async ({ page }) => {
  const sfUrl = process.env.SALESFORCE_URL || 'https://empathetic-hawk-kft3g7-dev-ed.trailblaze.my.salesforce.com';

  await page.goto(sfUrl);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);

  // Check if we're on the login page by looking for username/password fields
  const loginPage = page.locator('input[type="email"], input[type="text"][id="username"]');
  const isLoginPage = await loginPage.count();

  if (isLoginPage > 0) {
    // Login page detected - check for environment credentials
    const username = process.env.SALESFORCE_USERNAME;
    const password = process.env.SALESFORCE_PASSWORD;

    if (username && password) {
      // Auto-login with credentials from environment
      await loginPage.first().fill(username);
      const passwordField = page.locator('input[type="password"]').first();
      await passwordField.fill(password);
      await page.getByRole('button', { name: /Sign in|Anmelden/i }).click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(5000);
    } else {
      // No credentials - user must log in manually
      console.log('No Salesforce credentials found in environment. Please log in manually.');
      // Wait for the page to no longer be the login page (user logged in manually)
      await page.waitForSelector('input[type="email"], input[type="text"][id="username"]', { state: 'hidden' });
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(5000);
    }
  }

  // Save the authenticated state to storageState file
  await page.context().storageState({ path: 'auth/storage-state.json' });
});