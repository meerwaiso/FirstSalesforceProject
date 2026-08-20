import { defineConfig, devices } from '@playwright/test';

// Self-contained E2E config for SCRUM-329. No globalSetup / no storageState —
// the spec reads its sid from /tmp/scr329/sid_clean.txt and frontdoor-auths itself,
// so no `sf` CLI calls happen at runtime (clean, consent-safe).
export default defineConfig({
  testDir: './tests/e2e',
  testMatch: /SCRUM-329-testfeld2008\.spec\.ts/,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 200000,
  reporter: [
    ['list'],
    ['json', { outputFile: 'test-report/scr329-results.json' }],
  ],
  use: {
    baseURL: 'https://resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com',
    viewport: { width: 1440, height: 900 },
    trace: 'on-first-retry',
    screenshot: 'on',
  },
  projects: [
    // Note: no `devices['Desktop Chrome']` here — the spec's test.use() sets a real
    // Chrome userAgent (required for LEX to hydrate; raw Headless UA renders an empty skeleton).
    { name: 'chromium' },
  ],
});
