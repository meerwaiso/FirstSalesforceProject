import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, saveInlineEdit, startInlineEdit } from './record-page';

/**
 * [SCRUM-440] E2E: Rückrufwunsch auf Opportunity in der Lightning-UI.
 *
 * Deckt die UI-Seite der Akzeptanzkriterien, die Apex-Tests nicht können:
 *
 *   AC1 — Opportunity öffnet for editing → checkbox „Rückruf gewünscht“ +
 *          datetime „Rückruf am“ BOTH visible on the Details tab, each with an
 *          „Edit …“ button (main layout, no collapsible section).
 *   AC2 — checked + „Rückruf am“ empty → save REJECTED with the exact message
 *          „Bitte einen Rückruftermin in der Zukunft angeben.“ (ValRule pair).
 *   AC3 — checked + valid future „Rückruf am“ → save PERSISTS (SOQL read-back)
 *          AND the after-update handler auto-creates exactly one open callback
 *          Task (Subject „Rückruf: “+Name, Priority High, ActivityDate=date).
 *
 * NOT here (Apex, house method — SCRUM440RueckrufwunschTest/FlsTest):
 *   AC4 update-existing-no-duplicate, AC5 uncheck→Deferred, AC6 FLS neg/pos,
 *   AC7 coverage, bulk200. Those run as Apex System.runAs tests (no 3rd licence).
 *
 * Locators VERIFIED via probe (2026-10-10, Opportunity 006WU00000TOLDtYAP):
 *   - Details tab: getByRole('tab',{name:'Details'}) — record-page helper.
 *   - Field labels „Rückruf gewünscht“/„Rückruf am“ visible on Details tab.
 *   - „Edit Rückruf gewünscht“ button enters inline edit (whole section).
 *   - Checkbox: input[name="Rueckruf_desired__c"] type=checkbox; click → checked.
 *   - Datetime: TWO input[name="Rueckruf_am__c"] — [0]=date text (MM/DD/YYYY),
 *     [1]=time combobox (role=combobox). fill() sets date cleanly; the time
 *     combobox needs an option selected for the datetime to commit.
 *   - Save: house saveInlineEdit (Save / Save & New).
 */

const OPP_LABEL = 'Rückruf gewünscht';
const DATE_LABEL = 'Rückruf am';
const CB_API = 'Rueckruf_desired__c';
const DT_API = 'Rueckruf_am__c';
const REJECT_MSG = 'Bitte einen Rückruftermin in der Zukunft angeben.';

// ── SF-CLI helpers (house SCRUM-430) ───────────────────────────────────
function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}
function soql(soqlText: string): any {
  const out = execSync(
    `sf data query --query "${soqlText}" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe','pipe','pipe'], maxBuffer: 10*1024*1024,
      env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } },
  );
  return shellJson(out).result;
}

let oppId: string;

test.beforeAll(() => {
  const tag = 'TEST-SCRUM440-E2E-' + Date.now().toString(36).toUpperCase();
  const out = execSync(
    `sf data create record -s Opportunity -v "Name='${tag}' StageName=Prospecting CloseDate=2027-03-31" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } },
  );
  const id = shellJson(out)?.result?.id || shellJson(out)?.id;
  if (!id) throw new Error(`Opportunity-Create failed: ${out.slice(0,300)}`);
  oppId = String(id);
});

test.afterAll(() => {
  if (oppId) {
    execSync(
      `sf data delete record -s Opportunity -i ${oppId} --target-org Test-Org --json`,
      { encoding: 'utf-8', timeout: 120000, stdio: ['pipe','pipe','pipe'], env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } },
    );
  }
});

// A future date well beyond NOW() so the ValRule (<= NOW()) passes.
// The org's locale is German: the datetime input ONLY accepts DD.MM.YYYY.
// Verified 2026-10-10: US "12/25/2027" sets the DOM .value but never enters the
// Aura edit model (save commits nothing, no error); "25.12.2027" commits.
const FUTURE_DATE = '25.12.2027';   // DD.MM.YYYY, verified accepted
const FUTURE_TIME = '14:30';        // timepicker option, 15-min steps

/** Enter inline edit and set checkbox + datetime (date text + time combobox option). */
async function setCallback(page: Page, checked: boolean, date: string | null, time: string | null) {
  const editBtn = page.getByRole('button', { name: `Edit ${OPP_LABEL}` });
  await expect(editBtn).toBeVisible({ timeout: 15000 });
  await editBtn.click();
  await page.waitForTimeout(1200);

  const cb = page.locator(`input[name="${CB_API}"]`).first();
  await expect(cb).toBeVisible({ timeout: 10000 });
  if (checked) await cb.click();

  if (date) {
    const ins = await page.locator(`input[name="${DT_API}"]`).all();
    await expect(ins.length, 'datetime renders as date-text + time-combobox (2 inputs)').toBe(2);
    await ins[0].fill(date);
    if (time) {
      // The time combobox needs an OPTION clicked for the datetime to commit.
      // Options are lightning-base-combobox-item[role=option] with the value in
      // data-value (e.g. "14:30:00.000", 15-min steps) — textContent is empty.
      // Scope to the combobox's own .slds-combobox wrapper (slds-timepicker) so
      // we never grab another combobox's options.
      const combo = ins[1];
      await combo.click();
      await page.waitForTimeout(800);
      const optHandle = await combo.evaluateHandle((el, want) => {
        const wrap = el.closest('.slds-combobox');
        if (!wrap) throw new Error('datetime time-combobox has no .slds-combobox wrapper');
        const opts = wrap.querySelectorAll('[role="option"]');
        for (const o of opts) {
          const dv = o.getAttribute('data-value') || '';
          if (dv.startsWith(want)) return o;
        }
        throw new Error(`no time option "${want}" in the datetime timepicker`);
      }, time);
      await optHandle.click();
      await page.waitForTimeout(600);
    }
  }
}

// ── AC1: both fields visible on the Details tab ────────────────────────
test.describe('[SCRUM-440] AC1 — Felder sichtbar in der UI', () => {
  test('Opportunity öffnet for editing → checkbox + datetime BOTH visible', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${oppId}/view`);

    await expect(
      page.getByText(OPP_LABEL, { exact: true }).first(),
      `Field label "${OPP_LABEL}" not on the Details tab — layout entry missing or field not deployed`,
    ).toBeVisible({ timeout: 15000 });
    await expect(
      page.getByText(DATE_LABEL, { exact: true }).first(),
      `Field label "${DATE_LABEL}" not on the Details tab — layout entry missing or field not deployed`,
    ).toBeVisible({ timeout: 15000 });

    // Each field is directly editable (Edit button visible without unfolding)
    await expect(
      page.getByRole('button', { name: `Edit ${OPP_LABEL}` }),
      'Checkbox field not directly editable — sits in a collapsible section',
    ).toBeVisible({ timeout: 10000 });
    await expect(
      page.getByRole('button', { name: `Edit ${DATE_LABEL}` }),
      'Datetime field not directly editable — sits in a collapsible section',
    ).toBeVisible({ timeout: 10000 });
  });
});

// ── AC2: checked + empty date → save rejected, exact message ───────────
test.describe('[SCRUM-440] AC2 — Save-Rejection', () => {
  test('checked + „Rückruf am“ empty → save rejected with exact message', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${oppId}/view`);

    // Enter edit, check the box, leave the date EMPTY
    const editBtn = page.getByRole('button', { name: `Edit ${OPP_LABEL}` });
    await expect(editBtn).toBeVisible({ timeout: 15000 });
    await editBtn.click();
    await page.waitForTimeout(1200);
    const cb = page.locator(`input[name="${CB_API}"]`).first();
    await cb.click();
    const checked = await cb.evaluate((n) => (n as any).checked);
    expect(checked, 'checkbox click did not set checked=true').toBe(true);

    await saveInlineEdit(page);
    await page.waitForTimeout(3000);

    // The exact ValRule errorMessage must be shown, and the save must NOT persist.
    const bodyText = await page.evaluate(() => document.body.innerText);
    expect(bodyText, `save not rejected with the exact message "${REJECT_MSG}"`).toContain(REJECT_MSG);

    const org = soql(`SELECT ${CB_API},${DT_API} FROM Opportunity WHERE Id='${oppId}'`).records[0];
    expect(org[CB_API], 'rejected save must not persist checkbox=true').toBe(false);
    expect(org[DT_API], 'rejected save must not persist a date').toBe(null);
  });
});

// ── AC3: checked + valid future date → persists + auto-creates Task ────
test.describe('[SCRUM-440] AC3 — Save & auto-Task', () => {
  test('checked + valid future date → persists (SOQL) + one open callback Task', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${oppId}/view`);
    await setCallback(page, true, FUTURE_DATE, '14:30');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    // Persisted in the org (SOQL read-back)
    const org = soql(`SELECT ${CB_API},${DT_API} FROM Opportunity WHERE Id='${oppId}'`).records[0];
    expect(org[CB_API], 'AC3: checkbox persisted true').toBe(true);
    expect(org[DT_API], 'AC3: future date persisted (not null)').toBeTruthy();

    // The after-update handler auto-created exactly one open callback Task
    const tasks = soql(`SELECT Id,Subject,Status,Priority,ActivityDate FROM Task WHERE WhatId='${oppId}' AND Subject LIKE 'Rückruf:%' AND IsClosed=false`);
    expect(tasks.totalSize, 'AC3: exactly one open callback Task auto-created').toBe(1);
    const t = tasks.records[0];
    expect(t.Subject, 'AC3: Task Subject prefix „Rückruf: “').toMatch(/^Rückruf: /);
    expect(t.Priority, 'AC3: Task Priority Hoch = High').toBe('High');
    expect(t.Status, 'AC3: new Task Not Started').toBe('Not Started');
  });
});
