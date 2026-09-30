import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'child_process';

/**
 * [SCRUM-434] AC4 — Report "Geschlossene Fälle je Ursache-Kategorie über
 * einen Zeitraum (Monat/Quartal)" mit funktionierendem Zeitraumfilter.
 *
 * AC4 verlangt: Ein Report gruppiert geschlossene Cases nach Ursache__c, und
 * der Zeitraumfilter (timeFrameFilter) muss die Anzeige umschaltbar sein
 * (Monat ~ "Last 30 Days", Quartal ~ "Last 90 Days").
 *
 * Prüfstrategie (Zielsystem, nicht DOM-Glaube):
 *  1. SOQL-Ground-Truth direkt aus der Org: Anzahl geschlossener Cases mit
 *     ClosedDate in den letzten 30 bzw. 90 Tagen, gruppiert nach Ursache__c.
 *  2. Den Report rendern, die Gruppen- und Total-Zeilen LISEN.
 *  3. UI-Assertion: jede Report-Zeile trifft die SOQL-Zahl exakt.
 *  4. Zeitraumfilter im Filter-Panel auf "Last 30 Days" umschalten, Apply.
 *  5. Neue Total-Zeile muss die 30-Tage-SOQL-Zahl treffen — nicht mehr 23,
 *     sondern der kleinere Wert. Das beweist, dass der Filter wirkt, nicht
 *     nur dass der Report rendert.
 *
 * UI-Navigation (VERIFIZIERT 2026-09-30, Probe):
 *  - Report-App läuft im iframe 'lightningReportApp' (Crossdoc).
 *  - Filter-Toggle:  button.action-bar-action-toggleFilter  (im Frame)
 *  - Zeitfilterzeile: li.sectionable-table-row mit Text /Date\/Time Closed/
 *  - Range-Wahl:      div.custom-range-picklist input.slds-combobox__input
 *                     -> Options als li[role=option] ("Last 30 Days" etc.)
 *  - Apply:           button.filter-apply
 *
 * Hinweis: Salesforce bietet in diesem Report-Typ nur Tage-basierte
 * Intervalle (30/60/90/120) — kein Kalender-Monat/-Quartal. "Monat/Quartal"
 * aus der AC wird durch "Last 30 Days" / "Last 90 Days" abgebildet, exakt
 * wie im Report-Design (docs/SCRUM-434-design.md) definiert.
 */

const ORG = 'devops-agent@cline.test';
const REPORT_ID = '00OWU00000QcH452AF';

function cli(args: string): string {
  return execSync(`FORCE_COLOR=0 NO_COLOR=1 sf ${args}`, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function sfJson(args: string): any {
  const raw = cli(args);
  return JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
}

/** Anzahl geschlossener Cases mit ClosedDate in den letzten `days` Tagen,
 *  gruppiert nach Ursache__c (leer wird als '(leer)' gezählt). */
function soqlClosedByUrsache(days: number): { total: number; byUrsache: Record<string, number> } {
  const from = new Date(Date.now() - days * 86400000).toISOString();
  const to = new Date(Date.now() + 86399000).toISOString();
  const q = `SELECT Id, IsClosed, ClosedDate, Ursache__c FROM Case WHERE ClosedDate>='${from.replace('T', 'T')}' AND ClosedDate<='${to}'`.replace(
    /'\d{4}-\d{2}-\d{2}T[0-9:.]+Z'/g,
    (m) => m.replace(/'/g, ''),
  );
  const recs = sfJson(`data query -o ${ORG} -q "${q}" --json`).result.records;
  const closed = recs.filter((r: any) => r.IsClosed);
  const byUrsache: Record<string, number> = {};
  for (const r of closed) {
    const key = r.Ursache__c ?? '(leer)';
    byUrsache[key] = (byUrsache[key] ?? 0) + 1;
  }
  if (closed.length === 0) throw new Error(`SOQL: 0 geschlossene Cases in den letzten ${days} Tagen — AC4 wäre ungetestet (Daten fehlen)`);
  return { total: closed.length, byUrsache };
}

/** DeveloperName -> Label im Report (UI zeigt Display-Names). */
const LABEL_BY_DEVNAME: Record<string, string> = {
  HowToAnfrage: 'How-to / Anfrage',
  RechnungAbrechnung: 'Rechnung / Abrechnung',
  TechnischerFehler: 'Technischer Fehler',
  Produktqualitaet: 'Produktqualität',
  ProzessAbhaengigkeit: 'Prozess-/Abhängigkeit',
  Systeminstabilitaet: 'Systeminstabilität',
  KeinFehlerKeineMassnahme: 'Kein Fehler / Keine Massnahme',
};

/** Liest die Tabelle aus dem Report-Frame: Map Label->Zahl + gesamt. */
async function readReportTable(frame: Frame): Promise<{ rows: Map<string, number>; totalRow: number }> {
  const rows = new Map<string, number>();
  // Gruppen-Zeilen: erste Zelle = Label (mit aria Drill-Down-Suffix), letzte = Zahl
  const tds = frame.locator('table tbody tr');
  const n = await tds.count();
  let totalRow = -1;
  for (let i = 0; i < n; i++) {
    const cells = tds.nth(i).locator('td, th');
    const cnt = await cells.count();
    if (cnt < 2) continue;
    const label = ((await cells.nth(0).innerText().catch(() => '')) || '').trim();
    const value = ((await cells.nth(cnt - 1).innerText().catch(() => '')) || '').trim().replace(/[^0-9]/g, '');
    if (!value) continue;
    if (label.toLowerCase() === 'total') {
      totalRow = parseInt(value, 10);
    } else {
      // Label in der UI trägt einen "unchecked, Select row for Drill Down.-" Suffix — das Label vorne rausziehen
      const clean = label.split(', uncheck')[0].split(', unchecked')[0].trim();
      rows.set(clean, parseInt(value, 10));
    }
  }
  return { rows, totalRow };
}

/** Wartet, bis der Total-Wert in der Report-Tabelle einen neuen, stabilen
 *  Wert annimmt (Report neulädt sich nach Filterwechsel). */
async function waitForNewTotal(frame: Frame, previous: number, timeoutMs = 45000): Promise<number> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const { totalRow } = await readReportTable(frame).catch(() => ({ rows: new Map(), totalRow: -1 }));
    if (totalRow !== -1 && totalRow !== previous) return totalRow;
    if (Date.now() > deadline) throw new Error(`Report-Tabelle bleibt bei Total=${previous} — Filterwechsel wirkte nicht sichtbar`);
    await frame.waitForTimeout(1500);
  }
}

test.describe('[SCRUM-434] AC4 Zeitraumfilter', () => {
  test('Report rendert je Ursache, Zeitraumfilter 90->30 Tage wirkt', async ({ page }) => {
    test.setTimeout(240000);

    // 0) Ground-Truth aus der Org (Zielsystem, nicht Report)
    const g90 = soqlClosedByUrsache(90);
    const g30 = soqlClosedByUrsache(30);
    console.log(`GROUND-TRUTH 90T: total=${g90.total} by=${JSON.stringify(g90.byUrsache)}`);
    console.log(`GROUND-TRUTH 30T: total=${g30.total} by=${JSON.stringify(g30.byUrsache)}`);
    // Voraussetzung für einen trennscharfen Test: die zwei Perioden müssen
    // unterschiedlich ausfallen — sonst beweist der Filterwechsel nichts.
    expect(g90.total, 'AC4 Trennschärfe: 90T- und 30T-Mengen müssen sich unterscheiden').not.toBe(g30.total);

    // 1) Report öffnen
    await page.goto(`/lightning/r/Report/${REPORT_ID}/view`, {
      waitUntil: 'domcontentloaded', timeout: 60000,
    });
    let frame: Frame | undefined;
    const deadline = Date.now() + 60000;
    for (;;) {
      frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
      if (frame) break;
      if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) nicht aufgetaucht');
      await page.waitForTimeout(500);
    }
    await frame.waitForLoadState('domcontentloaded').catch(() => {});
    const frameF = frame as Frame;
    // Report-Tabelle ist da, wenn die erste Datenzeile rendert
    expect
      .poll(async () => {
        const t = frameF.locator('table tbody tr');
        return (await t.count()) > 0;
      }, { timeout: 60000 })
      .toBe(true, 'Report-Tabelle rendert keine Zeilen innerhalb 60s');

    // 2) Ausgangszustand: Standardfilter "Last 90 Days"
    const label90 = await frameF.locator('li.sectionable-table-row', { hasText: /Date\/Time Closed/ }).first().innerText().catch(() => '');
    expect(label90, 'Zeitfilter zeigt zu Beginn Last 90 Days').toMatch(/Last 90 Days/);

    const first = await readReportTable(frameF);
    expect(first.totalRow, `Report-Total (90T) muss SOQL-Trennschärfe ${g90.total} treffen`).toBe(g90.total);

    // Nicht-leere Gruppen müssen exakt die SOQL-Zahl treffen
    for (const [devName, count] of Object.entries(g90.byUrsache)) {
      if (devName === '(leer)') continue;
      const label = LABEL_BY_DEVNAME[devName] ?? devName;
      expect(first.rows.get(label) ?? -1, `90T: Gruppe ${label} muss ${count} haben`).toBe(count);
    }
    // Leere Ursache: UI zeigt '-' als Zeilen-Head
    const emptyCount90 = g90.byUrsache['(leer)'] ?? 0;
    if (emptyCount90 > 0) {
      expect(first.rows.get('-') ?? -1, `90T: Leer-Gruppe (-) muss ${emptyCount90} haben`).toBe(emptyCount90);
    }

    // 3) Zeitraumfilter umschalten: 90 -> 30 Tage
    await frameF.locator('button.action-bar-action-toggleFilter').first().click({ timeout: 20000 });
    await page.waitForTimeout(1500);
    // Zeile anklicken, um die Zeilenbearbeitung (Date/Range-Wahl) zu öffnen
    await frameF.locator('li.sectionable-table-row', { hasText: /Date\/Time Closed/ }).first().click({ timeout: 20000 });
    await page.waitForTimeout(2500);
    // Range-Listbox öffnen und WARTEN, bis sie sichtbar ist (aria-expanded / Option vorhanden)
    const rangeInput = frameF.locator('div.custom-range-picklist input.slds-combobox__input').first();
    await rangeInput.click({ timeout: 20000 });
    await expect
      .poll(
        async () => frameF.locator('[role=option]').count(),
        { timeout: 30000, message: 'Range-Listbox öffnet nicht — keine [role=option] sichtbar' },
      )
      .toBeGreaterThan(0);
    // "Last 30 Days" wählen (Monat).
    // VERIFIZIERT 2026-09-30 (probe11): Der Frame trägt 58 [role=option] aus
    // mehreren Listboxen (Range + geschlossene Comboboxen). Ein anchorierter
    // Regex (/^Last 30 Days$/) matcht dort 0 Treffer, der Substring matcht
    // genau 1 — und der Klick auf diesen setzt den Inputwert.
    await frameF.locator('[role=option]', { hasText: 'Last 30 Days' }).first().click({ timeout: 15000 });
    // Wert des Range-Input nach dem Klick — positive Verifikation des Wechsel
    const rangeValue = await frameF.locator('div.custom-range-picklist input.slds-combobox__input').first().inputValue();
    expect(rangeValue, 'Range-Input trägt nach Klick "Last 30 Days"').toBe('Last 30 Days');
    await page.waitForTimeout(1000);
    // Apply im Filter-Dialog
    await frameF.locator('button.filter-apply').first().click({ timeout: 15000 });
    await page.waitForTimeout(2000);

    // 4) Filter muss sichtbar "Last 30 Days" tragen (beweist, dass der
    //    Wechsel in der UI stattgefunden hat, nicht nur dass Zahlen anders sind)
    const label30 = await frameF
      .locator('li.sectionable-table-row', { hasText: /Date\/Time Closed/ })
      .first()
      .innerText()
      .catch(() => '');
    expect(label30, 'Zeitfilter zeigt nach Wechsel Last 30 Days').toMatch(/Last 30 Days/);

    // 5) Neue Total-Zeile: Report neulädt sich. Warten bis der Wert wechselt.
    const newTotal = await waitForNewTotal(frameF, first.totalRow);
    const after = await readReportTable(frameF);
    expect(after.totalRow, `Report-Total nach 30T-Umschaltung muss SOQL-Zahl ${g30.total} treffen`).toBe(g30.total);
    expect(newTotal, 'Total-Wert muss sich beim Filterwechsel verändert haben').not.toBe(first.totalRow);

    // Nicht-leere Gruppen nach Umschaltung
    for (const [devName, count] of Object.entries(g30.byUrsache)) {
      if (devName === '(leer)') continue;
      const label = LABEL_BY_DEVNAME[devName] ?? devName;
      const seen = after.rows.get(label) ?? 0;
      expect(seen, `30T: Gruppe ${label} muss ${count} haben`).toBe(count);
    }
  });
});
