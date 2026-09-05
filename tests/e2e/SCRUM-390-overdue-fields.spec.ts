import { test, expect, type Locator } from '@playwright/test';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-390] AC1 — Lightning-Read-Back: „Bearbeitungsdauer (Tage)" und
 * „Überfällig" als sichtbare Komponenten auf der Case-Record-Page (Lightning).
 *
 * PO-Entscheidung 16230: AC2–AC5 akzeptiert (Live-SOQL-Read-back, 514-Fall-Scan),
 * AC1 Classic akzeptiert (record-ui Full/View). Für Lightning reichte sie die
 * record-ui-Inferenz nicht — dieser Spec ist der geforderte direkte Read-Back:
 * die Test-Org läuft auf der System-Default-Page (keine explizite
 * Lightning-Case-FlexiPage, verified via FlexiPage-Retrieve @devops), die
 * Details reibungfrei aus dem Classic-Layout rendert.
 *
 * Record 500WU00002VPZQ5YAP (Case 00001024): offen, Low, 63 Tage alt,
 * Is_Overdue__c=true — Werte per SOQL read-back verifiziert vor Testlauf.
 *
 * House-Konvention (record-page.ts): Record-Page öffnet auf Related-Tab, die
 * Layout-Felder rendern erst unter Details; openDetailsTab wartet auf den
 * Tab, klickt und verifiziert den Wechsel (Retry) statt fixed sleep.
 */
const CASE_PATH = '/lightning/r/Case/500WU00002VPZQ5YAP/view';

/**
 * Label im Details-Tab-Panel beschränkt suchen (kein full-Page-Scan): ein
 * Label außerhalb des Detail-Panels (Related-/Chatter-Bereich) erfüllt die
 * AC nicht. Beide Felder sind read-only Formelfelder — es muss das LABEL
 * als sichtbare Komponente im Panel geben.
 */
async function expectLabelInDetailsPanel(panel: Locator, label: string) {
  const el = panel.getByText(label, { exact: false }).first();
  await expect(
    el,
    `Label "${label}" nicht sichtbar im Details-Tab-Panel — die AC1-Feld-Sichtbarkeit in Lightning wäre damit NICHT belegt`
  ).toBeVisible({ timeout: 15000 });
}

test.describe('[SCRUM-390] AC1 Lightning read-back', () => {
  test('AC1: beide Felder sichtbar als Komponenten auf der Lightning-Case-Page', async ({ page }) => {
    await openRecordDetails(page, CASE_PATH);
    const details = page.getByRole('tabpanel', { name: 'Details', exact: true });
    await expect(details).toBeVisible({ timeout: 15000 });

    await expectLabelInDetailsPanel(details, 'Bearbeitungsdauer (Tage)');
    await expectLabelInDetailsPanel(details, 'Überfällig');

    // Evidenz (Read-Back statt nur Pass/Fail): Panel-Text inkl. gerenderten
    // Werten — 63 für offen Low 63 Tage alt, Überfällig-Status true.
    const panelText = await details.innerText().catch(() => '<panel nicht lesbar>');
    console.log('=== [SCRUM-390] AC1 Details-Panel Evidenz ===\n' + panelText);
    // Werte-Read-Back: die 63 der open Case 00001024 muss im Panel stehen
    expect(panelText, 'Bearbeitungsdauer-Wert 63 nicht im Details-Panel gerendert').toContain('63');
  });
});
