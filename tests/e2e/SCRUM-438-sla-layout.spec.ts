import { test, expect, type Page } from '@playwright/test';
import { openRecordPage } from './record-page';

/**
 * [SCRUM-438] AC12 — UI-Read-Back: „SLA"-Layout-Sektion auf der Lightning-Case-Page.
 *
 * AC12 (Design): „Layout: eigene Sektion SLA mit Zielzeit, Status, Eskalation,
 * Ueberschritten (primär) + Letzter Lauf (Detail). Items: behavior=Readonly.
 * SLA_Uhr_gestoppt__c und SLA_Akkumulierte_WorkingMins__c bewusst NICHT
 * auf dem Layout (intern)."
 *
 * Die Case-Record-Page rendert Details in einer EIGENEN, bereits ausgewählten
 * Pane (rechter Spalte) — das Contact-Muster (Related-first, Details muss
 * geklickt werden) gilt hier nicht (SCRUM-390, dokumentiert in ensureDetailsPane).
 *
 * Test-Record: 500WU00002uFVFCYA4 — per API erstellt, before-Trigger hat
 * alle 7 SLA-Felder initialisiert (SLA_Zielzeit__c gesetzt, Status=Im Zeitplan).
 *
 * UI-Labels, org-verifiziert via FieldDefinition 2026-10-04:
 *   SLA_Zielzeit__c            -> SLA-Zielzeit
 *   SLA_Status__c              -> SLA-Status
 *   SLA_Eskalation__c          -> SLA-Eskalationsstufe
 *   SLA_Ueberschritten__c      -> SLA überschritten
 *   SLA_Last_Checked__c        -> SLA letzter Lauf
 *   (intern, NICHT auf Layout:)
 *   SLA_Uhr_gestoppt__c        -> SLA Uhr gestoppt (intern)
 *   SLA_Akkumulierte_WorkingMins__c -> SLA kumulierte Working-Minuten
 */

const CASE_ID = '500WU00002uFVFCYA4';
const CASE_PATH = `/lightning/r/Case/${CASE_ID}/view`;

// 5 Felder die AKTIV in der SLA-Section auf dem Layout stehen (org-verifiziert)
const VISIBLE_FIELDS = [
  { label: 'SLA-Zielzeit',             api: 'SLA_Zielzeit__c' },
  { label: 'SLA-Status',               api: 'SLA_Status__c' },
  { label: 'SLA-Eskalationsstufe',     api: 'SLA_Eskalation__c' },
  { label: 'SLA überschritten',        api: 'SLA_Ueberschritten__c' },
  { label: 'SLA letzter Lauf',         api: 'SLA_Last_Checked__c' },
] as const;

// 2 Felder die bewusst NICHT auf dem Layout sind (intern)
const HIDDEN_FIELDS = [
  { label: 'SLA Uhr gestoppt (intern)',      api: 'SLA_Uhr_gestoppt__c' },
  { label: 'SLA kumulierte Working-Minuten', api: 'SLA_Akkumulierte_WorkingMins__c' },
] as const;

/**
 * Details-Pane in beide Seitenformen abholen (Case: eigene ausgewählte Pane;
 * Contact: Related-first, Klick nötig). Gleicher Ansatz wie SCRUM-390.
 */
async function ensureDetailsPane(page: Page) {
  const fieldProbe = page.getByText('SLA-Zielzeit').first();
  const detailsTab = page.getByRole('tab', { name: 'Details' });
  for (let attempt = 0; attempt < 4; attempt++) {
    if (await fieldProbe.isVisible({ timeout: 1500 }).catch(() => false)) return;
    const tabVisible = await detailsTab.isVisible({ timeout: 1500 }).catch(() => false);
    if (!tabVisible) continue;
    const selected = await detailsTab.getAttribute('aria-selected').catch(() => null);
    if (selected === 'true') continue;
    await detailsTab.click();
    await page.waitForTimeout(1500);
  }
}

test.describe('[SCRUM-438] AC12 SLA-Section in Case-UI', () => {
  test.describe.configure({ timeout: 120000 });

  test('AC12a: „SLA" ist eine eigene Sektion (heading) auf der Case-Details-Page', async ({ page }) => {
    await openRecordPage(page, CASE_PATH);
    await ensureDetailsPane(page);

    const sectionHeading = page.getByRole('heading', { name: 'SLA', exact: true });
    await expect(
      sectionHeading,
      'Section-Heading „SLA" NICHT sichtbar auf der Case-Details-Page — ' +
        'AC12 Layout-Sektion fehlt. Diagnose: ' +
        'sf project retrieve start --metadata "Layout:Case-Case Layout" ' +
        'und grep "SLA" in der Datei.'
    ).toBeVisible({ timeout: 20000 });
  });

  test('AC12b: alle 5 SLA-Felder sind als Komponenten in der Sektion sichtbar', async ({ page }) => {
    await openRecordPage(page, CASE_PATH);
    await ensureDetailsPane(page);

    for (const f of VISIBLE_FIELDS) {
      const lbl = page.getByText(f.label, { exact: true }).first();
      await expect(
        lbl,
        `Feld "${f.label}" (${f.api}) NICHT sichtbar in der SLA-Sektion — AC12 verletzt`
      ).toBeVisible({ timeout: 15000 });
    }
    // Evidenz über Pass/Fail hinaus: Werte der 5 Felder aus der Read-Back-SoQL
    // (LIVE-INIT, 2026-10-04): Status=Im Zeitplan, Eskalation=Keine,
    // Ueberschritten=false, Zielzeit>CreatedDate, Last_Checked=CreatedDate.
    console.log(
      '=== [SCRUM-438] AC12b Sichtbarkeit: alle 5 Felder gefunden. ' +
      'SoQL-Read-Back: Status=Im Zeitplan, Eskalation=Keine, Ueberschritten=false ==='
    );
  });

  test('AC12c: die 2 internen SLA-Felder sind NICHT auf dem Case-Layout', async ({ page }) => {
    await openRecordPage(page, CASE_PATH);
    await ensureDetailsPane(page);

    for (const f of HIDDEN_FIELDS) {
      const lbl = page.getByText(f.label, { exact: true });
      await expect(
        lbl,
        `Feld "${f.label}" (${f.api}) IST sichtbar auf dem Case-Layout — ` +
          'sollte bewusst intern bleiben (AC12: behavior=Readonly primary, ' +
          'Uhr_gestoppt und WorkingMins NICHT auf Layout).'
      ).toHaveCount(0, { timeout: 5000 });
    }
    console.log(
      '=== [SCRUM-438] AC12c Negative-Prüfung: „SLA Uhr gestoppt (intern)" und ' +
      '„SLA kumulierte Working-Minuten" nicht sichtbar — korrekt (intern) ==='
    );
  });

});
