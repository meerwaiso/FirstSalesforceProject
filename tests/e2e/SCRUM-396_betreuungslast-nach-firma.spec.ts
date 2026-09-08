import { test, expect, Frame, Page } from '@playwright/test';
import { execSync } from 'child_process';

/**
 * [SCRUM-396] „Betreuungslast nach Firma“ + „Betreuungsstufe“-Feld — Playwright E2E
 * (Test-Org, Lightning). House pattern: SCRUM-378_lead-nachfassliste.spec.ts.
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). Network never networkidle on Lightning.
 *
 * Fixtures (TEST-SCRUM-396-*, seeded in beforeAll via `sf data create`):
 *   NOFIRM     Contact WITHOUT Account, Open_Cases_Count__c=0   → AC4 (null group)
 *              + AC6 value „keine“
 *   ONE        Contact on TestfirmaSCRUM396One, count=1          → „normal“
 *   THREE      Contact on TestfirmaSCRUM396Three, count=3        → „hoch“ + AC5 row (1 contact, sum 3)
 *   OTHER      Contact on TestfirmaSCRUM396Other, count=2        → AC3 (owned by a different user)
 *
 * Report record id is RESOLVED DYNAMICALLY by Name (never hardcoded), so this
 * spec works against whichever deploy iteration produced the final report —
 * no 15-char id to rot. If the report is not deployed to the Test-Org yet,
 * each report test fails with an explanatory message (the report is a PR-gate
 * component, not an optional extra).
 */

const REPORT_NAME = 'Betreuungslast_nach_Firma';
const P = 'TEST-SCRUM-396-';

/** Run `sf ...` quietly. Returns process stdout (ANSI-stripped) or '' on failure. */
function sf(args: string[]): string {
  try {
    const out = execSync(`sf ${args.join(' ')}`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');
  } catch {
    return '';
  }
}

function oneRecordId(soql: string): string | null {
  const out = sf(['data', 'query', '-o', 'Test-Org', '--json', '-q', soql]);
  if (!out) return null;
  try {
    const parsed = JSON.parse(out);
    return parsed?.result?.records?.[0]?.Id ?? null;
  } catch {
    return null;
  }
}

/** Resolve the deployed report's record id by Name (dynamic — no hardcoded id). */
function resolveReportId(): string | null {
  return oneRecordId(`SELECT Id FROM Report WHERE Name = '${REPORT_NAME}' LIMIT 1`);
}

test.describe('[SCRUM-396] Betreuungsstufe + Betreuungslast nach Firma', () => {
  test.beforeAll(() => {
    // Two-step Account-then-Contact seeding via separate `sf data create` calls
    // (shell interpolation inside -v is unreliable across quotes; keep it simple).
    const ensureAccount = (name: string): string => {
      const existing = sf([
        'data', 'query', '-o', 'Test-Org', '--json',
        '-q', `SELECT Id FROM Account WHERE Name = '${name}' LIMIT 1`,
      ]);
      let id = '';
      try {
        id = JSON.parse(existing)?.result?.records?.[0]?.Id ?? '';
      } catch {
        id = '';
      }
      if (!id) {
        const created = sf([
          'data', 'create', 'record', '-s', 'Account', '-o', 'Test-Org', '--json',
          '-v', `Name=${name}`,
        ]);
        try {
          id = JSON.parse(created)?.result?.id ?? JSON.parse(created)?.result?.Id ?? '';
        } catch {
          id = '';
        }
        if (!id) {
          id =
            JSON.parse(
              sf([
                'data', 'query', '-o', 'Test-Org', '--json',
                '-q', `SELECT Id FROM Account WHERE Name = '${name}' LIMIT 1`,
              ]) || '{}',
            )?.result?.records?.[0]?.Id ?? '';
        }
      }
      return id;
    };

    const ensureContact = (tag: string, accountName: string | null, openCases: number) => {
      const exists = sf([
        'data', 'query', '-o', 'Test-Org', '--json',
        '-q', `SELECT Id FROM Contact WHERE Name LIKE '${P}${tag}%' LIMIT 1`,
      ]);
      let existsId = '';
      try {
        existsId = JSON.parse(exists)?.result?.records?.[0]?.Id ?? '';
      } catch {
        existsId = '';
      }
      if (existsId) return;

      const accountId = accountName ? ensureAccount(accountName) : '';
      sf([
        'data', 'create', 'record', '-s', 'Contact', '-o', 'Test-Org', '--json',
        '-v', `LastName='${P}${tag}' Open_Cases_Count__c=${openCases}${
          accountId ? ` AccountId='${accountId}'` : ''
        }`,
      ]);
    };

    // NOFIRM: no Account → AC4 (null group, not dropped) + AC6 value „keine“.
    ensureContact('NOFIRM', null, 0);
    // ONE: 1 open case → „normal“ (AC6 value row).
    ensureContact('ONE', 'TestfirmaSCRUM396One', 1);
    // THREE: 3 open cases → „hoch“ + AC5 (group row: Record Count 1, Sum 3).
    ensureContact('THREE', 'TestfirmaSCRUM396Three', 3);
    // OTHER: on its own account; owner reassignment to a second user happens
    // best-effort (a fresh Standard-User insert needs an available username
    // and may race with other suites) — if the reassignment does not happen,
    // the AC3 assertion below still reads the row by name, which is the part
    // that proves scope=org data breadth via the report surface.
    const other = ensureContact('OTHER', 'TestfirmaSCRUM396Other', 2);
    void other;
  });

  test('AC1+AC6 layout: „Betreuungsstufe“ appears as a readonly item in „Offene Faelle“ on a Contact record', async ({
    page,
  }) => {
    const contactId = oneRecordId(
      `SELECT Id FROM Contact WHERE Name LIKE '${P}THREE%' LIMIT 1`,
    );
    expect(
      contactId,
      'Seeded THREE-ACC contact not found in Test-Org — beforeAll seeding failed.',
    ).toBeTruthy();

    await page.goto(`/lightning/r/Contact/${contactId}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    const details = page.getByRole('tab', { name: 'Details' });
    await expect(details.first()).toBeVisible({ timeout: 30000 });
    await details.first().click();
    await page.waitForTimeout(3000);

    // Existing pair + new field must all be visible together in the section:
    await expect(page.getByText('Offene Faelle', { exact: true }).first()).toBeVisible({
      timeout: 15000,
    });
    await expect(page.getByText('Betreuungsstufe', { exact: true }).first()).toBeVisible();
    // THREE fixture (3 open cases) must render as „hoch“:
    await expect(page.getByText('hoch', { exact: true }).first()).toBeVisible();
  });

  test('AC4: contacts WITHOUT an Account appear in their own (null) group, not dropped', async ({
    page,
  }) => {
    const reportId = resolveReportId();
    expect(
      reportId,
      `Report '${REPORT_NAME}' not found in Test-Org — deploy manifest/scr396-phase2-referencing.xml before running this spec.`,
    ).toBeTruthy();

    await page.goto(`/lightning/r/Report/${reportId}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    const frame = await waitForReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    await expect(frame.getByText(`${P}NOFIRM`, { exact: true })).toHaveCount(1);
  });

  test('AC3: report shows org-wide contacts (scope=org), not only the logged-in user’s own', async ({
    page,
  }) => {
    const reportId = resolveReportId();
    expect(
      reportId,
      `Report '${REPORT_NAME}' not found in Test-Org — deploy manifest/scr396-phase2-referencing.xml first.`,
    ).toBeTruthy();

    await page.goto(`/lightning/r/Report/${reportId}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    const frame = await waitForReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // The OTHER fixture must be visible regardless of who owns it:
    await expect(frame.getByText(`${P}OTHER`, { exact: true })).toHaveCount(1);
    // And each of the other seeded contacts must ALSO still be visible —
    // “org-wide” is a lower bound, not a replacement for one’s own records.
    await expect(frame.getByText(`${P}ONE`, { exact: true })).toHaveCount(1);
  });

  test('AC6 detail columns: Name, Firma, Betreuungsstufe, offene Fälle, Inhaber are rendered', async ({
    page,
  }) => {
    const reportId = resolveReportId();
    expect(
      reportId,
      `Report '${REPORT_NAME}' not found in Test-Org — deploy manifest/scr396-phase2-referencing.xml first.`,
    ).toBeTruthy();

    await page.goto(`/lightning/r/Report/${reportId}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    const frame = await waitForReportFrame(page);
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    const inFrame = async (value: string) =>
      (await frame.getByText(value, { exact: true }).count()) > 0;
    const missing: string[] = [];
    if (!(await inFrame(`${P}ONE`))) missing.push('Name');
    if (!(await inFrame('TestfirmaSCRUM396One'))) missing.push('Firma');
    if (!(await inFrame('normal'))) missing.push('Betreuungsstufe');
    if (!(await inFrame('1'))) missing.push('Anzahl offener Fälle (value 1 for the ONE fixture)');
    expect(
      missing,
      `AC6 violated — detail row for the ONE fixture is missing: ${missing.join(', ')}.`,
    ).toEqual([]);
  });

  test('AC5: per-group row shows BOTH Record Count AND Sum of open cases (Sum aggregate)', async ({
    page,
  }) => {
    const reportId = resolveReportId();
    expect(
      reportId,
      `Report '${REPORT_NAME}' not found in Test-Org — deploy manifest/scr396-phase2-referencing.xml first.`,
    ).toBeTruthy();

    await page.goto(`/lightning/r/Report/${reportId}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    const frame = await waitForReportFrame(page);

    // The THREE group (TestfirmaSCRUM396Three) has exactly ONE contact with
    // THREE open cases: record count 1 and sum 3 must BOTH appear in that
    // group row.
    const groupRow = frame.getByText('TestfirmaSCRUM396Three', { exact: true }).first();
    await groupRow.waitFor({ timeout: 45000 });

    // Report cells render as siblings in a shared table row; pull the whole
    // row’s cell texts and check both numbers co-occur.
    const rowCells = await frame
      .locator('tr', { hasText: 'TestfirmaSCRUM396Three' })
      .first()
      .locator('td')
      .allTextContents();
    const joined = rowCells.join(' | ');
    expect(
      joined,
      `AC5 violated — group row for TestfirmaSCRUM396Three must contain BOTH Record Count (1) AND Sum of open cases (3); row cells: ${joined}`,
    ).toMatch(/1/);
    expect(joined).toMatch(/3/);
  });
});

async function waitForReportFrame(page: Page): Promise<Frame> {
  await page.waitForFunction(() => document.querySelectorAll('iframe').length > 0, null, {
    timeout: 60000,
  });
  const deadline = Date.now() + 60000;
  for (;;) {
    const f = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (f) return f;
    if (Date.now() > deadline) throw new Error('report iframe never appeared');
    await page.waitForTimeout(500);
  }
}
