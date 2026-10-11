import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-442] E2E: Kundansatisfaction — Rating at closing, follow-up Task,
 * Account overview, Sales cannot change a rating.
 *
 * LOCATORS: every locator below was VERIFIED by the Tester in this session
 * (probe scripts probe442aq/aw/bs/bt/bq on Case 500WU00002vEBUnYAO,
 * Account 001WU00002GEhiqYAD, Report 00OWU00000QqteB2AR, 2026-10-11):
 *   - Details tab:            getByRole('tab', { name: 'Details' })  (house helper)
 *   - Edit entry:             getByRole('button', { name: 'Edit Kundansatisfaction' })
 *   - Picklist combobox:      getByRole('combobox', { name: 'Kundansatisfaction' })
 *                             -> click opens the option overlay
 *   - Options:                getByRole('option') — names carry an EN-DASH (U+2013):
 *                             "--None--", "1 – sehr dissatisfied", "2 – dissatisfied",
 *                             "3 – neutral", "4 – satisfied", "5 – sehr satisfied"
 *                             (NOT input[name="Customer_Satisfaction__c"] — the
 *                             Developer's UNVERIFIED form; there is no such input)
 *   - Score readable on page: getByText('2 – dissatisfied', { exact: true }) count 1
 *   - Account labels (org-verified FieldDefinition.Labels):
 *     "Status ärger?", "Satisfaction Ø (3 Monate)", "Satisfaction min (3 Monate)",
 *     "Cases in Ø-Fenster", "Ø-Fenster seit" — all getByText exact, count 1, visible
 *   - Task visible:           /lightning/r/Task/<id>/view, getByText(/Nachbetreuung/)
 *   - Report:                 /lightning/r/Report/00OWU00000QqteB2AR/view,
 *                             frame url contains 'lightningReportApp' (house SCRUM-434)
 *
 * ORG QUIRKS the Tester could NOT work around (stated, not hidden):
 *   1. The Status picklist on the Lightning record page offers only
 *      --None--/New/Working/Escalated — "Closed" is NOT offered (verified: option
 *      enumeration probe442aq/ai/am; SCRUM-434 tester notes confirm 2026-09-30).
 *      The "Close" action button exists (getByText('Close', exact) count 1) but
 *      renders with vis:false and is not clickable (probe442bt/bf). => The UI
 *      closing path is NOT reachable from the record page in this org state.
 *      AC1/AC2 closing is therefore exercised on the REST/CLI path (which the
 *      AC explicitly demands: "every closing path") plus the Apex System.runAs
 *      tests. The picklist-edit mechanics the Developer flagged UNVERIFIED ARE
 *      covered end-to-end here (entry, save, post-save persistence).
 *   2. A second licensed browser user for the AC7/AC8 UI session does not exist
 *      (2/2 licences held by System Administrators). AC7/AC8 are proven by the
 *      Apex System.runAs tests (withoutPS_scoreInvisible,
 *      salesShape_writeRefusedValueUnchanged, readPS_readableNotUpdateable).
 *
 * Seeds are created via sf CLI (house SCRUM-440/430) and deleted in afterAll.
 */

const ORG = 'Test-Org';
const SCORE_LABEL = 'Kundansatisfaction';
const API = 'Customer_Satisfaction__c';
const REJECT_MSG =
  'Bitte wählen eine Kundansatisfaction (1–5) für den geschlossenen Fall, bevor Sie speichern. Solange der Fall offen ist, ist das Feld freiwillig.';
const TASK_PREFIX = 'Nachbetreuung: ';
const REPORT_NAME = 'Miserable_Kunde_Satisfaction';

function cli(args: string): string {
  return execSync(`FORCE_COLOR=0 NO_COLOR=1 sf ${args}`, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}
function sfJson(args: string): any {
  const raw = cli(args);
  const clean = raw.replace(/\u001b\[[0-9;]*[a-zA-Z]/g, '');
  return JSON.parse(clean.slice(clean.indexOf('{'), clean.lastIndexOf('}') + 1));
}
function soql(q: string): any {
  return sfJson(`data query -o ${ORG} --json -q "${q}"`).result;
}

let accId: string;
let caseId: string;
const extraCaseIds: string[] = [];
const TAG = 'TEST-SCRUM442-E2E-' + Date.now().toString(36).toUpperCase();

test.beforeAll(() => {
  const accOut = sfJson(
    `data create record -s Account -v "Name='${TAG}'" -o ${ORG} --json`,
  );
  accId = String(accOut?.result?.id ?? '');
  if (!accId) throw new Error('Account-Create failed');

  const caseOut = sfJson(
    `data create record -s Case -v "Subject='${TAG} cable broken' Status='Working' Origin='Phone' AccountId='${accId}'" -o ${ORG} --json`,
  );
  caseId = String(caseOut?.result?.id ?? '');
  if (!caseId) throw new Error('Case-Create failed');
});

test.afterAll(() => {
  if (caseId) cli(`data delete record -s Case -i ${caseId} -o ${ORG} --json`);
  if (accId) cli(`data delete record -s Account -i ${accId} -o ${ORG} --json`);
});

// ── AC1: closing WITHOUT a score is refused, Case stays open ───────────
test.describe('[SCRUM-442] AC1 — Schliessen ohne Rating refused', () => {
  test('REST/CLI closing without score → exact ValRule message, Case still open', async ({ page }) => {
    void page;
    // The CLI exits non-zero on a refused save, so execSync THROWS — the refusal
    // payload (error.data = the ValRule messages) comes off the thrown error's
    // stdout. Verified 2026-10-11 22:0x: errorCode FIELD_CUSTOM_VALIDATION_EXCEPTION
    // with the exact message; a plain sfJson() here would abort the test.
    let refused = false;
    let errs: string[] = [];
    try {
      const upd = sfJson(
        `data update record -s Case -i ${caseId} -v "Status='Closed'" -o ${ORG} --json`,
      );
      refused = upd?.result?.success !== true;
      errs = (upd?.result?.errors ?? []).map((e: any) => String(e?.message ?? e));
    } catch (err: any) {
      refused = true;
      const payload = String((err as any)?.stdout ?? (err as any)?.message ?? '');
      try {
        const parsed = JSON.parse(payload.slice(payload.indexOf('{'), payload.lastIndexOf('}') + 1));
        const data = (parsed as any)?.data ?? [];
        errs = (Array.isArray(data) ? data : []).map((e: any) => String(e?.message ?? e));
      } catch {
        errs = [payload];
      }
    }
    expect(refused, 'AC1: closing without a score must be refused').toBe(true);
    expect(
      errs.some((m) => m.includes(REJECT_MSG)),
      `AC1: refusal must carry the exact message "${REJECT_MSG}"`,
    ).toBe(true);

    const org = soql(`SELECT Id,Status,IsClosed,${API} FROM Case WHERE Id='${caseId}'`).records[0];
    expect(org.IsClosed, 'AC1: refused closing must not close the Case').toBe(false);
    expect(org.Status, 'AC1: Status untouched after refusal').not.toBe('Closed');
    expect(org[API], 'AC1: no score invented by the refused save').toBe(null);
  });
});

// ── AC2: the score is entered via the picklist combobox and PERSISTS ───
test.describe('[SCRUM-442] AC2 — Rating entered + stored', () => {
  test('combobox edit sets score 4, save persists, value readable', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Case/${caseId}/view`);

    // Verified locator: the Edit entry for the picklist field.
    const editBtn = page.getByRole('button', { name: `Edit ${SCORE_LABEL}` });
    await expect(editBtn, 'score not offered on the record page (layout/PS)').toBeVisible({ timeout: 15000 });
    await editBtn.first().click();
    await page.waitForTimeout(2000);

    // Verified locator: BUTTON[role=combobox] carrying the field's aria-label.
    const cb = page.getByRole('combobox', { name: SCORE_LABEL, exact: true }).first();
    await expect(cb, 'no Kundansatisfaction combobox in edit mode').toBeVisible({ timeout: 15000 });
    await cb.click();
    await page.waitForTimeout(2500);

    // Verified: options are role=option with EN-DASH names.
    const opt = page.getByRole('option', { name: '4 – satisfied', exact: true }).first();
    await expect(opt, 'option "4 – satisfied" not offered').toBeVisible({ timeout: 15000 });
    await opt.click();
    await page.waitForTimeout(2000);

    // The combobox now carries the chosen value (ariaSnapshot read-back).
    const snap = (await cb.ariaSnapshot() || '').replace(/\s+/g, ' ');
    expect(snap, 'combobox did not commit the chosen option').toContain('4 – satisfied');

    // Save (house saveInlineEdit semantics: Save or Save & New).
    const save = page.getByRole('button', { name: 'Save' }).first();
    const saveNew = page.getByRole('button', { name: 'Save & New' }).first();
    const useSave = await save.isVisible({ timeout: 5000 }).catch(() => false);
    await expect(useSave || await saveNew.isVisible().catch(() => false), 'no Save button after the picklist edit').toBe(true);
    await (useSave ? save : saveNew).click();
    await page.waitForTimeout(4000);

    // Persisted in the org — the post-save read-back the AC demands.
    const org = soql(`SELECT ${API} FROM Case WHERE Id='${caseId}'`).records[0];
    expect(org[API], 'AC2: score 4 persisted after save').toBe('Score_4');

    // Readable in the UI as the label text (verified locator).
    const readable = page.getByText('4 – satisfied', { exact: true }).first();
    await expect(readable, 'AC2: score not readable on the Case page after save').toBeVisible({ timeout: 15000 });
  });
});

// ── AC3: low score on closing → exactly one follow-up Task, visible ────
test.describe('[SCRUM-442] AC3 — follow-up Task after low score', () => {
  test('closed with score 2 → one Task (SOQL) + visible on its record page', async ({ page }) => {
    // The UI closing path is not reachable (org quirk 1, see header); the
    // closing is done on the REST path, the Task is then proven in the org
    // AND in the UI (house SCRUM-440 AC3 shape: SOQL proves, UI proves visibility).
    const closed = sfJson(
      `data update record -s Case -i ${caseId} -v "Status='Closed' ${API}='Score_2' Ursache__c='Out_of_hours'" -o ${ORG} --json`,
    );
    expect(closed?.result?.success, 'AC3 precondition: closing with score must succeed').toBe(true);

    const tasks = soql(`SELECT Id,Subject,Status,Priority,ActivityDate,OwnerId FROM Task WHERE WhatId='${caseId}' AND Subject LIKE '${TASK_PREFIX}%'`);
    expect(tasks.totalSize, 'AC3: exactly one follow-up Task').toBe(1);
    const t = tasks.records[0];
    expect(t.Subject, 'AC3: byte-exact prefix').toMatch(new RegExp('^' + TASK_PREFIX));
    expect(t.Status, 'AC3: Not Started').toBe('Not Started');
    expect(t.Priority, 'AC3: High').toBe('High');
    const owner = soql(`SELECT Id,OwnerId FROM Case WHERE Id='${caseId}'`).records[0];
    expect(t.OwnerId, 'AC3: Task owned by the Case owner (the rep)').toBe(owner.OwnerId);

    // Visibility in the UI: the Task renders on its own record page.
    await page.goto(`/lightning/r/Task/${t.Id}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
    await page.waitForTimeout(3000);
    const seen = page.getByText(TASK_PREFIX, { exact: false }).first();
    await expect(seen, 'AC3: follow-up Task not visible in the UI').toBeVisible({ timeout: 15000 });
  });
});

// ── AC4: reopen + reclose → still exactly ONE Task ─────────────────────
test.describe('[SCRUM-442] AC4 — no second reminder', () => {
  test('close low, reopen, reclose low → Task count stays 1', async ({ page }) => {
    void page;
    // Each test.describe block gets its OWN beforeAll seed (Playwright BDD),
    // so this block's Case is fresh: create the first reminder first.
    const first = sfJson(
      `data update record -s Case -i ${caseId} -v "Status='Closed' ${API}='Score_2' Ursache__c='Out_of_hours'" -o ${ORG} --json`,
    );
    expect(first?.result?.success, 'AC4 precondition: first closing succeeds').toBe(true);
    const before = soql(`SELECT Id FROM Task WHERE WhatId='${caseId}' AND Subject LIKE '${TASK_PREFIX}%'`);
    expect(before.totalSize, 'AC4 precondition: one Task already exists').toBe(1);

    const reopen = sfJson(`data update record -s Case -i ${caseId} -v "Status='Escalated'" -o ${ORG} --json`);
    expect(reopen?.result?.success, 'AC4: reopen succeeds').toBe(true);
    const reclose = sfJson(
      `data update record -s Case -i ${caseId} -v "Status='Closed' ${API}='Score_1' Ursache__c='Out_of_hours'" -o ${ORG} --json`,
    );
    expect(reclose?.result?.success, 'AC4: reclose with low score succeeds').toBe(true);

    const after = soql(`SELECT Id,Subject FROM Task WHERE WhatId='${caseId}' AND Subject LIKE '${TASK_PREFIX}%'`);
    expect(after.totalSize, 'AC4: closed twice → still exactly ONE Task').toBe(1);
    const st = soql(`SELECT Status,IsClosed,ClosedDate,${API} FROM Case WHERE Id='${caseId}'`).records[0];
    expect(st.IsClosed, 'AC4: Case closed again').toBe(true);
    expect(st[API], 'AC4: new low score stored').toBe('Score_1');
  });
});

// ── AC5: Account overview renders the satisfaction section ─────────────
test.describe('[SCRUM-442] AC5 — Account overview', () => {
  test('Account detail page shows the section with values (non-zero)', async ({ page }) => {
    // This block's seed is fresh: close its Case with a low score first, so the
    // Rebuilder has a scored, closed Case on THIS Account to roll up.
    const closed = sfJson(
      `data update record -s Case -i ${caseId} -v "Status='Closed' ${API}='Score_2' Ursache__c='Out_of_hours'" -o ${ORG} --json`,
    );
    expect(closed?.result?.success, 'AC5 precondition: closing with score succeeds').toBe(true);

    // The Rebuilder must have run for the rollups to carry values.
    sfJson(`apex run -o ${ORG} -f scratch/SCRUM442-rebuilder-driver.cls --json`);

    await openRecordDetails(page, `/lightning/r/Account/${accId}/view`);

    // Verified labels (FieldDefinition.Label read back from the org).
    for (const label of ['Status ärger?', 'Satisfaction Ø (3 Monate)', 'Satisfaction min (3 Monate)', 'Cases in Ø-Fenster', 'Ø-Fenster seit']) {
      await expect(
        page.getByText(label, { exact: true }).first(),
        `layout label "${label}" missing on the Account Details tab`,
      ).toBeVisible({ timeout: 15000 });
    }

    // NON-ZERO: the indicator and the average carry real values for this Account.
    const roll = soql(`SELECT Satisfaction_Arger__c,Satisfaction_Durchdurch__c,Satisfaction_Min__c,Satisfaction_Anzahl__c FROM Account WHERE Id='${accId}'`).records[0];
    expect(roll.Satisfaction_Arger__c !== null, 'AC5: indicator carries a value (not null)').toBe(true);
    expect(roll.Satisfaction_Anzahl__c, 'AC5: NON-ZERO — at least one scored Case in the window').toBeGreaterThan(0);
    expect(roll.Satisfaction_Durchdurch__c !== null, 'AC5: average computed').toBe(true);
    expect(roll.Satisfaction_Arger__c, 'AC5: a score of 1/2 makes the customer AErger').toBe('Ärger');

    // The indicator value is rendered in the UI next to its label.
    await expect(
      page.getByText('Ärger', { exact: true }).first(),
      'AC5: indicator value "Ärger" not visible on the Account page',
    ).toBeVisible({ timeout: 15000 });
  });
});

// ── AC6: overview Report lists EXACTLY the dissatisfied customers ─────
test.describe('[SCRUM-442] AC6 — overview Report', () => {
  test('Report rows == SOQL count of AErger-Accounts, non-zero', async ({ page }) => {
    // Ground truth from the org: Accounts flagged AErger whose window is inside
    // the report's INTERVAL_LAST90 on Satisfaction_Fenster_Start__c.
    const gt = soql(`SELECT Id,Name FROM Account WHERE Satisfaction_Arger__c='Ärger'`);
    expect(gt.totalSize, 'AC6: NON-ZERO ground truth — at least one dissatisfied customer exists').toBeGreaterThan(0);

    // Report id read back from the org via
    // `sf project retrieve start --metadata "Report:Sales/Miserable_Kunde_Satisfaction"`
    // (Id 00OWU00000QqteB2AR, house pattern SCRUM-434 uses a constant id — the
    // Tooling `Report` sObject query is NOT supported: INVALID_TYPE).
    const rid: string = '00OWU00000QqteB2AR';
    expect(rid !== '', 'AC6: the Report is deployed in the org').toBe(true);

    await page.goto(`/lightning/r/Report/${rid}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    let frame: any = null;
    const deadline = Date.now() + 90000;
    while (!frame) {
      frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
      if (frame) break;
      if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) not found');
      await page.waitForTimeout(1500);
    }
    await frame.waitForTimeout(12000);

    const rows = await frame.locator('tbody tr').count();
    expect(rows, `AC6: Report rows (${rows}) must equal the org count (${gt.totalSize})`).toBe(gt.totalSize);
    expect(rows, 'AC6: NON-ZERO — the overview must actually list the customer').toBeGreaterThan(0);
  });
});
