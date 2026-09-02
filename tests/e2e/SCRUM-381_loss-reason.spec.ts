import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-381] Verlustgrund bei Opportunities - UI-E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json); nie
 * networkidle auf Lightning. Locators durchdringen die icres-* Shadow-DOM
 * ueber den Accessibility-Baum:
 *   - New-Form: textbox "Opportunity Name", combobox "Stage" (role=option),
 *     combobox "Verlustgrund" - Pflichtfelder tragen ein fuehrendes "*"
 *     im Label => getByLabel mit exact:false.
 *   - Record-Seite: Details-Tab; Inline-Editor "Edit Stage"; View-Text
 *     "Stage / <Wert> / Edit Stage".
 *
 * AC7 (FLS-Negativ) ist serverseitig bewiesen durch den Apex-Test
 * SCRUM381LostReasonTest.test_FLS_Negativ_OhnePS_Ungreifbar (System.runAs
 * gegen echtes Org-Verhalten; zweite UI-Session nicht moeglich: beide
 * Lizenzen belegt). Close Date wird gesetzt, wo Records persistieren
 * muessen (Standard-OVF verlangt sie fuer Closed Won/Lost).
 */

const TAG = 'TEST-SCRUM-381-UI';
const createdIds: string[] = [];

// ── SF-CLI Helpers (Muster der 370er-Spec) ────────────────────────────────

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function createOpp(fields: string): string {
  const out = execSync(
    `sf data create record -s Opportunity -v "${fields}" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  const doc = shellJson(out);
  const id = doc?.id ?? doc?.result?.id;
  if (!id) throw new Error(`Opportunity-Create lieferte keine Id: ${out.slice(0, 300)}`);
  const idStr = String(id);
  createdIds.push(idStr);
  return idStr;
}

function deleteOpp(id: string): void {
  execSync(
    `sf data delete record -s Opportunity -i ${id} --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'] },
  );
}

/** Details-Tab oeffnen, wo die Classic-Layout-Felder (Stage, Verlustgrund) rendern. */
async function openDetails(page: Page, path: string) {
  await page.goto(path, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
  await page.getByRole('tab', { name: 'Details' }).first().waitFor({ state: 'visible', timeout: 30000 });
  await page.getByRole('tab', { name: 'Details' }).first().click();
  await page.getByLabel('Stage', { exact: false }).first().waitFor({ state: 'visible', timeout: 30000 });
}

/** Stage ueber den Inline-Editor in der View aendern. */
async function changeStageInline(page: Page, optionName: string) {
  const edit = page.getByRole('button', { name: 'Edit Stage', exact: true });
  await edit.first().waitFor({ state: 'visible', timeout: 15000 });
  await edit.first().click();
  const opt = page.getByRole('option', { name: optionName, exact: true }).first();
  await opt.waitFor({ state: 'visible', timeout: 10000 });
  await opt.click();
  await page.getByText(optionName, { exact: true }).first().waitFor({ state: 'visible', timeout: 15000 });
}

test.describe('[SCRUM-381] Verlustgrund bei Opportunities (UI)', () => {
  test.afterEach(() => {
    for (let i = createdIds.length - 1; i >= 0; i--) {
      try { deleteOpp(createdIds[i]); } catch { /* best effort */ }
    }
    createdIds.length = 0;
  });

  test('AC1: saving Closed Lost without a loss reason is rejected with the German hint', async ({ page }) => {
    await page.goto('/lightning/o/Opportunity/new', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
    await page.getByLabel('Opportunity Name', { exact: false }).first().waitFor({ state: 'visible', timeout: 30000 });

    // Name + Close Date (Standard-OVF) + Stage = Closed Lost. Allein der
    // Verlustgrund fehlt: Save muss an der ValRule mit ihrer
    // German-Message scheitern.
    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(TAG + '-AC1');
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await page.getByRole('combobox', { name: 'Stage', exact: false }).first().click({ timeout: 10000 });
    await page.getByRole('option', { name: 'Closed Lost', exact: true }).first().click({ timeout: 10000 });

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 10000 });

    // Immer noch auf dem New-Form ...
    await expect(page).toHaveURL(/lightning\/o\/Opportunity\/new/, { timeout: 20000 });
    // ... und die ValRule-Message ist sichtbar.
    await expect(page.getByText('verloren markieren').first()).toBeVisible({ timeout: 20000 });
  });

  test('AC2: saving Closed Lost with a loss reason persists both values', async ({ page }) => {
    await page.goto('/lightning/o/Opportunity/new', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
    await page.getByLabel('Opportunity Name', { exact: false }).first().waitFor({ state: 'visible', timeout: 30000 });

    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(TAG + '-AC2');
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await page.getByRole('combobox', { name: 'Stage', exact: false }).first().click({ timeout: 10000 });
    await page.getByRole('option', { name: 'Closed Lost', exact: true }).first().click({ timeout: 10000 });
    await page.getByRole('combobox', { name: 'Verlustgrund', exact: false }).first().click({ timeout: 10000 });
    await page.getByRole('option', { name: 'Zu teuer', exact: true }).first().click({ timeout: 10000 });

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 10000 });

    // Erfolg: Navigation zu neuem Record; beide Werte nach Reload pruefen.
    await page.waitForURL(/lightning\/r\/Opportunity\/006/, { timeout: 20000 });
    const m = page.url().match(/(006[a-zA-Z0-9]+)/);
    expect(m, 'did not navigate to a created record').toBeTruthy();
    createdIds.push(m![1]);

    await openDetails(page, `/lightning/r/Opportunity/${m![1]}/view`);
    await expect(page.getByText('Closed Lost').first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('Zu teuer', { exact: true }).first()).toBeVisible();
  });

  test('AC3: for other stages the loss reason stays optional', async ({ page }) => {
    const id = createOpp(`Name='${TAG}-AC3' StageName='Qualification' CloseDate=2027-01-01`);

    await openDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await expect(page.getByText('Qualification').first()).toBeVisible({ timeout: 15000 });
    // Kein Grund gesetzt: Record intakt, Feld leer, keine Block-Message.
    await expect(page.getByText('Verlustgrund').first()).toBeVisible();
    await expect(page.getByText('verloren markieren')).toHaveCount(0);
  });

  test('AC6: Verlustgrund is visible on the record, in the same block as Stage', async ({ page }) => {
    const id = createOpp(`Name='${TAG}-AC6' StageName='Negotiation' CloseDate=2027-02-01 Loss_Reason__c='KeinBudget'`);

    await openDetails(page, `/lightning/r/Opportunity/${id}/view`);

    // Beide Felder rendern, der gesetzte Wert ist sichtbar ...
    await expect(page.getByLabel('Stage', { exact: false }).first()).toBeVisible();
    await expect(page.getByLabel('Verlustgrund', { exact: false }).first()).toBeVisible();
    await expect(page.getByText('Kein Budget', { exact: true }).first()).toBeVisible();
    // ... und liegen im selben Block: im gerenderten Text folgt
    // "Verlustgrund" auf "Stage" ohne Abschnittsueberschrift dazwischen.
    const body = await page.locator('body').innerText();
    const iStage = body.indexOf('Stage');
    const iLoss = body.indexOf('Verlustgrund');
    expect(iStage, 'Stage not on record').toBeGreaterThan(-1);
    expect(iLoss, 'Verlustgrund not on record').toBeGreaterThan(iStage);
    expect(body.slice(iStage, iLoss), 'Section heading separates Stage from Verlustgrund')
      .not.toMatch(/Information|Angaben|Secti?on/i);
  });

  test('AC4: reopening a closed-lost opportunity clears the loss reason', async ({ page }) => {
    const id = createOpp(`Name='${TAG}-AC4' StageName='Closed Lost' Loss_Reason__c='ZuTeuer' CloseDate=2026-08-01`);

    // Ist-Zustand: View zeigt den Grund ...
    await openDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await expect(page.getByText('Zu teuer', { exact: true }).first()).toBeVisible({ timeout: 15000 });

    // ... nach Stage-Zuruckschalten auf einen offenen Stage ist er weg.
    await changeStageInline(page, 'Prospecting');

    // Reload: Auto-Clear ist persistiert.
    await openDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await expect(page.getByText('Prospecting', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('Zu teuer', { exact: true })).toHaveCount(0);
  });

  test('AC5: winning a closed-lost opportunity clears the loss reason', async ({ page }) => {
    const id = createOpp(`Name='${TAG}-AC5' StageName='Closed Lost' Loss_Reason__c='Wettbewerber' CloseDate=2026-08-01`);

    await openDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await expect(page.getByText('An einen Wettbewerber verloren').first()).toBeVisible({ timeout: 15000 });

    // Closed Won direkt; ValRule darf es nicht blocken (Stage-Gate greift
    // nur bei Closed Lost), Auto-Clear muss greifen.
    await changeStageInline(page, 'Closed Won');

    await openDetails(page, `/lightning/r/Opportunity/${id}/view`);
    await expect(page.getByText('Closed Won').first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('An einen Wettbewerber verloren')).toHaveCount(0);
  });
});
