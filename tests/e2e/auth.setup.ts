import { chromium } from '@playwright/test';

/**
 * Auth setup for Salesforce E2E tests.
 * Navigates to the Salesforce org and saves the authenticated state.
 * If already logged in, saves the session immediately.
 * If on the login page, waits for manual login by the user.
 */
export default async function setup() {
  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  const sfUrl = process.env.SALESFORCE_URL || 'https://empathetic-hawk-kft3g7-dev-ed.trailblaze.my.salesforce.com';

  await page.goto(sfUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(10000);

  // Check if we're on the login page by looking for username/password fields
  const loginField = page.locator('input[type="email"], input[id="username"]');
  const isLoginPage = await loginField.count();

  if (isLoginPage > 0) {
    // Login page detected - check for environment credentials
    const username = process.env.SALESFORCE_USERNAME;
    const password = process.env.SALESFORCE_PASSWORD;

    if (username && password) {
      // Auto-login with credentials from environment
      await loginField.first().fill(username);
      const passwordField = page.locator('input[type="password"]').first();
      await passwordField.fill(password);
      await page.getByRole('button', { name: /Sign in|Anmelden/i }).click();
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(5000);
    } else {
      // No credentials - user must log in manually
      console.log('No Salesforce credentials found in environment. Please log in manually.');
      // Wait for the page to no longer be the login page (user logged in manually)
      await loginField.waitFor({ state: 'hidden', timeout: 60000 });
      await page.waitForTimeout(5000);
    }
  }

  // Save the authenticated state to storageState file
  await context.storageState({ path: 'auth/storage-state.json' });

  await browser.close();
}