import { test, expect } from '@playwright/test';
import { resolveOrg } from './org';

/**
 * Session smoke test.
 *
 * Run this FIRST whenever the suite starts failing. It separates the two
 * failure modes that otherwise look identical from a test report:
 *
 *   - this test fails  -> the auth/session layer is broken
 *                         (re-run `sf org login web`, then retry)
 *   - this test passes -> the session is fine and the failing specs are
 *                         hitting missing metadata or bad locators
 *
 * It deliberately touches only standard Salesforce UI, so it stays valid
 * no matter which custom metadata is deployed to the org.
 */
test.describe('[SMOKE] Salesforce session', () => {
  test('authenticated session reaches the Lightning shell', async ({ page }) => {
    await page.goto('/lightning/page/home', { waitUntil: 'domcontentloaded' });

    // Never landed on (or bounced back to) a login screen
    await expect(page).toHaveURL(/lightning\.force\.com\/lightning/);
    await expect(page.locator('input[name="username"]')).toHaveCount(0);

    // The global header only renders for an authenticated session
    await expect(page.locator('div.slds-global-header, one-appnav').first()).toBeVisible({
      timeout: 60000,
    });

    // And the App Launcher is reachable — the entry point most specs rely on
    await expect(page.getByRole('button', { name: 'App Launcher' }).first()).toBeVisible();
  });

  test('session is bound to the org the CLI is pointing at', async ({ page }) => {
    const { lightningUrl } = resolveOrg();

    await page.goto('/lightning/page/home', { waitUntil: 'domcontentloaded' });

    // Guards against the classic failure of a stale hardcoded org host:
    // a valid session against the *wrong* org still shows a working UI.
    expect(page.url().startsWith(lightningUrl)).toBe(true);
  });
});
