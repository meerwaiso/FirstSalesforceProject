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
  use: {
    baseURL: process.env.SALESFORCE_URL || 'https://empathetic-hawk-kft3g7-dev-ed.trailblaze.my.salesforce.com',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});