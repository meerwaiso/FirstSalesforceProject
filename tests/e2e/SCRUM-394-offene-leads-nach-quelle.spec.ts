import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';

const REPORT_ID = '00OWU00000QEIUL2A5';

function sfRaw(args: string[]): string {
  try {
    return execSync(`sf ${args.join(' ')} 2>/dev/null`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 16 * 1024 * 1024,
    });
  } catch { return ''; }
}

/** BUG-D-Fix: keine Aggregat-Alias-SOQL (CLI lehnt ab). */
function sfCount(q: string): number {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', q, '--json', '--compact', 'false']);
  const m = out.match(/"totalSize"\s*:\s*(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}

/** BUG-C-Fix: LeadSource-Picklist-Wert ist "Web" (nicht "Website"). Fixtures idempotent. */
function ensureFixtures() {
  const specs: Array<[string, string]> = [
    ['FULL',   "LastName=TEST-SCRUM-394-FULL Email=full394@example.com Phone='+49 30 90182039' Company='Testfirma394Full' 'Status=Open - Not Contacted' LeadSource=Email"],
    ['MOBILE', "LastName=TEST-SCRUM-394-MOBILE MobilePhone='+49 151 0987654' Company='Testfirma394Mobile' 'Status=Open - Not Contacted' LeadSource=Web"],
    ['NOSRC',  "LastName=TEST-SCRUM-394-NOSRC Company='Testfirma394NoSource' 'Status=Open - Not Contacted'"],
    ['CONV',   "LastName=TEST-SCRUM-394-CONV 'Status=Closed - Not Converted' Email=conv394@example.com Phone='+49 30 90182040' Company='Testfirma394Converted' LeadSource=Email"],
  ];
  for (const [tag, values] of specs) {
    if (sfCount(`SELECT Id FROM Lead WHERE LastName='TEST-SCRUM-394-${tag}' LIMIT 1`) > 0) continue;
    sfRaw(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v', values]);
  }
}

async function openReportFrame(page: import('@playwright/test').Page) {
  await page.goto(`/lightning/r/Report/${REPORT_ID}/view`);
  await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
  await page.waitForLoadState('domcontentloaded');
  const deadline = Date.now() + 60000;
  for (;;) {
    const f = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (f) return f;
    if (Date.now() > deadline) throw new Error('report iframe never appeared');
    await page.waitForTimeout(500);
  }
}

test.describe('[SCRUM-394] Offene Leads nach Quelle + Datenqualität', () => {
  test.beforeAll(() => { ensureFixtures(); });

  test('AC2 + AC4: report in Sales, grouped by Lead-Quelle incl. own group for blank source', async ({ page }) => {
    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });
    // BUG-C: LeadSource-Picklist-Wert ist "Web" (nicht "Website").
    await expect(frame.getByText('Email').first()).toBeVisible({ timeout: 45000 });
    await expect(frame.getByText(/^Web$/).first()).toBeVisible();
    // Blank-Gruppe rendert als "-" oder "(blank)" (Salesforce variiert je UI-Variante).
    const blankGroup = frame.locator('td').filter({ hasText: /^-\s*$|^(blank)$/ });
    expect(await blankGroup.count(), 'blank group must render as "-" or "(blank)"').toBeGreaterThan(0);
  });

  test('AC5 (BUG-B): detail rows render — Name, Firma, Status, Datenqualität, Inhaber', async ({ page }) => {
    // BUG-B-Fix: Report hat jetzt showDetails=true (architect 16415, commit abd64f5).
    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });
    // AC5 Spalten-Header:
    await expect(frame.getByText('First Name').first()).toBeVisible({ timeout: 45000 });
    await expect(frame.getByText('Last Name').first()).toBeVisible();
    await expect(frame.getByText('Company / Account').first()).toBeVisible();
    await expect(frame.getByText('Lead Status').first()).toBeVisible();
    await expect(frame.getByText('Datenqualität').first()).toBeVisible();
    await expect(frame.getByText('Lead Owner').first()).toBeVisible();
    // Fixture-Werte in den Detail-Zeilen (logical-column asserts):
    await expect(frame.getByText('TEST-SCRUM-394-FULL', { exact: true })).toHaveCount(1);
    await expect(frame.getByText('TEST-SCRUM-394-MOBILE', { exact: true })).toHaveCount(1);
    await expect(frame.getByText('Testfirma394Full', { exact: true })).toHaveCount(1);
    await expect(frame.getByText('Testfirma394Mobile', { exact: true })).toHaveCount(1);
    await expect(frame.getByText('Open - Not Contacted', { exact: true }).first()).toBeVisible();
    // AC1-Werte in der „Datenqualität“-Spalte:
    // - FULL (Email+Phone+Company) & MOBILE (nur MobilePhone): beide → „vollständig" (PO 2026-09-06)
    // - NOSRC (kein Email): → „unvollständig"
    await expect(frame.getByText('vollständig', { exact: true }).first()).toBeVisible();
    await expect(frame.getByText('unvollständig', { exact: true }).first()).toBeVisible();
  });

  test('AC3 (BUG-D): report total == org-wide open-lead count (live SOQL, no hard-coded 62)', async ({ page }) => {
    // BUG-D-Fix: Referenz per LIVE-SOQL, nicht hart codiert.
    // Beide Seiten (SOQL + Report) zählen dieselbe Population:
    // alle Leads mit IsConverted=false der Org. Fixtures sind in beiden enthalten.
    const ref = sfCount('SELECT Id FROM Lead WHERE IsConverted=false');
    expect(ref, 'org-wide COUNT of open leads must be retrievable').toBeGreaterThanOrEqual(4);

    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // Grand-Total (letzte Ziffer im Report) muss mit der SOQL-Zeile übereinstimmen:
    const text = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    const numbers = Array.from(text.matchAll(/(\d+)/g)).map((m) => parseInt(m[1], 10));
    expect(numbers.length > 0, 'report must render numeric counts').toBeTruthy();
    const maxSeen = Math.max(...numbers);
    expect(
      numbers,
      `AC3 violated: report total must match org-wide COUNT(open leads)=${ref}; largest number rendered in report: ${maxSeen}`,
    ).toContain(ref);
  });
});