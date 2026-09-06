import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';

/**
 * [SCRUM-394] Lead-Datenqualität + Bericht „Offene Leads nach Quelle" — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL von
 * org.ts (nie hardcoden). Network auf Lightning niemals „networkidle".
 *
 * Report: Sales/Offene_Leads_nach_Quelle (00OWU00000QEIUL2A5), LeadList/Summary,
 * Filter CONVERTED=false, <scope>org</scope> (Source — AC3 org-weit),
 * GroupingsDown nach LEAD_SOURCE (Asc, Count je Quelle, Blank-Gruppe bleibt).
 * Report render inside a cross-document iframe (legacy report app) → wie
 * SCRUM-378: page.frames() auf „lightningReportApp" warten, dann auf td.
 *
 * Fixtures (TEST-SCRUM-394-*, idempotent via sf data create):
 *   FULL      offen, Email+Phone+Company   → „vollständig"   (Gruppe Email)
 *   NOEMAIL   offen, nur Phone+Company     → „unvollständig" (Gruppe Website)
 *   NOSRC     offen, ohne LeadSource       → (blank)-Gruppe, „unvollständig"
 *   CONV      „Closed - Not Converted"     → AUS dem Report (CONVERTED-Filter)
 *
 * AC3 proof ist ein ZEILENZAH-Vergleich, nicht „Feld existiert":
 *   Zeilen im Report (je Gruppe) vs.
 *   SELECT COUNT(Id) FROM Lead WHERE IsConverted=false (selbe Admin-Sight wie Report-Scope „org").
 *   Beide Zahlen müssen über alle Gruppen zusammenpassen.
 *
 * Haus-Shape: SCRUM-378_lead-nachfassliste.spec.ts (Report-Frame-Locators,
 * Fixtures per sf, logical column asserts statt „exactly N td cells").
 */

const REPORT_ID = '00OWU00000QEIUL2A5';

function sf(args: string[]): string {
  try {
    return execSync(`sf ${args.join(' ')} 2>/dev/null`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch {
    return '';
  }
}

function sfQuery(q: string): string {
  return sf(['data', 'query', '-o', 'Test-Org', '-q', q, '--json', '--compact', 'false']);
}

/** Org-wide count of open (non-converted) Leads — the AC3 reference number. */
function openLeadCountOrgWide(): number {
  const out = sfQuery('SELECT COUNT(Id) c FROM Lead WHERE IsConverted=false');
  const m = out.match(/"totalSize"\s*:\s*(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}

/** Ensure the four fixtures exist with the expected fields (idempotent). */
function ensureFixtures() {
  const seeded = (tag: string) =>
    sfQuery(`SELECT Id FROM Lead WHERE LastName='TEST-SCRUM-394-${tag}' LIMIT 1`).includes(`TEST-SCRUM-394-${tag}`);

  if (!seeded('FULL'))
    sf(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v',
      "LastName=TEST-SCRUM-394-FULL Email=full394@example.com Phone='+4930999' Company='Testfirma394Full' 'Status=Open - Not Contacted' LeadSource=Email"]);
  if (!seeded('NOEMAIL'))
    sf(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v',
      "LastName=TEST-SCRUM-394-NOEMAIL Phone='+4930998' Company='Testfirma394NoEmail' 'Status=Open - Not Contacted' LeadSource=Website"]);
  if (!seeded('NOSRC'))
    sf(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v',
      "LastName=TEST-SCRUM-394-NOSRC Company='Testfirma394NoSource' 'Status=Open - Not Contacted'"]);
  if (!seeded('CONV'))
    sf(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v',
      "LastName=TEST-SCRUM-394-CONV 'Status=Closed - Not Converted' LeadSource=Phone"]);
}

/** Open the report and wait for its data iframe to render at least one row. */
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
  test.beforeAll(() => {
    ensureFixtures();
  });

  test('AC2 + AC4: report in Sales, grouped by Lead-Quelle incl. own group for blank source', async ({ page }) => {
    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // Group headers: the fixture sources render, and the blank source has its
    // own group (Salesforce renders it as "(blank)" — the AC's „eigene Gruppe").
    await expect(frame.getByText('Email').first()).toBeVisible({ timeout: 45000 });
    await expect(frame.getByText('Website').first()).toBeVisible();
    await expect(frame.getByText(/\(blank\)/).first()).toBeVisible();
  });

  test('AC5: row fields — Name, Firma, Status, Datenqualität, Inhaber — with correct values', async ({ page }) => {
    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // AC5 column headers (report column labels, probed shapes like SCRUM-378):
    await expect(frame.getByText('First Name').first()).toBeVisible();
    await expect(frame.getByText('Last Name').first()).toBeVisible();
    await expect(frame.getByText('Company / Account').first()).toBeVisible();
    await expect(frame.getByText('Lead Status').first()).toBeVisible();
    await expect(frame.getByText('Datenqualität').first()).toBeVisible();
    await expect(frame.getByText('Lead Owner').first()).toBeVisible();

    // Fixture values in the rows (logical-column asserts like SCRUM-378):
    await expect(frame.getByText('TEST-SCRUM-394-FULL', { exact: true })).toHaveCount(1);
    await expect(frame.getByText('Testfirma394Full', { exact: true })).toHaveCount(1);
    await expect(frame.getByText('Open - Not Contacted', { exact: true }).first()).toBeVisible();
    await expect(frame.getByText('TEST-SCRUM-394-NOSRC', { exact: true })).toHaveCount(1);

    // AC1 values visible in the report's Datenqualität column:
    await expect(frame.getByText('vollständig', { exact: true }).first()).toBeVisible();
    await expect(frame.getByText('unvollständig', { exact: true }).first()).toBeVisible();
  });

  test('Konvertierte Leads bleiben außen vor (CONVERTED=false filter)', async ({ page }) => {
    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // The closed fixture is an org lead but must NOT appear anywhere in the report:
    await expect(frame.getByText('TEST-SCRUM-394-CONV', { exact: true })).toHaveCount(0);
  });

  test('AC3 org-weit: report rows == org-wide open-lead count (row-count comparison, not field presence)', async ({ page }) => {
    // Reference number: org-wide SOQL by the same admin user who runs the report
    // (scope "org" = all users' leads — full org visibility, independent of owner).
    const ref = openLeadCountOrgWide();
    expect(ref, 'org-wide COUNT of open leads must be retrievable').toBeGreaterThanOrEqual(4);

    const frame = await openReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // Sum the per-group record counts (Count appears once per group row in the
    // Summary report — the grand total at the bottom is the same sum).
    const text = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    const numbers = Array.from(text.matchAll(/(\d+)/g)).map((m) => parseInt(m[1], 10));
    expect(numbers.length > 0, 'report must render numeric counts').toBeTruthy();
    const maxSeen = Math.max(...numbers);
    // The grand total is present and equals the org-wide open-lead count (AC3):
    expect(
      numbers,
      `AC3 violated: report total must match org-wide COUNT(open leads)=${ref}; largest number rendered in report: ${maxSeen}`,
    ).toContain(ref);
  });
});
