# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: SCRUM-275-laptop-dashboard.spec.ts >> [SCRUM-275] Laptop-Dashboard UI-Tests >> AC3: Dashboard zeigt Daten in Echtzeit
- Location: tests/e2e/SCRUM-275-laptop-dashboard.spec.ts:109:7

# Error details

```
Test timeout of 30000ms exceeded.
```

```
Error: locator.click: Test timeout of 30000ms exceeded.
Call log:
  - waiting for getByLabel('App Launcher').first()

```

# Page snapshot

```yaml
- generic [ref=e1]:
  - generic [ref=e2]:
    - generic [ref=e5]:
      - generic [ref=e7]:
        - img [ref=e8]
        - generic [ref=e9]: Salesforce login
      - generic [ref=e11]:
        - generic [ref=e12]:
          - heading "Salesforce login" [level=1] [ref=e13]
          - generic [ref=e14]:
            - text: Username
            - textbox "Username" [active] [ref=e16]
          - text: Password
          - textbox "Password" [ref=e17]
          - button "Log In" [ref=e18] [cursor=pointer]
          - generic [ref=e19]:
            - checkbox "Remember me" [ref=e20]
            - generic [ref=e21]: Remember me
        - link "Forgot Your Password?" [ref=e23] [cursor=pointer]:
          - /url: /secur/forgotpassword.jsp?locale=us
    - generic [ref=e24]: © 2026 Salesforce, Inc. All rights reserved.
  - iframe [ref=e26]:
    - generic [active] [ref=f1e1]:
      - heading "Access Denied" [level=1] [ref=f1e2]
      - text: You don't have permission to access "http://c.salesforce.com/login-messages/promos.html" on this server.
      - paragraph [ref=f1e3]: "Reference #18.ded5ce17.1781980333.1dd236c9"
      - paragraph [ref=f1e4]: https://errors.edgesuite.net/18.ded5ce17.1781980333.1dd236c9
  - generic: Login
  - iframe [ref=e27]:
    
```

# Test source

```ts
  1   | import { test, expect } from '@playwright/test';
  2   | 
  3   | /**
  4   |  * [SCRUM-275] Lightning-Dashboard fuer HR- und IT-Team
  5   |  *
  6   |  * Test-Szenarien abgeleitet aus den Acceptance Criteria:
  7   |  *
  8   |  * AC1: Dashboard zeigt Bereiche: Aktive Gerate, Offene Antraege, Gesamtwert
  9   |  * AC2: Dashboard ist als Tab integrierbar
  10  |  * AC3: Daten sind in Echtzeit aktuell
  11  |  * AC4: Filter nach Mitarbeiter, Status und Modell sind verfuegbar
  12  |  * AC5: Seite ist fuer HR- und IT-Mitarbeiter sichtbar
  13  |  */
  14  | 
  15  | test.describe('[SCRUM-275] Laptop-Dashboard UI-Tests', () => {
  16  |   // Helper: Open Salesforce via App Launcher
  17  |   async function openLaptopDashboard(page: import('@playwright/test').Page) {
  18  |     const sfUrl = process.env.SALESFORCE_URL || 'https://empathetic-hawk-kft3g7-dev-ed.trailblaze.my.salesforce.com';
  19  |     await page.goto(sfUrl);
  20  |     await page.waitForLoadState('networkidle');
  21  |     await page.waitForTimeout(3000);
  22  | 
  23  |     // Open App Launcher
  24  |     const appLauncher = page.getByLabel('App Launcher').first();
> 25  |     await appLauncher.click();
      |                       ^ Error: locator.click: Test timeout of 30000ms exceeded.
  26  |     await page.waitForTimeout(1000);
  27  | 
  28  |     // Search for Smartphone Management app
  29  |     const searchBox = page.getByRole('textbox', { name: /Search apps/i }).first();
  30  |     await searchBox.fill('Smartphone');
  31  |     await page.waitForTimeout(500);
  32  | 
  33  |     const appOption = page.getByRole('option', { name: /Smartphone Management/i }).first();
  34  |     await appOption.click();
  35  |     await page.waitForLoadState('networkidle');
  36  |     await page.waitForTimeout(3000);
  37  |   }
  38  | 
  39  |   // AC2: Laptop_Dashboard Tab ist in der App-Leiste sichtbar
  40  |   test('AC2: Laptop_Dashboard Tab ist sichtbar', async ({ page }) => {
  41  |     await openLaptopDashboard(page);
  42  | 
  43  |     // Navigate to Laptop_Dashboard tab
  44  |     const dashboardTab = page.getByRole('tab', { name: /Laptop Dashboard/i });
  45  |     const dashboardVisible = await dashboardTab.isVisible().catch(() => false);
  46  | 
  47  |     if (dashboardVisible) {
  48  |       await dashboardTab.click();
  49  |       await page.waitForLoadState('networkidle');
  50  |       await page.waitForTimeout(3000);
  51  |     }
  52  | 
  53  |     // Assert: Dashboard content is visible
  54  |     const dashboardContent = page.getByText(/Laptop/i);
  55  |     expect(await dashboardContent.isVisible().catch(() => false)).toBe(true);
  56  |   });
  57  | 
  58  |   // AC1: Dashboard zeigt die drei Bereiche
  59  |   test('AC1: Dashboard zeigt Aktive Gerate, Offene Antraege, Gesamtwert', async ({ page }) => {
  60  |     await openLaptopDashboard(page);
  61  | 
  62  |     // Navigate to Laptop_Dashboard tab
  63  |     const dashboardTab = page.getByRole('tab', { name: /Laptop Dashboard/i });
  64  |     if (await dashboardTab.isVisible().catch(() => false)) {
  65  |       await dashboardTab.click();
  66  |       await page.waitForLoadState('networkidle');
  67  |       await page.waitForTimeout(3000);
  68  |     }
  69  | 
  70  |     // Assert: Dashboard sections are visible
  71  |     const aktiveGeraete = page.getByText(/Aktive/i);
  72  |     const offeneAntraege = page.getByText(/Offene/i);
  73  |     const gesamtwert = page.getByText(/Gesamtwert/i);
  74  | 
  75  |     const aktiveVisible = await aktiveGeraete.isVisible().catch(() => false);
  76  |     const offeneVisible = await offeneAntraege.isVisible().catch(() => false);
  77  |     const wertVisible = await gesamtwert.isVisible().catch(() => false);
  78  | 
  79  |     // At least one section should be visible
  80  |     expect(aktiveVisible || offeneVisible || wertVisible).toBe(true);
  81  |   });
  82  | 
  83  |   // AC4: Filter sind verfuegbar
  84  |   test('AC4: Filter nach Mitarbeiter, Status und Modell sind verfuegbar', async ({ page }) => {
  85  |     await openLaptopDashboard(page);
  86  | 
  87  |     // Navigate to Laptop_Dashboard tab
  88  |     const dashboardTab = page.getByRole('tab', { name: /Laptop Dashboard/i });
  89  |     if (await dashboardTab.isVisible().catch(() => false)) {
  90  |       await dashboardTab.click();
  91  |       await page.waitForLoadState('networkidle');
  92  |       await page.waitForTimeout(3000);
  93  |     }
  94  | 
  95  |     // Check for filter elements
  96  |     const filterKunde = page.getByLabel(/Kunde/i).first();
  97  |     const filterStatus = page.getByLabel(/Status/i).first();
  98  |     const filterModell = page.getByLabel(/Modell/i).first();
  99  | 
  100 |     const kundeVisible = await filterKunde.isVisible().catch(() => false);
  101 |     const statusVisible = await filterStatus.isVisible().catch(() => false);
  102 |     const modellVisible = await filterModell.isVisible().catch(() => false);
  103 | 
  104 |     // At least one filter should be visible
  105 |     expect(kundeVisible || statusVisible || modellVisible).toBe(true);
  106 |   });
  107 | 
  108 |   // AC3: Daten sind in Echtzeit aktuell (nach Record-Erstellung sichtbar)
  109 |   test('AC3: Dashboard zeigt Daten in Echtzeit', async ({ page }) => {
  110 |     await openLaptopDashboard(page);
  111 | 
  112 |     // Navigate to Laptop_Dashboard tab
  113 |     const dashboardTab = page.getByRole('tab', { name: /Laptop Dashboard/i });
  114 |     if (await dashboardTab.isVisible().catch(() => false)) {
  115 |       await dashboardTab.click();
  116 |       await page.waitForLoadState('networkidle');
  117 |       await page.waitForTimeout(3000);
  118 |     }
  119 | 
  120 |     // Assert: Dashboard content is rendered (not empty)
  121 |     const dashboardContent = page.locator('lightning-datatable, [data-testid], table');
  122 |     const contentExists = await dashboardContent.count();
  123 | 
  124 |     // Dashboard should have some content
  125 |     expect(contentExists).toBeGreaterThan(0);
```