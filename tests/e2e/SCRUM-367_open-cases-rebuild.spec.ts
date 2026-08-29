import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-367] „Offene Fälle“ — Vollkorrettur + no-Code-Reparatur + Ergebnis-Anzeige.
 *
 * AC-Abdeckung (E2E-Teil):
 *   AC1 Zähler älterer Kontakte zeigt die exakte Zahl offener Fälle
 *   AC2 Kontakt ohne Fälle zeigt 0 statt leer
 *   AC3 Korrektur wiederholbar/no-Code (WebLink deployed + live Run-Zeilen existieren)
 *   AC6 Ergebnis (Anzahl korrigierter Kontakte) in der UI sichtbar
 *
 * AC4 (parallele Bearbeitung) und AC5 (50k Skalierung) sind NICHT E2E-Acceptance:
 *   AC4 wurde live gegen die Test-Org verifiziert (während laufendem Rebuild 8/8
 *   Case-Updates erfolgreich, Batch trotzdem Abgeschlossen) + Apex
 *   SCRUM367OpenCasesRebuildTest.recompute_returnsChangedCount (No-op erzeugt
 *   keine DML); AC5 durch SCRUM367OpenCasesRebuildScaleTest (Stateful-Summe über
 *   Chunk-Grenzen). Beides steht im Jira-Kommentar mit Run-Ids.
 *
 * Fixtures werden IM TEST per SOQL aufgelöst (keine hartgecodeten Ids), weil
 * die Test-Org zwischen Läufen neue Run-Zeilen bekommt.
 */

/** Org-Werte per SOQL — Referenz für alle UI-Assertions (kein hartgecodeter Zustand). */
function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function soql(query: string): any {
  const out = execSync(`sf data query --query "${query}" --target-org Test-Org --json`, {
    encoding: 'utf-8',
    timeout: 60000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 10 * 1024 * 1024,
  });
  return shellJson(out).result.records;
}

function contactWithCounter(gte: number): string {
  const recs = soql(`SELECT Id, Open_Cases_Count__c FROM Contact WHERE Open_Cases_Count__c >= ${gte} ORDER BY LastModifiedDate DESC LIMIT 1`);
  if (recs.length === 0) throw new Error(`Kein Kontakt mit Offene_Faelle >= ${gte} gefunden — Vollkorrektur läuft noch?`);
  return recs[0].Id;
}

function contactWithZeroCounter(): string {
  const recs = soql(`SELECT Id FROM Contact WHERE Open_Cases_Count__c = 0 ORDER BY LastModifiedDate DESC LIMIT 1`);
  if (recs.length === 0) throw new Error('Kein Kontakt mit Offene_Faelle = 0 gefunden');
  return recs[0].Id;
}

function latestRun(): any {
  const recs = soql(`SELECT Id, Status__c, ContactsProcessed__c, ContactsCorrected__c FROM CaseRebuildRun__c ORDER BY CreatedDate DESC LIMIT 1`);
  if (recs.length === 0) throw new Error('Keine CaseRebuildRun__c-Runtime-Zeile in der Test-Org');
  return recs[0];
}

test.describe('[SCRUM-367] Offene Fälle — Vollkorrektur', () => {
  test('AC1: Bestands-Kontakt zeigt exakte Anzahl offener Fälle auf dem Details-Tab', async ({ page }) => {
    const id = contactWithCounter(1);
    const org = Number(soql(`SELECT Open_Cases_Count__c FROM Contact WHERE Id='${id}'`)[0].Open_Cases_Count__c);
    await openRecordDetails(page, `/lightning/r/Contact/${id}/view`);
    // Wert aus dem statischen Anzeigeelement (gleiche Technik wie SCRUM-365-Spec)
    const el = page.locator('div.slds-form-element').filter({ hasText: 'Offene Fälle' }).first();
    await expect(el, 'Feld „Offene Fälle“ nicht auf dem Details-Tab').toBeVisible({ timeout: 20000 });
    const value = el.locator('.test-id__field-value').first();
    await expect(value).toBeVisible({ timeout: 20000 });
    const ui = (await value.innerText()).trim();
    expect(ui, `UI zeigt „${ui}“, Org (SOQL) hat „${org}“`).toBe(String(org));
  });

  test('AC2: Kontakt OHNE offene Fälle zeigt 0 (nicht leer) — und kein Kontakt der Org ist mehr NULL', async ({ page }) => {
    // Org-Ebene: Vollkorrektur-Endzustand, kein einziger NULL-Zähler.
    const nulls = Number(soql(`SELECT COUNT(Id) FROM Contact WHERE Open_Cases_Count__c = null`)[0].expr0);
    expect(nulls, 'Vollkorrektur hat NULL-Zähler zurückgelassen').toBe(0);

    const id = contactWithZeroCounter();
    await openRecordDetails(page, `/lightning/r/Contact/${id}/view`);
    const el = page.locator('div.slds-form-element').filter({ hasText: 'Offene Fälle' }).first();
    await expect(el).toBeVisible({ timeout: 20000 });
    const raw = (await el.locator('.test-id__field-value').first().innerText()).trim();
    expect(raw, `Feld rendert „${raw}“ — erwartet 0, NICHT leer`).toBe('0');
  });

  test('AC3: no-Code-Auslösung deployed (WebLink + Layout-Referenz) und mindestens zwei abgeschlossene Läue in der Org', async ({ page }) => {
    // (a) WebLink-Metadaten existieren in der Org (nicht nur im Repo) — Retrieve.
    //     Die SDR-CLI liefert WebLinks als <webLinks>-Block IN der CustomObject-Datei
    //     (objects/Contact.object), als eigene webLinks/-Datei existiert.
    const fs = await import('node:fs');
    const tmp = '/tmp/scrum367_webcheck';
    fs.rmSync(tmp, { recursive: true, force: true });
    fs.mkdirSync(tmp, { recursive: true });
    execSync(
      `sf project retrieve start -o Test-Org -m "WebLink:Contact.Rebuild_Offene_Faelle" -t ${tmp}`,
      { stdio: ['pipe', 'pipe', 'pipe'], timeout: 120000 },
    );
    execSync(`unzip -o ${tmp}/unpackaged.zip -d ${tmp}/unz`, { stdio: ['pipe', 'pipe', 'pipe'] });
    const objXml = fs.readFileSync(`${tmp}/unz/unpackaged/objects/Contact.object`, 'utf-8');
    expect(
      objXml,
      'WebLink Rebuild_Offene_Faelle nicht in der Org deployed (AC3 no-Code-Trigger fehlt)',
    ).toContain('<fullName>Rebuild_Offene_Faelle</fullName>');
    expect(objXml, 'WebLink muss die Apex-Methode startRebuild aufrufen').toContain('startRebuild');
    expect(objXml).toContain('CaseOpenCountRebuilder');
    fs.rmSync(tmp, { recursive: true, force: true });

    // (b) Die Auslösung hat live funktioniert: mindestens zwei Lauf-Log-Zeilen,
    //     alle Abgeschlossen (2. Lauf = idempotente Wiederholung).
    const done = soql(`SELECT COUNT(Id) FROM CaseRebuildRun__c WHERE Status__c = 'Abgeschlossen'`);
    const doneCount = Number(done[0].expr0);
    expect(doneCount, 'Keine abgeschlossene Rebuild-Lauf-Zeile in der Test-Org').toBeGreaterThanOrEqual(2);

    // (c) UI: die Lauf-Log-Liste existiert und zeigt die neueste Lauf-Nr.
    const run = latestRun();
    const runNumber = soql(`SELECT Name FROM CaseRebuildRun__c WHERE Id='${run.Id}'`)[0].Name;
    await page.goto('/lightning/o/CaseRebuildRun__c/list', { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('.slds-global-header', { timeout: 60000 });
    await expect(
      page.getByText(runNumber, { exact: true }).first(),
      `Lauf-Nr. ${runNumber} nicht in der Liste „Korrekturlauf Offene Faelle“`,
    ).toBeVisible({ timeout: 30000 });
  });

  test('AC6: Ergebnis sichtbar — „Kontakte korrigiert“ auf der Lauf-Record-Seite (BUG: SCRUM-369 — Layout hat keine Custom Fields)', async ({ page }) => {
    const run = latestRun();
    await openRecordDetails(page, `/lightning/r/CaseRebuildRun__c/${run.Id}/view`);
    // AC6 verlangt: „die Anzahl korrigierter Kontakte ist sichtbar“.
    // Bekannter Defect (Bug-Ticket): das deplomente Layout „Korrekturlauf Offene
    // Faelle Layout“ enthält nur Name/OwnerId/CreatedById/LastModifiedById —
    // Status/Kontakte verarbeitet/Kontakte korrigiert/Abgeschlossen am fehlen.
    // Dieser Test ist die automatisierte Reproduktion und soll nach dem Fix grün werden.
    const el = page.locator('div.slds-form-element').filter({ hasText: 'Kontakte korrigiert' }).first();
    await expect(
      el,
      'AC6 verletzt: „Kontakte korrigiert“ ist auf der Lauf-Record-Seite NICHT sichtbar (Custom Fields fehlen im Layout)',
    ).toBeVisible({ timeout: 20000 });
    const raw = (await el.locator('.test-id__field-value').first().innerText()).trim();
    expect(/^\d+$/.test(raw), `„Kontakte korrigiert“ rendert nicht-numerisch: „${raw}“`).toBe(true);
  });
});
