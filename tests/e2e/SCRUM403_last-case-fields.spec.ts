/**
 * [SCRUM-403] Letztes Anliegen (Last_Case_Date__c) + Wie lange her
 * (Time_Since_Last_Case__c) — Tester E2E, Test-Org.
 *
 * Scope (Architect, Jira 17090): AC 8 Lightning-Record-View, AC 2/3 Live-Nachschauen,
 * AC 7 UI read-only. AC 1/4/5/6 sind Apex-Tests (SCRUM403LastCaseDateTest), nicht E2E.
 *
 * Konventionen (SCRUM-394): execFileSync ohne Shell, FORCE_COLOR=0 (Playwright-Worker
 * setzt sonst ANSI-Codes in den JSON-Output und der totalSize-Regex stirbt).
 * Session: frontdoor.jsp globalSetup, baseURL aus org.ts (nie hardcoded).
 * Lightning: nie networkidle; waitForSelector + explizits Locator.
 *
 * Fixtures (echte Org-Kontakte, keine DML — Case.CreatedDate nicht per DML setzbar):
 *   003WU00001VrdqWYAR "Pat Stumuller"  Last_Case_Date__c = NULL   -> beide Felder leer (AC 2)
 *   003WU00001VrdqTYAR "Rose Gonzalez"  populated                 -> AC 1 value
 *   003WU00001kYIVsYAO "ProbeCount"     populated                 -> AC 1 value (2. Beispiel)
 */
import { test, expect } from '@playwright/test';
import { execFileSync } from 'child_process';
import * as processRef from 'process';
import { openRecordDetails } from './record-page';

const sfOpts = {
  encoding: 'utf8',
  stdio: ['pipe', 'pipe', 'pipe'] as const,
  maxBuffer: 16 * 1024 * 1024,
  env: { ...processRef.env, FORCE_COLOR: '0', NO_COLOR: '1' },
};

function sfRaw(args: string[]): string {
  try {
    return execFileSync('sf', args, sfOpts) as string;
  } catch {
    return '';
  }
}
// totalSize aus dem --json-Output. Regler: -o Test-Org liefet {status,result:{totalSize}} —
// der erste totalSize-Wert wird regexbasiert gelesen (funktioniert für beide Shapes).
function soqlCount(q: string): number {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', q, '--json']);
  const m = out.match(/"totalSize"\s*:\s*(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}
function soqlRecords<T = any>(q: string): T[] {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', q, '--json']);
  const clean = out.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');
  try {
    const j = JSON.parse(clean);
    return (j?.result?.records ?? j?.records ?? []) as T[];
  } catch {
    return [];
  }
}

interface Fixture {
  id: string;
  hasCase: boolean;
  lastCaseDate?: string; // ISO yyyy-mm-dd
  timeSince?: string; // e.g. "vor 2 Monaten"
}
let fixtures: Fixture[] = [];

test.beforeAll(() => {
  const recs = soqlRecords<{
    Id: string;
    Name: string;
    Last_Case_Date__c: string | null;
    Time_Since_Last_Case__c: string | null;
  }>(
    "SELECT Id, Name, Last_Case_Date__c, Time_Since_Last_Case__c FROM Contact WHERE Id IN ('003WU00001VrdqWYAR','003WU00001VrdqTYAR','003WU00001kYIVsYAO')"
  );
  expect(recs.length, `expected 3 fixture contacts in the org, got ${recs.length}`).toBe(3);
  const byId: Record<string, (typeof recs)[number]> = Object.fromEntries(recs.map((r) => [r.Id, r]));

  // NULL-Fixture (AC 2): Last_Case_Date__c muss null sein.
  const pat = byId['003WU00001VrdqWYAR'];
  expect(pat.Last_Case_Date__c, 'Pat Stumuller muss einen NULL-Feld-Wert haben (Neukunde, kein Case)').toBeNull();
  fixtures.push({ id: pat.Id, hasCase: false });

  for (const id of ['003WU00001VrdqTYAR', '003WU00001kYIVsYAO']) {
    const r = byId[id];
    expect(r.Last_Case_Date__c, `${r.Name} muss einen befüllten Wert haben`).not.toBeNull();
    fixtures.push({ id: r.Id, hasCase: true, lastCaseDate: r.Last_Case_Date__c!, timeSince: r.Time_Since_Last_Case__c ?? undefined });
  }
});

// "Hat dieses Feld eine Wert-Zeile?" Lightning rendert pro Feld: Label-Element,
// dann Wert-Element (oder "Edit"-Chevron bei empt­y‑editable), dann das nächste Feld.
// → Die Wert-Zeile ist ALSO IMMER line+1, falls sie existiert. Ein Feld ist leer,
// wenn line+1 NICHT die Wert-Form des Feldes hat (sondern Chevron / anderes Label).
// Wert-Form pro Feld:
//   Last_Case_Date__c  -> dd.mm.yyyy (Org-Locale deutsch)
//   Time_Since_Last_Case__c -> "heute" | "gestern" | "vor N Tagen|Monaten|Jahren"
async function hasValueLine(page: any, label: string, valueRe: RegExp): Promise<boolean> {
  await expect(page.getByText(label, { exact: true }).first()).toBeVisible({ timeout: 15000 });
  const txt = await page.locator('body').innerText();
  const lines = txt.split('\n').map((l: string) => l.trim()).filter((l: string) => l.length > 0);
  const idx = lines.indexOf(label);
  if (idx === -1) return false;
  const next = lines[idx + 1];
  return next !== undefined && valueRe.test(next);
}
const DATE_RE = /^\d{2}\.\d{2}\.\d{4}$/;
const DURATION_RE = /^(heute|gestern|vor \d+ (Tagen|Monaten|Jahren))$/;
const ANY_FORMULA_RE = /^(heute|gestern|vor \d+ (Tagen|Monaten|Jahren))$/;

// ─── AC 2: Kontakt ohne Anliegen → beide Felder LEER (kein "heute", keine "0") ──
test('AC2: contact without any case shows BOTH fields empty (UI)', async ({ page }) => {
  const nullFix = fixtures.find((f) => !f.hasCase)!;
  await openRecordDetails(page, `/lightning/r/Contact/${nullFix.id}/view`);

  await expect(page.getByText('Letztes Anliegen', { exact: true }).first()).toBeVisible({ timeout: 15000 });
  await expect(page.getByText('Wie lange her', { exact: true }).first()).toBeVisible({ timeout: 15000 });

  expect(await hasValueLine(page, 'Letztes Anliegen', DATE_RE), 'Letztes Anliegen muss leer rendern (keine Datums-Zeile)').toBe(false);
  expect(await hasValueLine(page, 'Wie lange her', DURATION_RE), 'Wie lange her muss leer rendern (keine Dauer-Zeile)').toBe(false);

  // Kein Formel-Text ("heute"/"gestern"/"vor N …") irgendwo — ein frischer Kontakt
  // darf nicht aussehen, als hätte er gerade ein Anliegen.
  const formulaTexts = await page
    .locator('body')
    .getByText(/^heute$|^gestern$|^vor \d+ (Tagen|Monaten|Jahren)/)
    .count();
  expect(formulaTexts, 'kein Formel-Dauer-Text für einen Kontakt ohne Case').toBe(0);
});

// ─── AC 1 (Wert-Check in der UI): Datum + Dauer zusammen, live aus der Org gelesen.
test('AC1 value: Last_Case_Date__c + Time_Since_Last_Case__c render together with live values', async ({ page }) => {
  for (const fx of fixtures.filter((f) => f.hasCase)) {
    await openRecordDetails(page, `/lightning/r/Contact/${fx.id}/view`);
    const [yyyy, mm, dd] = fx.lastCaseDate!.split('-');
    const expectedDate = `${dd}.${mm}.${yyyy}`; // Org-Locale deutsch: DD.MM.YYYY

    await expect(page.getByText('Letztes Anliegen', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('Wie lange her', { exact: true }).first()).toBeVisible({ timeout: 15000 });

    await expect(page.getByText(expectedDate, { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.locator('body').getByText(fx.timeSince!, { exact: true }).first()).toBeVisible({ timeout: 15000 });
  }
});

// ─── AC 7 (UI): beide Felder rendern als statischer Text (kein Form-Input).
// Zeitformel-Feld ist für JEDEN read-only (updateable=false, UI-API verifiziert).
// Datumsfeld: Admin-Sitzung zeigt updateable=true (Profil gewährt Modify; das PS ist
//   additive und kann es nicht streichen) — das ist KEIN Defekt. Der eigentliche
//   "niemand ändert manuell"-Beweis für Service-User ist der Apex-FlsTest
//   (System.runAs, Standard-User ohne/mit PS: isUpdateable false in beiden Fällen).
test('AC7 UI: neither field renders as an editable form input', async ({ page }) => {
  const fx = fixtures.filter((f) => f.hasCase)[0]!;
  await openRecordDetails(page, `/lightning/r/Contact/${fx.id}/view`);

  const anlInput = await page.getByLabel('Letztes Anliegen').count();
  const wieInput = await page.getByLabel('Wie lange her').count();
  expect(anlInput, `'Letztes Anliegen' darf kein Form-Input in der View-Ansicht sein`).toBe(0);
  expect(wieInput, `'Wie lange her' (Formel) darf kein Form-Input sein`).toBe(0);
});

// ─── AC 2/3 (Daten-Ebene, SOQL über Test-Org): Set-Equality statt Spot-Zahlen.
// Beweisführung: (a) jeder Kontakt mit ≥1 Case ist befüllt, (b) jeder NULL-Kontakt
// hat 0 Cases, (c) beides zusammen = die Gesamtpopulation. Das fängt einen
// übersehenen Kontakt mit Case (AC3-Lücke) UND einen falschen Wert (AC2-Lücke).
test('AC2/3 data-level: populated set with-cases, NULL set has 0 cases, set identity', () => {
  const total = soqlCount('SELECT Id FROM Contact');
  const populated = soqlCount('SELECT Id FROM Contact WHERE Last_Case_Date__c != null');
  const nullContacts = soqlCount('SELECT Id FROM Contact WHERE Last_Case_Date__c = null');
  const withCase = soqlCount('SELECT ContactId FROM Case WHERE ContactId != null GROUP BY ContactId');

  expect(total, 'SOQL total failed').toBeGreaterThan(0);
  expect(populated + nullContacts, 'populated + null muss totalContacts ergeben').toBe(total);

  // AC2: Kontakt mit NULL-Feld, der ABER einen Case hat (Verteilungs-Fehler) = 0.
  const nullButHasCase = soqlCount(
    'SELECT Id FROM Contact WHERE Last_Case_Date__c = null AND Id IN (SELECT ContactId FROM Case)'
  );
  expect(nullButHasCase, 'AC2: kein NULL-Kontakt darf einen Case haben (Neukunde muss leer bleiben)').toBe(0);

  // AC3: Kontakt mit befülltem Feld, der ABER keinen Case hat (falsche Wert-Quelle) = 0.
  const populatedNoCase = soqlCount(
    'SELECT Id FROM Contact WHERE Last_Case_Date__c != null AND Id NOT IN (SELECT ContactId FROM Case)'
  );
  expect(populatedNoCase, 'AC3: kein befüllter Kontakt darf ohne Case sein (Datum kommt nur von einem echten Case)').toBe(0);

  // Set-Identität: Anzahl der Kontakte mit Case == Anzahl der befüllten Kontakte.
  expect(populated, `AC3: jede Kontakt-mit-Case ist befüllt (populated=${populated}, withCase=${withCase})`).toBe(withCase);
});
