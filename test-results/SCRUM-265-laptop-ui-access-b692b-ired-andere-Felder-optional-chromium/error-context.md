# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: SCRUM-265-laptop-ui-access.spec.ts >> [SCRUM-265] Laptop-Objekt UI-Zugriff >> Edge Case: Nur Name-Feld required, andere Felder optional
- Location: tests/e2e/SCRUM-265-laptop-ui-access.spec.ts:281:7

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
      - paragraph [ref=f1e3]: "Reference #18.d51d1002.1781963863.60950558"
      - paragraph [ref=f1e4]: https://errors.edgesuite.net/18.d51d1002.1781963863.60950558
  - generic: Login
  - iframe [ref=e27]:
    
```

# Test source

```ts
  1   | import { test, expect } from '@playwright/test';
  2   | 
  3   | /**
  4   |  * [SCRUM-265] Neues Custom Object 'Laptop' in Salesforce erstellen
  5   |  *
  6   |  * Test-Szenarien abgeleitet aus den Acceptance Criteria:
  7   |  *
  8   |  * AC1: Custom Object Laptop__c existiert in Salesforce (Deployed, Public)
  9   |  * AC2: Objekt hat einen Tab "Laptop", der in der Navigation sichtbar ist
  10  |  * AC3: Page Layout "Laptop Layout" ist konfiguriert und zeigt alle Felder
  11  |  * AC4: Compact Layout "Laptop Compact" ist konfiguriert
  12  |  * AC5: Permission Set "Laptop_Permissions" gewaehrt CRUD auf Laptop__c
  13  |  * AC6: Alle definierten Felder sind auf dem Create-Formular sichtbar und editierbar
  14  |  * AC7: Das Name-Feld ist required; andere Felder sind optional
  15  |  * AC8: Benutzer koennen ueber Tab → New einen Laptop-Record erstellen und speichern
  16  |  * AC9: Reports und Search sind fuer das Objekt aktiviert
  17  |  * AC10: Activities sind fuer das Objekt aktiviert
  18  |  */
  19  | 
  20  | const EXPECTED_FIELDS = [
  21  |   'Name',
  22  |   'Seriennummer',
  23  |   'Marke',
  24  |   'Modell',
  25  |   'Kunde',
  26  |   'Verkäufer',
  27  |   'Preis',
  28  |   'Kondition',
  29  |   'Farbe',
  30  |   'CPU',
  31  |   'RAM',
  32  |   'Speicherkapazität',
  33  |   'Kaufdatum',
  34  |   'Verkaufsdatum',
  35  |   'Garantie bis',
  36  |   'Gewährleistungsnummer',
  37  |   'Status',
  38  | ];
  39  | 
  40  | const TEST_DATA = {
  41  |   name: 'Test MacBook Pro 16',
  42  |   serieNummer: 'SN-LAPTOP-2026-001',
  43  |   marke: 'Apple',
  44  |   modell: 'MacBook Pro 16"',
  45  |   kunde: 'Max Mustermann',
  46  |   verkaeufer: 'Lisa Müller',
  47  |   preis: '2499.00',
  48  |   farbe: 'Space Grau',
  49  |   cpu: 'M3 Pro',
  50  |   ram: '32 GB',
  51  |   speicher: '1 TB SSD',
  52  | };
  53  | 
  54  | test.describe('[SCRUM-265] Laptop-Objekt UI-Zugriff', () => {
  55  |   // Helper: Open Smartphone Management app via App Launcher
  56  |   async function openSmartphoneApp(page: import('@playwright/test').Page) {
  57  |     const sfUrl = process.env.SALESFORCE_URL || 'https://empathetic-hawk-kft3g7-dev-ed.trailblaze.my.salesforce.com';
  58  |     await page.goto(sfUrl);
  59  |     await page.waitForLoadState('networkidle');
  60  |     await page.waitForTimeout(3000);
  61  | 
  62  |     // Open App Launcher (three-dot grid icon)
  63  |     const appLauncher = page.getByLabel('App Launcher').first();
> 64  |     await appLauncher.click();
      |                       ^ Error: locator.click: Test timeout of 30000ms exceeded.
  65  |     await page.waitForTimeout(1000);
  66  | 
  67  |     // Search for Smartphone Management app
  68  |     const searchBox = page.getByRole('textbox', { name: /Search apps/i }).first();
  69  |     await searchBox.fill('Smartphone');
  70  |     await page.waitForTimeout(500);
  71  | 
  72  |     // Click on the app
  73  |     const appOption = page.getByRole('option', { name: /Smartphone Management/i }).first();
  74  |     await appOption.click();
  75  |     await page.waitForLoadState('networkidle');
  76  |     await page.waitForTimeout(3000);
  77  |   }
  78  | 
  79  |   // AC1 + AC2: Custom Object Laptop__c existiert und Tab ist sichtbar
  80  |   test('AC1+AC2: Laptop-Tab ist in der App-Leiste sichtbar', async ({ page }) => {
  81  |     await openSmartphoneApp(page);
  82  | 
  83  |     // Assert: Laptop tab or heading is visible
  84  |     const laptopTab = page.getByRole('tab', { name: /Laptop/i });
  85  |     const laptopHeading = page.getByRole('heading', { name: /Laptop/i });
  86  |     const laptopText = page.getByText(/Laptop/i);
  87  | 
  88  |     const tabVisible = await laptopTab.isVisible().catch(() => false);
  89  |     const headingVisible = await laptopHeading.isVisible().catch(() => false);
  90  |     const textVisible = await laptopText.isVisible().catch(() => false);
  91  | 
  92  |     expect(tabVisible || headingVisible || textVisible).toBe(true);
  93  |   });
  94  | 
  95  |   // AC5: Permission Set gewaehrt CRUD — New-Button ist sichtbar
  96  |   test('AC5: CRUD-Permission — New-Button ist sichtbar', async ({ page }) => {
  97  |     await openSmartphoneApp(page);
  98  | 
  99  |     // Navigate to Laptop tab if needed
  100 |     const laptopTab = page.getByRole('tab', { name: /Laptop/i });
  101 |     if (await laptopTab.isVisible().catch(() => false)) {
  102 |       await laptopTab.click();
  103 |       await page.waitForLoadState('networkidle');
  104 |       await page.waitForTimeout(2000);
  105 |     }
  106 | 
  107 |     // Assert: New button is visible and enabled
  108 |     const newButton = page.getByRole('button', { name: /New/i }).first();
  109 |     await expect(newButton).toBeVisible({ timeout: 10000 });
  110 |     await expect(newButton).toBeEnabled();
  111 |   });
  112 | 
  113 |   // AC3: Page Layout zeigt alle 17 Felder (Name + 16 Custom Fields)
  114 |   test('AC3: Page Layout enthaelt alle 17 Felder', async ({ page }) => {
  115 |     await openSmartphoneApp(page);
  116 | 
  117 |     // Navigate to Laptop tab
  118 |     const laptopTab = page.getByRole('tab', { name: /Laptop/i });
  119 |     if (await laptopTab.isVisible().catch(() => false)) {
  120 |       await laptopTab.click();
  121 |       await page.waitForLoadState('networkidle');
  122 |       await page.waitForTimeout(2000);
  123 |     }
  124 | 
  125 |     // Click New button to open create form
  126 |     const newButton = page.getByRole('button', { name: /New/i }).first();
  127 |     await newButton.click();
  128 |     await page.waitForLoadState('networkidle');
  129 |     await page.waitForTimeout(2000);
  130 | 
  131 |     // Assert: All 17 fields are present on the layout
  132 |     for (const field of EXPECTED_FIELDS) {
  133 |       const fieldLabel = page.getByText(field, { exact: true });
  134 |       await expect(fieldLabel).toBeVisible({ timeout: 5000 });
  135 |     }
  136 |   });
  137 | 
  138 |   // AC6: Alle Felder sind auf dem Create-Formular sichtbar und editierbar
  139 |   test('AC6: Alle Felder sind sichtbar und editierbar', async ({ page }) => {
  140 |     await openSmartphoneApp(page);
  141 | 
  142 |     // Navigate to Laptop tab
  143 |     const laptopTab = page.getByRole('tab', { name: /Laptop/i });
  144 |     if (await laptopTab.isVisible().catch(() => false)) {
  145 |       await laptopTab.click();
  146 |       await page.waitForLoadState('networkidle');
  147 |       await page.waitForTimeout(2000);
  148 |     }
  149 | 
  150 |     const newButton = page.getByRole('button', { name: /New/i }).first();
  151 |     await newButton.click();
  152 |     await page.waitForLoadState('networkidle');
  153 |     await page.waitForTimeout(2000);
  154 | 
  155 |     // Test Name field
  156 |     const nameField = page.getByLabel(/Name/i).first();
  157 |     await expect(nameField).toBeVisible();
  158 |     await nameField.fill('Edit Test');
  159 |     await expect(nameField).toHaveValue('Edit Test');
  160 |     await nameField.clear();
  161 | 
  162 |     // Test Seriennummer field
  163 |     const serieField = page.getByLabel(/Seriennummer/i);
  164 |     await expect(serieField).toBeVisible();
```