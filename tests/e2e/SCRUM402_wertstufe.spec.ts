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

/** SOQL record Ids (lowercased) — the collision-free key to prove WHICH org records
 *  a list renders, independent of duplicate Name strings (org has 2 shared between
 *  the open-«Hoch» and closed-«Hoch» sets). */
function sfQueryIds(query: string): string[] {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', query, '--json']);
  try {
    const d = JSON.parse(out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
    const recs = (d.result?.records ?? d.records ?? []) as { Id?: string }[];
    return recs.map((r) => (r.Id ?? '').toLowerCase());
  } catch {
    return [];
  }
}

/** German currency: "120.000,00 €" → 120000.00 */
function parseDeCurrency(text: string): number {
  const t = text.replace(/[€\s]/g, '');
  if (!t) return NaN;
  return parseFloat(t.replace(/\./g, '').replace(',', '.'));
}

/** One rendered data row from the «Hochwertige Chancen» list (see column map below). */
interface OppRow {
  id: string;
  name: string;
  account: string;
  amount: string;
  date: string;
  wert: string;
  owner: string;
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
  rows: OppRow[];
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

  // Each row: the record Name is a <th rowheader> (the link to the record), NOT
  // a <td>. The 8 <td> columns are:
  //   td[0]=RowNumber  td[1]=Select  td[2]=Account  td[3]=Amount
  //   td[4]=CloseDate  td[5]=Wertstufe  td[6]=OwnerAlias  td[7]=Action
  // Reading the Name from a td index is wrong — it silently lands on a later column.
  const rowLoc = page.locator('table[role="grid"] tbody tr[role="row"]');
  const n = await rowLoc.count();
  const rows: OppRow[] = [];
  for (let i = 0; i < n; i++) {
    const tr = rowLoc.nth(i);
    const tds = tr.locator('td');
    const cell = async (x: number): Promise<string> => {
      const raw = await tds.nth(x).innerText().catch(() => '');
      // Lightning appends an inline affordance like "Edit <Col>" / "Locked <Col>"
      // after the value; the first token-run before it is the value itself.
      const first = raw.split('\n')[0] ?? raw;
      return first.replace(/\s+(Edit|Locked)\b.*$/, '').trim();
    };
    // The rowheader is a link to /lightning/r/<Id>/view — the row's record Id,
    // the only collision-free key for identifying which org record a row shows.
    const rhHref = (await tr.locator('[role="rowheader"] a').first().getAttribute('href').catch(() => '')) ?? '';
    const idMatch = rhHref.match(/\/lightning\/r\/([0-9a-zA-Z]{15,18})/);
    rows.push({
      id: idMatch ? idMatch[1] : '',
      name: (await tr.locator('[role="rowheader"]').first().innerText().catch(() => ''))
        .split('\n')[0]
        .replace(/\s+Edit\b.*$/, '')
        .trim(),
      account: await cell(2),
      amount: await cell(3),
      date: await cell(4),
      wert: await cell(5),
      owner: await cell(6),
    });
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
  // Ground truth from the org (read-back, not tool output) — records as Id, nicht Name:
  // die Test-Org hat 2 Opportunity-Namen, die sowohl offen-«Hoch» als auch
  // geschlossen-«Hoch» tragen ("United Oil Installations", "United Oil Refinery
  // Generators"). Nur die Id erlaubt einen eindeutigen Satz-Vergleich.
  let openHochIds: string[] = [];
  let closedHochIds: string[] = [];
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

    // Precondition 2 — the 8 «Hoch» records actually exist in the org (as Ids).
    openHochIds = sfQueryIds(
      `SELECT Id FROM Opportunity WHERE StageName NOT IN ('Closed Won','Closed Lost') AND Value_Tier__c='Hoch'`
    );
    expect(openHochIds.length, `Org must contain exactly 8 open «Hoch» opportunities, found ${openHochIds.length}`).toBe(8);

    // Precondition 3 — closed «Hoch» records that must NOT appear (10, measured, as Ids).
    closedHochCount = sfCount(
      `SELECT Id FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost') AND Value_Tier__c='Hoch'`
    );
    closedHochIds = sfQueryIds(
      `SELECT Id FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost') AND Value_Tier__c='Hoch'`
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

    // 4) Every row: all six required columns populated — Name (rowheader), Konto,
    //    Betrag ≥ 100.000, Abschlussdatum, Wertstufe = «Hoch», Inhaber.
    const listedIds: string[] = [];
    for (const [i, row] of rows.entries()) {
      const amount = parseDeCurrency(row.amount);
      expect(row.id, `Row ${i + 1} has no resolvable record Id (rowheader link missing)`).toMatch(/^[0-9a-zA-Z]{15,18}$/);
      expect(row.name, `Row ${i + 1} has empty Name`).toBeTruthy();
      expect(row.account, `Row ${i + 1} has empty Konto (Account)`).toBeTruthy();
      expect(Number.isFinite(amount), `Row ${i + 1}: Amount «${row.amount}» is not a number`).toBe(true);
      expect(amount, `Row ${i + 1}: Amount «${row.amount}» not ≥ 100.000 (a "Hoch" record must be)`).toBeGreaterThanOrEqual(100000);
      expect(row.date, `Row ${i + 1} has empty Abschlussdatum (Close Date)`).toBeTruthy();
      expect(row.wert, `Row ${i + 1}: Wertstufe «${row.wert}» must be «Hoch»`).toBe('Hoch');
      expect(row.owner, `Row ${i + 1} has empty Inhaber (Owner)`).toBeTruthy();
      listedIds.push(row.id.toLowerCase());
    }

    // 5) Set of rendered records == the 8 open «Hoch» records of the org. By ID, not
    //    by name — because "United Oil Installations" and "United Oil Refinery
    //    Generators" exist as a closed-Hoch record in addition to the open-Hoch
    //    record, and Name-based comparisons become ambiguous (and wrongly red).
    expect(
      listedIds.slice().sort(),
      'The records being rendered must correspond exactly to the 8 open «Hoch» opportunities from the org (per record ID)'
    ).toEqual(openHochIds.slice().sort());

    // 6) Closed «Hoch» records must be excluded — per record ID, unambiguous in any case
    for (const closedId of closedHochIds) {
      expect(
        listedIds.includes(closedId),
        `A closed record (${closedId}) must not be displayed (this is also covered by the set comparison in 5, but this makes individual violations visible)`
      ).toBe(false);
    }
    expect(closedHochCount, 'Sanity: the org has 10 closed «Hoch» records that will be excluded').toBe(10);
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
