import { defineConfig, devices } from '@playwright/test';

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
    baseURL: process.env.SALESFORCE_URL || 'https://resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com',
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
