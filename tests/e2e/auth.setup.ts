import { chromium } from '@playwright/test';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

/**
 * Auth setup for Salesforce E2E tests.
 *
 * Exchanges the SFDX org access token for a real Lightning UI session via
 * `/secur/frontdoor.jsp`.
 *
 * NOTE: injecting the access token directly as a `sid` cookie does NOT work.
 * Salesforce serves the UI from two domains (`*.my.salesforce.com` and
 * `*.lightning.force.com`) and each needs its own server-issued session
 * cookies. A raw `sid` cookie gets bounced to `/visualforce/session` and
 * ends up on the login page. frontdoor.jsp performs that handshake and sets
 * the cookies for both domains.
 *
 * Steps:
 * 1. Run `sf org display --json` / `sf org auth show-access-token --json`
 * 2. Navigate to frontdoor.jsp with the token, returning to Lightning home
 * 3. Verify the Lightning shell actually rendered (positive check)
 * 4. Save the authenticated state for reuse in all test runs
 */

const AUTH_DIR = path.resolve('auth');
const AUTH_FILE = path.join(AUTH_DIR, 'storage-state.json');

/** Run an `sf` command and parse its JSON, stripping ANSI escape codes. */
function sfJson(command: string): any {
  // stderr is piped separately — the sf CLI writes update/deprecation
  // warnings there, which would otherwise corrupt the JSON payload.
  const raw = execSync(command, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
}

export default async function setup() {
  // ── Step 1: Fetch org data via SFDX CLI ──────────────────────────
  let instanceUrl: string;
  let accessToken: string;

  try {
    instanceUrl = sfJson('sf org display --json').result.instanceUrl;
    // `sf org display` redacts the token — fetch the real one separately
    accessToken = sfJson('sf org auth show-access-token --json').result.accessToken;
  } catch (error: any) {
    throw new Error(
      `[auth.setup] Failed to retrieve Salesforce org data. ` +
        `Make sure you have an active default org ("sf org login web"). ` +
        `Error: ${error.message || error}`
    );
  }

  if (!accessToken || !instanceUrl) {
    throw new Error(
      '[auth.setup] Org data is missing "accessToken" or "instanceUrl". ' +
        'The default org may not be properly authenticated.'
    );
  }

  // ── Step 2: Derive the Lightning domain ──────────────────────────
  const lightningUrl = instanceUrl.replace('.my.salesforce.com', '.lightning.force.com');
  const homeUrl = `${lightningUrl}/lightning/page/home`;

  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  // ── Step 3: frontdoor handshake ──────────────────────────────────
  // 'commit' rather than 'load': frontdoor.jsp answers with a bounce page
  // that redirects onward, so waiting for a full load here would stall.
  const frontdoorUrl =
    `${instanceUrl}/secur/frontdoor.jsp` +
    `?sid=${encodeURIComponent(accessToken)}` +
    `&retURL=${encodeURIComponent(homeUrl)}`;

  await page.goto(frontdoorUrl, { waitUntil: 'commit', timeout: 60000 });

  // ── Step 4: Verify the session POSITIVELY ────────────────────────
  // Checking merely that the URL lacks "login" is not enough: the bounce
  // pages contain no such marker, so a failed handshake would look like a
  // success and get saved as a logged-out storage state.
  try {
    await page.waitForURL(/lightning\.force\.com\/lightning/, { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    // The global header only renders for an authenticated Lightning session.
    await page
      .locator('div.slds-global-header, one-appnav')
      .first()
      .waitFor({ state: 'visible', timeout: 60000 });
  } catch (error: any) {
    const shot = path.join(AUTH_DIR, 'auth-failure.png');
    if (!fs.existsSync(AUTH_DIR)) fs.mkdirSync(AUTH_DIR, { recursive: true });
    await page.screenshot({ path: shot }).catch(() => {});
    await browser.close();
    throw new Error(
      `[auth.setup] Lightning session could not be established.\n` +
        `  Landed on: ${page.url()}\n` +
        `  Screenshot: ${shot}\n` +
        `  The org session likely expired — re-authenticate with "sf org login web".\n` +
        `  Original error: ${error.message || error}`
    );
  }

  // ── Step 5: Save the authenticated state ─────────────────────────
  if (!fs.existsSync(AUTH_DIR)) {
    fs.mkdirSync(AUTH_DIR, { recursive: true });
  }

  await context.storageState({ path: AUTH_FILE });
  await browser.close();

  console.log(`[auth.setup] Lightning session established for org: ${instanceUrl}`);
}
