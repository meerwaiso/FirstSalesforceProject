import { defineConfig, devices } from '@playwright/test';
import { resolveOrg } from './tests/e2e/org';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: [
    ['html', { outputFolder: 'test-report' }],
    ['json', { outputFile: 'test-report/playwright-results.json' }],
  ],
  globalSetup: './tests/e2e/auth.setup',
  use: {
    // The Lightning UI lives on *.lightning.force.com. Pointing baseURL at the
    // *.my.salesforce.com instance host makes every relative /lightning/... goto
    // bounce through the cross-domain session handshake and land on the login page.
    baseURL: resolveOrg().lightningUrl,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    // Use saved auth state to avoid session timeout
    storageState: 'auth/storage-state.json',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
