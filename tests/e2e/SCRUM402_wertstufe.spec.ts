import { test, expect, type Page } from '@playwright/test';
import { execFileSync, type ExecFileSyncOptionsWithStringEncoding } from 'child_process';
import * as processRef from 'process';

/**
 * SCRUM-402 — Wertstufe für offene Verkaufschance (Playwright E2E)
 *
 * Testet die UI-Schicht einer Live-Salesforce-Organisation. Die Formellogik
 * selbst (4 Stufen, beide Grenzen inklusiv, null → Unbekannt, Update-Follow)
 * ist im Apex-Test SCRUM402WertstufeTest (8/8) abgedeckt; dieses Spec bringt
 * den Beweis auf die Ebene, die der Nutzer sieht: Record-Page und List View.
 *
 * AC1 → Wertstufe auf der Record-Page (Details-Tab), read-only:
 *    - TC AC1-UI-Hoch      : Amount 100.000  → «Hoch»
 *    - TC AC1-UI-Unbekannt : Amount leer     → «Unbekannt»
 *                            (UI-Regressionsschutz gegen formulaTreatBlanksAs=BlankAsZero)
 * AC2 → List View «Hochwertige Chancen» als PS-tragender Nutzer (DO-D O1):
 *    - TC AC2              : GENAU 8 Zeilen, 6 Spalten, alle «Hoch»,
 *                            geschlossene Chancen (10 mit Stage Closed) nicht dabei
 * AC3 → Berechtigung:
 *    - TC AC3              : FLS-Negativfall via Apex System.runAs() (frisch
 *                            ausgeführt) + PS-Zuweisung des Session-Nutzers (CLI-Read-back)
 *
 * Session: Test-Org-CLI-User (devops-agent) — trägt das Permission Set
 * SCRUM401_Value_Tier_Read; der Vor-Bedingungs-Check steht in beforeAll.
 */

// sf subprocess without shell: Playwright workers set FORCE_COLOR, which makes the
// CLI write ANSI escapes into --json output even with NO_COLOR set. Disable color.
const sfExecOpts: ExecFileSyncOptionsWithStringEncoding = {
  encoding: 'utf8',
  stdio: ['pipe', 'pipe', 'pipe'],
  maxBuffer: 16 * 1024 * 1024,
  env: { ...processRef.env, FORCE_COLOR: '0', NO_COLOR: '1' },
};
function sfRaw(args: string[]): string {
  try {
    return execFileSync('sf', args, sfExecOpts);
  } catch {
    return '';
  }
}

/** SOQL count via totalSize — no --compact-false (it removes totalSize, CLI 2.139.x). */
function sfCount(query: string): number {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', query, '--json']);
  const m = out.match(/"totalSize"\s*:\s*(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}

function sfQueryNames(query: string): string[] {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', query, '--json']);
  try {
    const d = JSON.parse(out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
    const recs = (d.result?.records ?? d.records ?? []) as { Name?: string }[];
    return recs.map((r) => r.Name ?? '');
  } catch {
    return [];
  }
}

function sfQueryFirst(query: string): { Id?: string } {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', query, '--json']);
  try {
    const d = JSON.parse(out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
    const recs = (d.result?.records ?? d.records ?? []) as { Id?: string }[];
    return recs[0] ?? {};
  } catch {
    return {};
  }
}

/** German currency: "120.000,00 €" → 120000.00 */
function parseDeCurrency(text: string): number {
  const t = text.replace(/[€\s]/g, '');
  if (!t) return NaN;
  return parseFloat(t.replace(/\./g, '').replace(',', '.'));
}

/**
 * Open a Lightning list view by developer name and return the rendered data.
 * Verified path (see SCRUM-370 house shape): /lightning/o/<Object>/list?filterName=<DevName>.
 * The table lives in a shadow root — Playwright's CSS locator pierces it, but
 * document.querySelectorAll from page.evaluate does not; therefore rows/cells
 * are read via Playwright locators, not evaluate.
 */
async function openOpportunityList(page: Page): Promise<{
  header: string;
  headers: string[];
  rows: string[][];
}> {
  await page.goto('/lightning/o/Opportunity/list?filterName=Hochwertige_Chancen', {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
  await page.locator('text=items').first().waitFor({ state: 'visible', timeout: 30000 });

  const header = (
    await page.getByText(/\d+ items •/).first().innerText().catch(() => '')
  ).trim();

  const headers = (await page.locator('table[role="grid"] thead th, table[role="grid"] tr:has(th) th').allInnerTexts())
    .map((h) => h.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim());

  const rowLoc = page.locator('table[role="grid"] tbody tr[role="row"]');
  const n = await rowLoc.count();
  const rows: string[][] = [];
  for (let i = 0; i < n; i++) {
    rows.push((await rowLoc.nth(i).locator('td').allInnerTexts()).map((c) => c.trim()));
  }
  return { header, headers, rows };
}

/** Record page → Details tab → value rendered next to a field label. Verified 2026-09-08. */
async function openRecordDetails(page: Page, id: string) {
  await page.goto(`/lightning/r/Opportunity/${id}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
  const details = page.getByRole('tab', { name: 'Details' });
  await details.waitFor({ state: 'visible', timeout: 30000 });
  await details.click();
  await page.waitForTimeout(2500);
}

/**
 * Read the rendered value of a form field by its label.
 * Lightning renders label-then-value as adjacent lines; return the line after
 * the label — fails loudly (returns null caller asserts) if the label never rendered.
 */
async function readFieldValueAfterLabel(page: Page, label: string): Promise<string | null> {
  return page.evaluate((lbl) => {
    const t = document.body.innerText || '';
    const i = t.indexOf(lbl);
    if (i < 0) return null;
    const rest = t.slice(i + lbl.length);
    // first non-empty line after the label is the value
    for (const line of rest.split('\n')) {
      const v = line.trim();
      if (v) return v;
    }
    return null;
  }, label);
}

test.describe('[SCRUM-402] Wertstufe für offene Verkaufs-Chance', () => {
  let hochId = '';
  let unbekanntId = '';
  // Ground truth from the org (read-back, not tool output)
  let openHochNames: string[] = [];
  let closedHochNames: string[] = [];
  let closedHochCount = 0;

  test.beforeAll(() => {
    // Precondition 1 — session user owns the PS (positive side of AC3).
    const orgOut = sfRaw(['org', 'display', '--json']);
    let sessionUser = '';
    try {
      sessionUser = JSON.parse(orgOut.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')).result.username;
    } catch {
      sessionUser = '';
    }
    const assigned = sfCount(
      `SELECT Id FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM401_Value_Tier_Read' AND Assignee.Username='${sessionUser}'`
    );
    expect(assigned, `Session user ${sessionUser} must carry SCRUM401_Value_Tier_Read (AC3 positive side)`).toBe(1);

    // Precondition 2 — the 8 «Hoch» records actually exist in the org.
    openHochNames = sfQueryNames(
      `SELECT Name FROM Opportunity WHERE StageName NOT IN ('Closed Won','Closed Lost') AND Value_Tier__c='Hoch'`
    );
    expect(openHochNames.length, `Org must contain exactly 8 open «Hoch» opportunities, found ${openHochNames.length}`).toBe(8);

    // Precondition 3 — closed «Hoch» records that must NOT appear (10, measured).
    closedHochCount = sfCount(
      `SELECT Id FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost') AND Value_Tier__c='Hoch'`
    );
    closedHochNames = sfQueryNames(
      `SELECT Name FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost') AND Value_Tier__c='Hoch'`
    );

    // UI reference records for AC1: one 100.000 (boundary → Hoch), one with empty Amount (→ Unbekannt).
    hochId = (sfQueryFirst(`SELECT Id FROM Opportunity WHERE Name='Pyramid Emergency Generators' LIMIT 1`)?.Id as string) ?? '';
    unbekanntId = (sfQueryFirst(`SELECT Id FROM Opportunity WHERE Name='TEST-DBG' LIMIT 1`)?.Id as string) ?? '';
    expect(hochId, 'UI reference record Pyramid Emergency Generators (Amount 100.000) not found').toBeTruthy();
    expect(unbekanntId, 'UI reference record TEST-DBG (Amount null) not found').toBeTruthy();
  });

  test('AC1-UI: Amount 100.000 → value is «Hoch» on record page', async ({ page }) => {
    await openRecordDetails(page, hochId);
    const value = await readFieldValueAfterLabel(page, 'Wertstufe');
    expect(value, 'Wertstufe is not rendered on the Details tab — check layout deployment').toBe('Hoch');

    // Read-only in view mode: no edit control on the field (it is computed).
    await expect(page.getByRole('button', { name: 'Edit Wertstufe' })).toHaveCount(0);
  });

  test('AC1-UI: Amount empty → «Unbekannt» (regression guard against formulaTreatBlanksAs=BlankAsZero)', async ({ page }) => {
    await openRecordDetails(page, unbekanntId);
    const value = await readFieldValueAfterLabel(page, 'Wertstufe');
    expect(
      value,
      'TEST-DBG (Amount null) must display «Unbekannt»; with BlankAsZero this would be «Gering»'
    ).toBe('Unbekannt');
  });

  test('AC2: List view «Hochwertige Chancen» shows exactly 8 lines, 6 columns, all «Hoch», no closed', async ({ page }) => {
    const { header, headers: colHeaders, rows } = await openOpportunityList(page);

    // 1) Header announces the filtered count: «8 items …, Value by Stage, Wertstufe»
    expect(header, `List header does not name the view/filter: «${header}»`).toMatch(/^8 items/i);
    expect(header, 'Header must name the active filter (Stage + Wertstufe)').toMatch(/filtered/i);

    // 2) All six required columns exist (Name, Account, Amount, Close Date, Wertstufe, Owner)
    for (const col of ['Opportunity Name', 'Account Name', 'Amount', 'Close Date', 'Wertstufe', 'Opportunity Owner Alias']) {
      expect(
        colHeaders.some((h) => h.includes(col)),
        `Column «${col}» not rendered — header cells: ${colHeaders.join(' | ')}`
      ).toBe(true);
    }

    // 3) Exactly 8 lines (DO-D O1: «exactly 8» as PS-holding user in the UI)
    expect(rows.length, `List should show exactly 8 rows, showed ${rows.length}`).toBe(8);

    // 4) Every row: Wertstufe=«Hoch» (col 6), Amount ≥ 100.000 (col 4), Name present (col 2)
    const listedNames: string[] = [];
    for (const [i, cells] of rows.entries()) {
      expect(cells.length, `Row ${i + 1} has ${cells.length} cells, expected 8 (row number + 6 data + actions)`).toBe(8);
      const name = cells[2];
      const amount = parseDeCurrency(cells[4]);
      const wertstufe = cells[6];
      expect(name, `Row ${i + 1} has empty Name`).toBeTruthy();
      expect(amount, `Row ${i + 1}: Amount «${cells[4]}» not ≥ 100.000 (would violate Hoch-tier)`).toBeGreaterThanOrEqual(100000);
      expect(wertstufe, `Row ${i + 1}: Wertstufe «${wertstufe}» must be «Hoch»`).toBe('Hoch');
      listedNames.push(name);
    }

    // 5) Line set matches org ground truth line by line (not just line count)
    expect(
      listedNames.slice().sort(),
      'Listed names must equal the 8 open «Hoch» opportunities in the org'
    ).toEqual(openHochNames.slice().sort());

    // 6) Closed «Hoch» records must be excluded — by line count (8 vs 10 present) as well as by name
    for (const closedName of closedHochNames) {
      expect(
        listedNames.includes(closedName),
        `Closed opportunity «${closedName}» must not appear in the view`
      ).toBe(false);
    }
    expect(closedHochCount, 'Sanity: org has 10 closed «Hoch» records that are being excluded').toBe(10);
  });

  test('AC3: FLS — without PS does not see the field, with PS read-only (Apex runAs, fresh)', async () => {
    // Fresh Apex execution of the FLS test — runAs user WITHOUT the PS must
    // see isAccessible=false on Value_Tier__c, with the PS readable=true /
    // editable=false. Executed in the test, not merely cited.
    const out = sfRaw(['apex', 'run', 'test', '-n', 'SCRUM402WertstufeFlsTest', '-o', 'Test-Org', '--synchronous', '--json']);
    const m = out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '').indexOf('{');
    expect(m, `sf apex run test returned no JSON: ${out.slice(0, 300)}`).toBeGreaterThanOrEqual(0);
    const d = JSON.parse(out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '').slice(m));
    const summary = d.result?.summary ?? d.summary;
    expect(summary?.outcome, `FLS apex test run failed: ${JSON.stringify(summary)}`).toBe('Passed');
    const methods = (d.result?.tests ?? d.tests ?? []) as { Name?: string; MethodName?: string; Outcome?: string }[];
    const fls = methods.find(
      (t) => ((t.FullName as string) ?? '').includes('wertstufe_invisibleWithoutPS') || (t.MethodName ?? '').includes('wertstufe_invisibleWithoutPS')
    );
    expect(fls, 'FLS test method wertstufe_invisibleWithoutPS_readableOnlyWithPS not found in result set').toBeTruthy();
    expect(fls!.Outcome, `FLS test method failed: ${JSON.stringify(fls)}`).toBe('Pass');
  });
});
