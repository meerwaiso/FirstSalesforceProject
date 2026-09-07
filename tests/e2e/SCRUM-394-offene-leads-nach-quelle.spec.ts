import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';

const REPORT_ID = '00OWU00000QEIUL2A5';
// TC7 seed-helper path, relative to the repo root (Playwright cwd = repo root, testDir = ./tests/e2e).
const Tc7SeedApexPath = 'tests/e2e/scratch/SCRUM394_Tc7SeedConvLead.apex';

function sfRaw(args: string[]): string {
  try {
    return execSync(`sf ${args.join(' ')} 2>/dev/null`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 16 * 1024 * 1024,
    });
  } catch { return ''; }
}

// BUG-D-2 (tester 16450, repro 10/10): `--compact false` STRIPS `totalSize` from the CLI JSON
// output, so the count could never be parsed. SF CLI default output keeps totalSize -> no flag.
function sfCount(q: string): number {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', q, '--json']);
  const m = out.match(/"totalSize"\s*:\s*(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}

// BUG-C-Fix: LeadSource picklist value is "Web" (not "Website"). Fixtures are idempotent.
// The CONV fixture is a REAL converted Lead (IsConverted=true) — see TC7 seed-helper below.
type FixtureSpec = { tag: string; values: string };
const FIXTURES: FixtureSpec[] = [
  { tag: 'FULL',   values: "LastName=TEST-SCRUM-394-FULL Email=full394@example.com Phone='+49 30 90182039' Company='Testfirma394Full' 'Status=Open - Not Contacted' LeadSource=Email" },
  { tag: 'MOBILE', values: "LastName=TEST-SCRUM-394-MOBILE MobilePhone='+49 151 0987654' Company='Testfirma394Mobile' 'Status=Open - Not Contacted' LeadSource=Web" },
  { tag: 'NOSRC',  values: "LastName=TEST-SCRUM-394-NOSRC Company='Testfirma394NoSource' 'Status=Open - Not Contacted'" },
  { tag: 'CONV',   values: "LastName=TEST-SCRUM-394-CONV Email=conv394@example.com Phone='+49 30 90182040' Company='Testfirma394Converted' LeadSource=Email 'Status=Open - Not Contacted'" },
];

function seedFixture(f: FixtureSpec) {
  if (sfCount(`SELECT Id FROM Lead WHERE LastName='TEST-SCRUM-394-${f.tag}' LIMIT 1`) > 0) return;
  const out = sfRaw(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v', f.values, '--json']);
  const m = out.match(/"id"\s*:\s*"(00Q[A-Za-z0-9]{12,})"/);  // Lead prefix 00Q
  expect(m, `seeding fixture ${f.tag} must return a Lead id; CLI output:\n${out.slice(0, 500)}`).toBeTruthy();
}

// TC7 (design-doc c0a83dc / SCRUM-386 house shape): a converted Lead is NOT seedable via DML (IsConverted
// updateable=false, ConvertedAccountId only settable through convertLead). We seed the CONV fixture as an
// OPEN lead above, then flip it to REALLY converted via Database.convertLead in anonymous Apex. The apex
// block verifies IsConverted=true + ConvertedAccountId!=null on read-back before returning.
function convertConvFixture() {
  const out = execSync(`sf apex run -o Test-Org -f ${Tc7SeedApexPath} --json 2>/dev/null`, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  expect(out, `TC7 convertLead apex must run; output:\n${out.slice(0, 800)}`).toMatch(/"compiled"\s*:\s*true/);
  expect(out, `TC7 convertLead apex must not throw; output:\n${out.slice(0, 800)}`).not.toMatch(/Exception/);
}

function ensureFixtures() {
  for (const f of FIXTURES) seedFixture(f);
  convertConvFixture();
}

async function openReportFrame(page: import('@playwright/test').Page) {
  // House-shape frontdoor setup is handled by the global Playwright setup file; here we go straight to the
  // report by REPORT_ID (no folder assert — tester verifies Sales-folder via UI-API, 16450).
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

// TC10 (design-doc c0a83dc, LocaleSidKey=de_DE on the E2E identity): standard report column headers render in
// the USER locale, not the report language. The 5 standard columns (FIRST_NAME, LAST_NAME, COMPANY, STATUS,
// OWNER) are therefore locale-fragile and are NOT asserted by display text. We assert:
//   (a) the one locale-INDEPENDENT custom column we added, plus its value ("Datenqualität" label, German-only label,
//       and the "vollständig"/"unvollständig" values — formula is German),
//   (b) the number of data columns (6 for this report: 5 standard + 1 custom) via the header row,
//   (c) the fixture values which render identically in every locale.
const HEADER_ROWS = 'thead tr';       // report header row

test.describe('[SCRUM-394] Offene Leads nach Quelle + Datenqualität', () => {
  test.beforeAll(() => { ensureFixtures(); });

  test('AC2 + AC4: report renders grouped by Lead-Quelle incl. its own group for blank source', async ({ page }) => {
    const frame = await openReportFrame(page);
    await frame.locator(HEADER_ROWS).first().waitFor({ timeout: 45000 });

    // BUG-C-3 (16450): the "Email"/"Web" group rows are rowheaders of the kind "Drill Down. <group>" —
    // a plain getByText locator does not surface their content. The whole report frame text must carry
    // both group labels (regardless of how it is rendered: <th>, <td>, <b>, …).
    const frameText = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    expect(frameText, 'group "Email" must appear in the report frame').toMatch(/\bEmail\b/);
    expect(frameText, 'group "Web" must appear in the report frame').toMatch(/\bWeb\b/);
    // Blank-Gruppe renders either as "-" or "(blank)" (Salesforce varies by UI version; Architect 16415).
    const blankCells = frame.locator('td').filter({ hasText: /^-\s*$|^(blank)$/i });
    expect(await blankCells.count(), 'blank group must render as "-" or "(blank)"').toBeGreaterThan(0);
  });

  test('AC5 (BUG-B): detail rows render — Name, Firma, Status, Datenqualität, Inhaber', async ({ page }) => {
    // BUG-B-Fix: report now has showDetails=true (Architect 16415, commit abd64f5).
    const frame = await openReportFrame(page);
    await frame.locator(HEADER_ROWS).first().waitFor({ timeout: 45000 });

    // TC10 (c0a83dc): E2E identity has LocaleSidKey=de_DE; standard headers render in user locale. We assert
    // only on locale-ROBUST anchors: (a) the custom column header "Datenqualität" (German literal in the formula,
    //   identical in every locale), (b) the 6-column row shape, (c) the fixture values (ASCII, locale-invariant).
    await expect(frame.locator('th, td').filter({ hasText: /^Datenqualität$/ }).first())
      .toBeVisible({ timeout: 45000 });

    const rowText = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    expect(rowText, 'FULL fixture last-name must be in the report').toContain('TEST-SCRUM-394-FULL');
    expect(rowText, 'MOBILE fixture last-name must be in the report').toContain('TEST-SCRUM-394-MOBILE');
    expect(rowText, 'NOSRC fixture last-name must be in the report').toContain('TEST-SCRUM-394-NOSRC');

    // 6 data columns (5 standard + 1 custom): FIRST_NAME, LAST_NAME, COMPANY, STATUS, Datenqualität, OWNER
    const headerCells = await frame.locator(HEADER_ROWS).first().locator('th, td').count();
    expect(
      headerCells,
      `AC5 column count: expected 6; got ${headerCells}`,
    ).toBe(6);

    // AC1-Werte in der "Datenqualität"-Spalte (formula values are German; render identically in de/en user locales):
    //   FULL (Email+Phone+Company)  -> "vollständig"
    //   MOBILE (MobilePhone only)   -> "vollständig"  (PO 2026-09-06: Phone OR MobilePhone)
    //   NOSRC (kein Email)          -> "unvollständig"
    await expect(frame.locator('td').filter({ hasText: /^vollständig$/ }).first()).toBeVisible();
    await expect(frame.locator('td').filter({ hasText: /^unvollständig$/ }).first()).toBeVisible();
  });

  test('AC3 (BUG-D): report total == org-wide open-lead count (live SOQL, no hard-coded 62)', async ({ page }) => {
    // BUG-D-Fix: live SOQL reference; CLI default output keeps totalSize (BUG-D-2: drop --compact false).
    const ref = sfCount('SELECT Id FROM Lead WHERE IsConverted=false');
    expect(
      ref,
      `org-wide SOQL of open leads must be retrievable (got ${ref}; re-read tester 16450 BUG-D-2 if this is -1)`,
    ).toBeGreaterThanOrEqual(4);

    const frame = await openReportFrame(page);
    await frame.locator(HEADER_ROWS).first().waitFor({ timeout: 45000 });

    const text = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    const numbers = Array.from(text.matchAll(/(\d+)/g)).map((m) => parseInt(m[1], 10));
    expect(numbers.length > 0, 'report must render numeric counts').toBeTruthy();
    const maxSeen = Math.max(...numbers);
    expect(
      numbers,
      `AC3 violated: report must include the org-wide open-lead total (${ref}); largest rendered number: ${maxSeen}`,
    ).toContain(ref);
  });

  test('TC7 (design-doc c0a83dc): a REAL converted Lead is excluded from the report', async ({ page }) => {
    // beforeAll seeded a real converted Lead (TEST-SCRUM-394-CONV, IsConverted=true) via Database.convertLead —
    // DML/API create of a converted Lead is impossible in this org (IsConverted updateable=false; probe in
    // apex seed-helper). The report's CONVERTED=false filter + <scope>org</scope> must hide it.
    const notYetConverted = sfCount(`SELECT Id FROM Lead WHERE LastName='TEST-SCRUM-394-CONV' AND IsConverted=false`);
    expect(
      notYetConverted,
      "TC7 precondition: 'TEST-SCRUM-394-CONV' must actually be converted (IsConverted=true), not just Status-Closed",
    ).toBe(0);

    const frame = await openReportFrame(page);
    await frame.locator(HEADER_ROWS).first().waitFor({ timeout: 45000 });
    const text = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    expect(
      text,
      "TC7: the converted lead 'TEST-SCRUM-394-CONV' must NOT appear in the report (CONVERTED=false filter)",
    ).not.toContain('TEST-SCRUM-394-CONV');
  });
});
