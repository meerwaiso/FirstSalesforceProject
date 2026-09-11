/**
 * [SCRUM-408] Prod-Backport — Test-Org E2E gegen die Ziel-Layout-Zustände.
 *
 * Scope (Architect-Design docs/SCRUM-408-design.md, Jira 17838): das Ziel-Layout
 * (PR #92) erweitert die Sektion "Offene Faelle" um Betreuungsstufe__c,
 * Last_Case_Date__c, Time_Since_Last_Case__c. In der Test-Org ist die
 * Ziel-Zustands-Äquivalenz für die Sektion erfüllt (AC-T1/Layout-Konformität
 * gegen das Live-Prod-Ziel statisch verifiziert) — dieser Spec beweist, dass
 * die Sektion mit allen Feldern im Lightning-UI rendert (S3/AC-T6) und dass
 * SCRUM-405-AC7 (Telefonnummer der Firma) parallel intakt bleibt.
 *
 * Test-Org = Ziel-Layout für die Felder der Sektion (Retrieved 2026-09-11:
 * 58 layoutItems wie das Ziel-Layout; nur die Prod-spezifischen
 * platformActionList/summaryLayout-Blöcke fehlen, die für das Feld-Rendering
 * irrelevant sind).
 *
 * Fixtures (echte Kontakte, Werte via Live-SOQL abgefragt — nicht hardcoded,
 * damit TODAY()-tickende Felder nie hart assertet werden):
 *   003WU00001VrdqaYAB "Stella Pavlova"  Open_Cases_Count=1  -> Betreuungsstufe "normal"
 *   003WU00001VrdqTYAR "Rose Gonzalez"   Open_Cases_Count=0  -> Betreuungsstufe "keine"
 *
 * Konventionen (SCRUM-403/394): execFileSync ohne Shell, FORCE_COLOR=0/NO_COLOR=1
 * (Playwright-Workers setzen ANSI-Codes in den JSON-Output), Session via
 * globalSetup (frontdoor.jsp), never networkidle.
 */
import { test, expect } from '@playwright/test';
import { execFileSync } from 'child_process';
import * as processRef from 'process';
import { openRecordDetails, expectFieldVisible } from './record-page';

const sfOpts = {
  encoding: 'utf8',
  stdio: ['pipe', 'pipe', 'pipe'] as const,
  maxBuffer: 16 * 1024 * 1024,
  env: { ...processRef.env, FORCE_COLOR: '0', NO_COLOR: '1' },
};

interface OffeneFaelleFixture {
  id: string;
  name: string;
  offeneFaelle: number;
  betreuungsstufe: string; // Formel-Wert (Text): keine/normal/hoch
  lastCaseDate: string | null; // ISO
  timeSince: string | null; // "vor 2 Monaten" etc.
  firmenTelefon: string | null; // SCRUM-405: Account.Phone
}

function soqlRecords<T = any>(q: string): T[] {
  const out = execFileSync('sf', ['data', 'query', '-o', 'Test-Org', '-q', q, '--json'], sfOpts) as string;
  const clean = out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');
  const j = JSON.parse(clean);
  return (j?.result?.records ?? j?.records ?? []) as T[];
}

const STELLA = '003WU00001VrdqaYAB'; // 1 offener Fall -> "normal"
const ROSE = '003WU00001VrdqTYAR'; // 0 offene Fälle -> "keine"

let fixtures: Record<string, OffeneFaelleFixture> = {};

test.beforeAll(async () => {
  // Live-Werte abfragen (Wahrheit), damit das UI-Rendering gegen den
  // IST-Zustand geprüft wird statt gegen eingebackene Konstanten.
  const rows = soqlRecords<{
    Id: string;
    Name: string;
    Open_Cases_Count__c: number;
    Betreuungsstufe__c: string;
    Last_Case_Date__c: string | null;
    Time_Since_Last_Case__c: string | null;
    Firmen_Telefonnummer__c: string | null;
  }>(
    `SELECT Id, Name, Open_Cases_Count__c, Betreuungsstufe__c, Last_Case_Date__c,
     Time_Since_Last_Case__c, Firmen_Telefonnummer__c
     FROM Contact WHERE Id IN ('${STELLA}','${ROSE}')`
  );
  expect(rows, 'Stella Pavlova und Rose Gonzalez müssen existieren').toHaveLength(2);
  for (const r of rows) {
    fixtures[r.Id] = {
      id: r.Id,
      name: r.Name,
      offeneFaelle: r.Open_Cases_Count__c,
      betreuungsstufe: r.Betreuungsstufe__c,
      lastCaseDate: r.Last_Case_Date__c,
      timeSince: r.Time_Since_Last_Case__c,
      firmenTelefon: r.Firmen_Telefonnummer__c,
    };
  }
});

/**
 * S3 / AC-T6: Sektion "Offene Faelle" rendert im Lightning-UI mit den
 * 408-Feldern — Betreuungsstufe inkl. korrekt berechnetem Formelwert
 * (1 offene Fall -> "normal"), neben Last_Case_Date + Time_Since_Last_Case.
 */
test('S3: Offene-Faelle-Sektion rendert mit Betreuungsstufe + Last_Case_Date + Time_Since (Stella, 1 Fall -> "normal")', async ({ page }) => {
  const fx = fixtures[STELLA];
  expect(fx.betreuungsstufe, 'Voraussetzung: Formel muss 1 open case -> "normal" rechnen').toBe('normal');
  expect(fx.timeSince).not.toBeNull();

  await openRecordDetails(page, `/lightning/r/Contact/${fx.id}/view`);

  // Die Sektion + ihre Felder müssen rendern.
  await expectFieldVisible(page, 'Offene Fälle');
  await expectFieldVisible(page, 'Betreuungsstufe');
  await expectFieldVisible(page, 'Letztes Anliegen');
  await expectFieldVisible(page, 'Wie lange her');

  // Werte: Formel + Formula-Feld live gegen SOQL.
  await expect(page.locator('body').getByText(fx.betreuungsstufe, { exact: true }).first(),
    `Betreuungsstufe must render live value "${fx.betreuungsstufe}"`).toBeVisible({ timeout: 15000 });
  await expect(page.locator('body').getByText(fx.timeSince!, { exact: true }).first(),
    `Time_Since_Last_Case must render live value "${fx.timeSince}"`).toBeVisible({ timeout: 15000 });
  if (fx.lastCaseDate) {
    const dd = fx.lastCaseDate.split('-');
    const deDate = `${dd[2]}.${dd[1]}.${dd[0]}`; // Org-Locale Deutsch: dd.mm.yyyy
    await expect(page.locator('body').getByText(deDate, { exact: true }).first(),
      `Last_Case_Date must render as ${deDate}`).toBeVisible({ timeout: 15000 });
  }
});

/**
 * S3 (Formel-Eckwerte): 0 offene Fall -> Betreuungsstufe "keine" rendert
 * ebenfalls (leer/NULL ist KEIN Zustand-Verlust — die Formel liefert einen
 * Text-Wert).
 */
test('S3: Betreuungsstufe rendert Formelwert "keine" bei 0 offenen Fällen (Rose)', async ({ page }) => {
  const fx = fixtures[ROSE];
  expect(fx.offeneFaelle).toBe(0);
  expect(fx.betreuungsstufe).toBe('keine');

  await openRecordDetails(page, `/lightning/r/Contact/${fx.id}/view`);

  await expectFieldVisible(page, 'Betreuungsstufe');
  await expect(page.locator('body').getByText('keine', { exact: true }).first(),
    'Betreuungsstufe "keine" muss rendern (0 offene Fälle)').toBeVisible({ timeout: 15000 });
});

/**
 * SCRUM-405 AC7-Regression (S3 verlangt explizit: "Betreuungsstufe__c AND
 * Firmen_Telefonnummer__c werden gerendert"): das 405-Feld rendert parallel
 * mit korrektem Wert (= Account.Phone) — in beiden Fällen, wo die Firma
 * existiert (Rose = Edge Comms, (512) 757-6000).
 */
test('S3: Telefonnummer der Firma rendert parallel (SCRUM-405-AC7-Regression)', async ({ page }) => {
  const fx = fixtures[ROSE];
  expect(fx.firmenTelefon, 'Voraussetzung: Rose muss eine Firmennummer via Account haben').not.toBeNull();

  await openRecordDetails(page, `/lightning/r/Contact/${fx.id}/view`);

  await expectFieldVisible(page, 'Telefonnummer der Firma');
  await expect(page.locator('body').getByText(fx.firmenTelefon!, { exact: true }).first(),
    `Telefonnummer der Firma must render "${fx.firmenTelefon}"`).toBeVisible({ timeout: 15000 });
});
