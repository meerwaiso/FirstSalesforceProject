import { chromium } from '@playwright/test';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

/**
 * Auth setup for Salesforce E2E tests.
 *
 * Uses an injected session cookie (sid) from the active SFDX org
 * instead of navigating through a login page or frontdoor URLs.
 *
 * Steps:
 * 1. Run `sf org display --json` to fetch the current org data
 * 2. Extract `accessToken` (sid) and `instanceUrl` from the result
 * 3. Create a fresh Playwright browser context
 * 4. Inject the Salesforce session cookie into the context
 * 5. Navigate to the Salesforce home page to verify the session
 * 6. Save the authenticated state for reuse in all test runs
 */
export default async function setup() {
  // ── Step 1: Fetch org data via SFDX CLI ──────────────────────────
  let orgData: { accessToken: string; instanceUrl: string };

  try {
    const raw = execSync('sf org display --json', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const parsed = JSON.parse(raw);
    orgData = parsed.result;
  } catch (error: any) {
    throw new Error(
      `Failed to retrieve Salesforce org data via "sf org display --json". ` +
        `Make sure you have an active default org. ` +
        `Error: ${error.message || error}`
    );
  }

  const { accessToken, instanceUrl } = orgData;

  if (!accessToken || !instanceUrl) {
    throw new Error(
      'Org data is missing "accessToken" or "instanceUrl". ' +
        'The default org may not be properly authenticated.'
    );
  }

  // ── Step 2: Der cookie-ready domain ─────────────────────────────
  // Strip the protocol (https:// or http://) to get the bare domain
  const domain = instanceUrl.replace(/^https?:\/\//, '');

  // ── Step 3: Create browser context ──────────────────────────────
  const browser = await chromium.launch();
  const context = await browser.newContext();

  // ── Step 4: Inject the Salesforce session cookie (sid) ──────────
  await context.addCookies([
    {
      name: 'sid',
      value: accessToken,
      domain: domain,
      path: '/',
      httpOnly: true,
      secure: true,
      sameSite: 'None',
    },
  ]);

  // ── Step 5: Navigate to the Salesforce home page ────────────────
  const homeUrl = `${instanceUrl}/lightning/n/Home`;
  const page = await context.newPage();

  await page.goto(homeUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

  // ── Step 6: Wait for the full Lightning UI to finish loading ────
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);

  // ── Step 7: Save the authenticated state ────────────────────────
  const authDir = path.resolve('auth');
  if (!fs.existsSync(authDir)) {
    fs.mkdirSync(authDir, { recursive: true });
  }

  await context.storageState({ path: path.join(authDir, 'storage-state.json') });

  await browser.close();

  console.log(`[auth.setup] Session cookie injected successfully for org: ${instanceUrl}`);
}