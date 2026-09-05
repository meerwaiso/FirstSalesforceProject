import { test, expect, type Page } from '@playwright/test';
import { openRecordPage } from './record-page';

/**
 * [SCRUM-390] AC1 — Lightning-Read-Back: „Bearbeitungsdauer (Tage)" und
 * „Überfällig" als sichtbare Komponenten auf der Lightning-Case-Page.
 *
 * PO-Entscheidung 16230: AC2–AC5 akzeptiert (Live-SOQL-Read-back, 514-Fall-Scan),
 * AC1 Classic akzeptiert (record-ui Full/View). Für Lightning reichte die
 * record-ui-Inferenz nicht — dieser Spec ist der geforderte direkte Read-Back.
 * Test-Org fährt auf der System-Default-Case-Page (keine explizite
 * Lightning-Case-FlexiPage, @devops via FlexiPage-Retrieve verifiziert);
 * die Details reibungfrei aus dem Classic-Layout.
 *
 * Record 500WU00002VPZQ5YAP (Case 00001024): offen, Low, 63 Tage alt,
 * Is_Overdue__c=true — Feldwerte per SOQL read-back verifiziert vor Testlauf.
 *
 * Seitenform (aus dem 1. Lauffehler-Snapshot dokumentiert, 05.09.): Die
 * Case-Record-Page rendert Details in einer EIGENEN, bereits ausgewählten
 * Pane (rechte Spalte, tablist mit einziger Tab "Details" [selected]) — das
 * Contact-Muster (Related-first, Details muss geklickt werden) gilt hier NICHT;
 * der Haus-Helper openDetailsTab stößt an genau dieser Stelle auf 30s-Timeout,
 * weil er den Details-Tab des Contact-Musters erwartet. Deshalb: Details-Tab
 * nur bedienen, wenn er existiert UND nicht ausgewählt ist; die AC-Beweise
 * sind die FELD-Komponenten selbst + die gerenderten Werte.
 */
const CASE_PATH = '/lightning/r/Case/500WU00002VPZQ5YAP/view';

/**
 * Details-Pane in beide Seitenformen abholen (Case: eigene ausgewählte Pane;
 * Contact: Related-first, Klick nötig). Klick-Versuche nur, wenn der Tab
 * sichtbar ist und den Feldern vorher nicht bereits gerendert sind.
 */
async function ensureDetailsPane(page: Page) {
  const fieldProbe = page.getByText('Bearbeitungsdauer (Tage)').first();
  const detailsTab = page.getByRole('tab', { name: 'Details' });

  for (let attempt = 0; attempt < 4; attempt++) {
    if (await fieldProbe.isVisible({ timeout: 1500 }).catch(() => false)) return;
    const tabVisible = await detailsTab.isVisible({ timeout: 1500 }).catch(() => false);
    if (!tabVisible) continue; // noch nicht gerendert — weiter warten
    const selected = await detailsTab.getAttribute('aria-selected').catch(() => null);
    if (selected === 'true') continue; // Details bereits aktiv (Case-Form)
    await detailsTab.click();
  }
}

test.describe('[SCRUM-390] AC1 Lightning read-back', () => {
  test.describe.configure({ timeout: 120000 });

  test('AC1: beide Felder sichtbar als Komponenten auf der Lightning-Case-Page (Details/Sektion Überwachung)', async ({ page }) => {
    await openRecordPage(page, CASE_PATH);
    await ensureDetailsPane(page);

    // Beide Feld-Labels als sichtbare Komponenten (Details-Seitenform; die
    // Case-Default-Page hat keine zweite Stelle, an der diese Labels stehen
    // könnten — kein Chatter/Related-Inhalt mit diesem Text).
    const lblDuration = page.getByText('Bearbeitungsdauer (Tage)', { exact: true }).first();
    const lblOverdue = page.getByText('Überfällig', { exact: true }).first();

    await expect(
      lblDuration,
      'Feld "Bearbeitungsdauer (Tage)" NICHT sichtbar auf der Lightning-Case-Page — AC1 Lightning nicht belegt'
    ).toBeVisible({ timeout: 20000 });
    await expect(
      lblOverdue,
      'Feld "Überfällig" NICHT sichtbar auf der Lightning-Case-Page — AC1 Lightning nicht belegt'
    ).toBeVisible({ timeout: 10000 });

    // Wert-Read-Back (Evidenz über Pass/Fail hinaus): die slds-form-element-
    // Container rund um die Labels tragen den gerenderten Formelwert.
    const durationBox = page.locator('div.slds-form-element', { hasText: 'Bearbeitungsdauer (Tage)' }).first();
    const durationText = (await durationBox.innerText().catch(() => '')) || await lblDuration.locator('..').innerText().catch(() => '');
    console.log('=== [SCRUM-390] AC1 Wert-Read-Back: Bearbeitungsdauer-Container ===\n' + durationText);
    expect(
      durationText,
      'Bearbeitungsdauer-Wert 63 (offener Fall, 63 Tage alt) NICHT gerendert'
    ).toContain('63');

    const overdueBox = page.locator('div.slds-form-element', { hasText: 'Überfällig' }).first();
    const overdueText = await overdueBox.innerText().catch(() => '');
    console.log('=== [SCRUM-390] AC1 Wert-Read-Back: Überfällig-Container ===\n' + overdueText);
    expect(
      overdueText,
      'Überfällig-Wert (True für 63-tägiger offener Low-Fall) NICHT gerendert'
    ).toMatch(/True|true/i);
  });
});
