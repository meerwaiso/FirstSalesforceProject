import { test, expect } from '@playwright/test';
import { openRecordPage, openDetailsTab } from './record-page';

/**
 * [SCRUM-418] AK4 — Wiederaufmachen über die Lightning-UI, dann sofort die
 * Reaktivierungszahl lesen.
 *
 * Dies ist die Akzeptanzkriterium-Slice, die den Defekt in der echten
 * User-Interaktion (Lightning speichert per REST) reproduziert.
 *
 * Befund aus der Tester-Session (2026-09-18, Test-Org devops-agent@cline.test):
 *   - In-Org-Apex-DML: 1 Reopen → Zähler 1 (korrekt)
 *   - Externes REST/CLI-Update: 1 Reopen → Zähler 2 (DEFECT, 7× reproduziert)
 * Lightning speichert einen Status-Wechsel per REST → der UI-Pfad zeigt den
 * 2-Fachen Wert. Dieser Test ist der reproduzierbare, gebundene Nachweis.
 *
 * Fixture: ein frisch geschlossener Case (`CLOSED_CASE`, Subject
 * "SCRUM418_UIREOPEN"). Der Test wechselt den Status per UI auf einen offenen
 * Wert, speichert, und liest den Zähler vom Details-Tab zurück.
 *
 * AK4-Prompt: „…wechsle den Status wieder auf offen und speichere … zeigt die
 * Reaktivierungszahl schon den erhöhten Wert". Erwarteter erhöhter Wert nach
 * genau einer bisherigen Schließung + dieser einen Wiederaufmachung = 1.
 */

const CLOSED_CASE = '500WU00002rZt5fYAC'; // Subject "SCRUM418_UIREOPEN", Status=Closed

test.describe('[SCRUM-418] AK4 — Wiederaufmachen über Lightning-UI', () => {
  test('AC4: Status auf offen + Speichern → Reaktivierungszahl steigt exakt um 1 (auf 1)', async ({ page }) => {
    await openRecordPage(page, `/lightning/r/Case/${CLOSED_CASE}/view`);
    await openDetailsTab(page);

    // Status-Feld inline bearbeiten. Der Fall ist „Closed"; öffnen auf „New".
    const statusEdit = page.getByRole('button', { name: 'Edit Status' });
    await expect(statusEdit, 'Status-Feld nicht inline editierbar — prüfe FLS-PS / Layout').toBeVisible({ timeout: 15000 });
    await statusEdit.click();
    await page.waitForTimeout(800);

    const statusInput = page.getByLabel('Status', { exact: true }).first();
    await statusInput.click();
    await page.getByRole('option', { name: 'New' }).first().click();
    await page.waitForTimeout(500);

    // Speichern (Lightning: „Save" oder „Save & New").
    const save = page.getByRole('button', { name: 'Save' });
    if (await save.isVisible({ timeout: 5000 }).catch(() => false)) {
      await save.click();
    } else {
      await page.getByRole('button', { name: 'Save & New' }).click();
    }
    // Auf den re-render wartet der Details-Tab mit dem Zähler-Wert.
    await page.waitForTimeout(2500);

    // AK4-Observation: die Zelle „Reaktivierungszahl" zeigt „1" (nicht 2).
    // Bekannter Defekt: externes REST-Update (UI-save) inkrementiert DOPPELT →
    // die Zelle würde „2" zeigen und diese Expectation rot.
    const counterCell = page
      .getByText('Reaktivierungszahl', { exact: false })
      .first()
      .locator('..')
      .getByText(/^\d+$/)
      .first();
    await expect(counterCell).toHaveText('1', { timeout: 15000 });
  });
});
