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
  await dismissGuidance(page);
  const tab = page.getByRole('tab', { name: 'Details' }).first();
  const sel = await tab.getAttribute('aria-selected');
  if (sel !== 'true') await tab.click();
  await page.getByRole('button', { name: 'Edit Stage', exact: true }).first().waitFor({ state: 'visible', timeout: 30000 });
}

/** Stage ueber den Inline-Editor in der View aendern. */
async function changeStageInline(page: Page, optionName: string) {
  // "Edit Stage" oeffnet die Record-Edit-Form (Snapshot AC4/AC5: combobox
  // "Stage" + button "Save"). Gleiche Combobox-Mechanik wie im New-Form, das
  // AC1/AC2 schon gruen verifiziert haben - nicht die Path-Pipeline-Optionen.
  const edit = page.getByRole('button', { name: 'Edit Stage', exact: true }).first();
  await edit.waitFor({ state: 'visible', timeout: 15000 });
  await edit.click();
  const combo = page.getByRole('combobox', { name: 'Stage', exact: false }).first();
  await combo.waitFor({ state: 'visible', timeout: 20000 });
  await combo.click({ timeout: 15000 });
  await clickOption(page, optionName);
  await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 10000 });
  await expect(page).toHaveURL(/\/view$/, { timeout: 30000 });
}

/** Lightning-Dropdown-Option klicken: Animation kann die Option kurz
 *  unstabil machen; force=click mit Retry-Loop statt Endlos-Wait auf
 *  "stable". */
async function clickOption(page: Page, optionName: string) {
  const opt = page.getByRole('option', { name: optionName, exact: true }).first();
  await opt.waitFor({ state: 'visible', timeout: 10000 });
  await retry(5, 250, () => opt.click({ force: true }));
}

/** In-app Guidance-Dialog (Snapshot AC1: "Try the new Salesforce Setup",
 *  [active]) stiehlt alle Eingaben, wenn er erscheint - zugekle. */
async function dismissGuidance(page: Page) {
  const dlg = page.getByRole('dialog', { name: /Try the new Salesforce Setup/i });
  if (await dlg.count()) {
    await dlg.getByRole('button').first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

async function retry(n: number, delayMs: number, fn: () => Promise<void>) {
  let lastErr: unknown;
  for (let i = 0; i < n; i++) {
    try {
      await fn();
      return;
    } catch (e) {
      lastErr = e;
      await pageWait(delayMs);
    }
  }
  throw lastErr;
}

function pageWait(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

test.describe('[SCRUM-381] Verlustgrund bei Opportunities (UI)', () => {
  test.describe.configure({ timeout: 120000 });
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
    await dismissGuidance(page);
    // Name + Close Date (Standard-OVF) + Stage = Closed Lost. Allein der
    // Verlustgrund fehlt: Save muss an der ValRule mit ihrer
    // German-Message scheitern.
    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(TAG + '-AC1');
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await page.getByRole('combobox', { name: 'Stage', exact: false }).first().click({ timeout: 10000 });
    await clickOption(page, 'Closed Lost');

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
    await dismissGuidance(page);

    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(TAG + '-AC2');
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await page.getByRole('combobox', { name: 'Stage', exact: false }).first().click({ timeout: 10000 });
    await clickOption(page, 'Closed Lost');
    await page.getByRole('combobox', { name: 'Verlustgrund', exact: false }).first().click({ timeout: 10000 });
    await clickOption(page, 'Zu teuer');

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 10000 });

    // Erfolg: Navigation zum neuen Record. Lightning nutzt Short-URLs
    // (/lightning/r/006…/view) - Object-Kuerzel im Pfad ist nicht garantiert.
    await page.waitForURL(/lightning\/r\/006[a-zA-Z0-9]+\/view/, { timeout: 30000 });
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
    await expect(page.getByText('Stage').first()).toBeVisible();
    await expect(page.getByText('Verlustgrund').first()).toBeVisible();
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
