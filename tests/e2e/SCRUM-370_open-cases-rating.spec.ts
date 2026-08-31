import { test, expect, type Locator, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-370] „Einstufung Offene Fälle" (Open_Cases_Rating__c) +
 * Listenansicht „Kritische Kontakte" — E2E-Verifikation (Playwright-Teilsatz).
 *
 * Scope (Architect-Handoff, Jira-Comment 14799): Playwright E2E für
 *   - AK6-UI : Feld in der UI sichtbar (mit FLS), read-only dargestellt,
 *              Wert = Org-Wert. Der Negativ-Beweis (Benutzer OHNE FLS liest
 *              nicht) läuft in der Org als Apex-Test (2/2 Lizenzen belegt,
 *              siehe salesforce-playwright-session 4c) — hier frisch
 *              re-executied: `sf apex run test -n SCRUM370OpenCasesRatingTest`.
 *   - AK7    : ListView „Kritische Kontakte" listet GENAU die Contacts mit
 *              Einstufung = Kritisch (Ground Truth per SOQL, keine
 *              hartgecodete Zahl).
 *   - AK4    : Feld Readonly auf dem Contact-Layout direkt neben dem
 *              Zähler „Offene Fälle".
 *   - AK2/3  : Live-Ableitung — neue Cases öffnen der Zähler +1, der Rating
 *              folgt der Regel-Tabelle (Grenzen inklusive), UI zeigt den
 *              aktuellen Wert.
 *
 * FIXTURE: der Test legt eigene Contact/Cases per sf-CLI an und räumt sie
 * nach dem Test auf — die Referenzwerte werden IMMER per SOQL gelesen.
 */

const FIELD_RATING_LABEL = 'Einstufung Offene Faelle'; // ASCII-Label (Feld-Label in der Org)
const FIELD_COUNT_LABEL = 'Offene Fälle';

// ── SF-CLI Helpers ────────────────────────────────────────────────────────

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function soql(soqlText: string): any {
  const out = execSync(
    `sf data query --query "${soqlText}" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 10 * 1024 * 1024 },
  );
  return shellJson(out).result;
}

function createContact(lastName: string): string {
  // Wert anführen — der -v-Parser liest unanführte Leerzeichen als neue
  // Key=Value-Paare („Malformed key=value pair for value: E2E").
  const ln = lastName.replace(/"/g, "'");
  const out = execSync(
    `sf data create record -s Contact -v "LastName='${ln}'" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000 },
  );
  const doc = shellJson(out);
  const id = doc?.id ?? doc?.result?.id;
  if (!id) throw new Error(`Contact-Create lieferte keine Id: ${out.slice(0, 300)}`);
  return String(id);
}

function createCase(contactId: string, subject: string): string {
  const subj = subject.replace(/"/g, "'");
  // Subject anführen — unanführte Leerzeichen bricht den -v-Parser
  // („Malformed key=value pair").
  const out = execSync(
    `sf data create record -s Case -v "ContactId=${contactId} Subject='${subj}'" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000 },
  );
  const doc = shellJson(out);
  const id = doc?.id ?? doc?.result?.id;
  if (!id) throw new Error(`Case-Create lieferte keine Id: ${out.slice(0, 300)}`);
  return String(id);
}

function deleteRecord(sobject: string, id: string): void {
  execSync(`sf data delete record -s ${sobject} -i ${id} --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'] });
}

const readContact = (id: string) => soql(`SELECT Open_Cases_Count__c, Open_Cases_Rating__c FROM Contact WHERE Id='${id}'`).records[0];

/**
 * Der Case-Trigger rechnet asynchron (post-commit) um — kurz nach dem
 * letzten DML ist der Org-Wert nicht garantiert gesetzt. Kurzes Polling
 * (Max. ~40s) statt fester Sleep: liefert erst zurück, wenn der Wert da ist.
 */
function awaitOrgValue(
  contactId: string,
  expectRating: string,
  timeoutMs = 40000,
): { count: number; rating: string } {
  const deadline = Date.now() + timeoutMs;
  let last = readContact(contactId);
  for (;;) {
    if (String(last.Open_Cases_Rating__c) === expectRating && last.Open_Cases_Count__c != null) {
      return { count: Number(last.Open_Cases_Count__c), rating: String(last.Open_Cases_Rating__c) };
    }
    if (Date.now() > deadline) {
      throw new Error(
        `Org-Wert wird nicht „${expectRating}“ (letztmalig: rating=${last.Open_Cases_Rating__c} count=${last.Open_Cases_Count__c})`,
      );
    }
    execSync('sleep 3', { stdio: ['pipe', 'pipe', 'pipe'] });
    last = readContact(contactId);
  }
}

const ratingByApiValue: Record<string, string> = {
  Unauffaellig: 'Unauffaellig (0)',
  Normal: 'Normal (1-2)',
  Erhoeht: 'Erhoeht (3-4)',
  Kritisch: 'Kritisch (5 oder mehr)',
};

// ── UI Helpers ────────────────────────────────────────────────────────────

/**
 * Das EINZIGE slds-form-element, dessen Text die Feld-Label enthält
 * (muss exakt sein, sonst kollidieren „Offene Fälle" und
 * „Einstufung Offene Faelle" — die Label haben keine Übereinstimmung,
 * deshalb ist contains() hier sicher. Verifiziert 2026-08-30 via Probe,
 * form[15]=Offene Fälle, form[16]=Einstufung Offene Faelle auf E2EProbe2.)
 */
async function fieldFormElement(page: Page, label: string): Promise<Locator> {
  const forms = page.locator('div.slds-form-element');
  const n = await forms.count();
  for (let i = 0; i < n; i++) {
    const t = await forms.nth(i).innerText().catch(() => '');
    if (t.split('\n')[0]?.trim() === label) return forms.nth(i);
  }
  throw new Error(`Kein slds-form-element mit exaktem Label „${label}" auf der Details-Seite`);
}

/**
 * Der Wert-Text des Felds. Picklist-Felder rendern den Vollname
 * („Kritisch (5 oder mehr)"), Zahl-Felder rendern „5". Rückgabe:
 * trimmed textContent — wer eine Zahl braucht, matcht sie selbst.
 */
async function readDisplayValue(page: Page, label: string): Promise<string> {
  const el = await fieldFormElement(page, label);
  await el.locator('.test-id__field-value').first().waitFor({ state: 'attached', timeout: 20000 });
  return (await el.locator('.test-id__field-value').first().innerText()).trim();
}

/**
 * ListView „Kritische Kontakte": direkt via /lightning/o/Contact/list?
 * filterName=Kritische_Kontakte (probe-verifizierter Pfad — die App-Nav hat
 * keine List-View-Items, der filterName-Parameter ist der dokumentierte
 * Lightning-Einstiegspunkt). Liefert nach dem Laden die sichtbaren
 * Datentabellen-Zeilen (1 Zeile pro gelistetem Contact).
 */
async function openListView(page: Page, label: string): Promise<{ header: string; rowIds: string[]; devName: string }> {
  // filterName = DEVELOPER NAME der List-View (Kritische_Kontakte aus dem
  // listView-meta.xml), nicht das Label — das Label würde die View nicht
  // laden. Probe-verifiziert 2026-08-30: /lightning/o/Contact/list?filterName=Kritische_Kontakte
  const devName = 'Kritische_Kontakte';
  await page.goto(`/lightning/o/Contact/list?filterName=${devName}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });

  // Picker-Anzeige „<label>" bestätigen — damit der View tatsächlich geladen ist
  await page.getByText(label, { exact: true }).first().waitFor({ state: 'visible', timeout: 30000 });

  // Kopfzeile der Liste: „N items • Sorted by … • Filtered by …"
  const header = (await page.getByText(/items? •/).first().innerText().catch(() => '')).trim();

  // Datenzeilen: jede Datenzeile trägt data-row-key-value = Record-Id
  // (probe-verifiziert 2026-08-30). Die Kopfzeile hat data-row-key-value="HEADER".
  // Diese View rendert nur die zwei Custom-Felder (Zähler + Einstufung) — das
  // Name-Feld steht NICHT in der Spaltenliste (list-ui-Beleg), daher ist die
  // Id die einzige zuverlässige Identifikation pro Zeile.
  const rowIds: string[] = [];
  const rows = page.locator('tr[data-row-key-value]');
  const n = await rows.count();
  for (let i = 0; i < n; i++) {
    const key = (await rows.nth(i).getAttribute('data-row-key-value').catch(() => '')) ?? '';
    if (!key || key === 'HEADER') continue; // Kopfzeile ausfiltern
    rowIds.push(key);
  }
  return { header, rowIds, devName };
}

// ── Tests ─────────────────────────────────────────────────────────────────

test.describe('[SCRUM-370] Einstufung Offene Fälle + Kritische Kontakte', () => {
  let contactId = '';
  const createdIds: { kind: 'Contact' | 'Case'; id: string }[] = [];

  test.beforeAll(() => {
    contactId = createContact('SCR370 E2E Kritisch');
    createdIds.push({ kind: 'Contact', id: contactId });
    // Live-Ableitung: 5 offene Cases per CLI => der Trigger berechnet
    // Zähler 5 und Rating Kritisch (kein manuelles DML in die Felder).
    for (let i = 1; i <= 5; i++) {
      const cid = createCase(contactId, `SCR370 e2e offen ${i}`);
      createdIds.push({ kind: 'Case', id: cid });
    }
    // Trigger-Post-Commit: erst zurück, wenn die Org Kritisch zeigt.
    awaitOrgValue(contactId, 'Kritisch');
  });

  test.afterAll(() => {
    // Aufräumen: erst Cases (referenziert vom Contact), dann Contact.
    for (const c of [...createdIds].reverse()) deleteRecord(c.kind, c.id);
  });

  test('AK7: ListView „Kritische Kontakte" listet genau die Kritisch-Contacts', async ({ page }) => {
    // Ground Truth aus der Org: alle Contacts mit Rating Kritisch.
    const groundTruth = soql(`SELECT Id, LastName FROM Contact WHERE Open_Cases_Rating__c = 'Kritisch'`).records;
    expect(groundTruth.length, 'Vorbedingung: Org enthält mindestens einen Kritisch-Contact (eigene Fixture)')
      .toBeGreaterThanOrEqual(1);

    const { rowIds, header } = await openListView(page, 'Kritische Kontakte');

    // Filter-Anzeige muss die Einstufung nennen (List-View-Filter wirksam)
    expect(header, `List-Kopf benennt keinen Filter — View nicht geladen: „${header}"`)
      .toMatch(/Einstufung Offene Faelle|Kritisch|filtered/i);

    // Genau die Ground-Truth-Contacts sind gelistet — Anzahl
    const listed = new Set(rowIds);
    expect(rowIds.length, `View zeigt ${rowIds.length} Zeilen, Org hat ${groundTruth.length} Kritisch-Contacts`)
      .toBe(groundTruth.length);

    // Jeder Kritisch-Contact (Id) ist in der View — Reihenfolge irrelevant.
    // Identifikation per Id, weil die View das Name-Feld nicht rendert.
    for (const rec of groundTruth) {
      expect(listed.has(rec.Id!), `Kritisch-Contact (${rec.Id}, „${rec.LastName}") fehlt in der View`).toBe(true);
    }
  });

  test('AK6-UI: Feld sichtbar auf Details, Wert = Org-Wert (Kritisch), read-only dargestellt', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Contact/${contactId}/view`);
    const el = await fieldFormElement(page, FIELD_RATING_LABEL);
    await expect(el).toBeVisible();

    // Read-only-Darstellung: das Feld rendert als statisches Anzeigeelement
    // — weder Picker/Input noch Spinbutton im View-Modus (derselbe
    // Nachweis wie SCRUM-365; der autoritative FLS-Beweis, dass der Wert
    // für Service-Nutzer nicht editierbar ist, liegt im Apex-FLS-Test unten).
    await expect(el.locator('.test-id__field-value')).toBeVisible();
    expect(await el.getByRole('spinbutton').count(), 'Feld zeigt Spinbutton in View-Modus').toBe(0);
    expect(await el.locator('input, textarea, select, lightning-combobox').count(), 'Feld zeigt Eingabepunkt in View-Modus').toBe(0);

    const org = readContact(contactId);
    expect(org.Open_Cases_Rating__c, 'Fixture-Check: Org hat Rating Kritisch').toBe('Kritisch');
    const ui = await readDisplayValue(page, FIELD_RATING_LABEL);
    expect(ui, `UI zeigt „${ui}", Org hat „${org.Open_Cases_Rating__c}" (Vollname: ${ratingByApiValue['Kritisch']})`)
      .toBe(ratingByApiValue[org.Open_Cases_Rating__c!]);
  });

  test('AK6-UI-Negativ: FLS-Leserecht verweigert ohne Permission Set (Apex, runAs)', async () => {
    // Der UI-Negativ-Beweis braucht einen lizenzierten Benutzer ohne FLS —
    // die Test-Org hat 2/2 Lizenzen belegt (beide Sys-Admin), folglich läuft
    // der autoritative Negativ-Test als Apex mit System.runAs(). Hier wird
    // er FRISCH executed und das Ergebnis gelesen, nicht nur zitiert.
    const out = execSync(
      'sf apex run test -n SCRUM370OpenCasesRatingTest --target-org Test-Org --synchronous --json',
      { encoding: 'utf-8', timeout: 600000, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 10 * 1024 * 1024 },
    );
    const doc = shellJson(out);
    const summary = doc.result?.summary ?? doc.summary;
    expect(summary?.outcome, `Apex-Run: ${JSON.stringify(summary)}`).toBe('Passed');
    expect(summary?.failRate, String(summary?.failing ?? '')).toBe('0%');
    const flsTest = (doc.result?.tests ?? doc.tests ?? []).find(
      (t: { FullName?: string; MethodName?: string }) =>
        (t.FullName ?? t.MethodName ?? '').includes('fls_notReadableWithoutPS_readableButNotEditableWithPS'),
    );
    expect(flsTest, 'FLS-Test fehlt im Result-Set').toBeTruthy();
    expect(flsOutcome(flsTest), 'FLS-Test-Ergebnis').toMatch(/Pass/i);
  });

  test('AK4: Layout — Rating Readonly direkt neben Zähler „Offene Fälle"', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Contact/${contactId}/view`);
    const elRating = await fieldFormElement(page, FIELD_RATING_LABEL);
    await expect(elRating).toBeVisible();
    const elCount = await fieldFormElement(page, FIELD_COUNT_LABEL);
    await expect(elCount).toBeVisible();

    // „Direkt neben": beide Felder im selben slds-form-element-Array,
    // benachbarte Indizes in derselben Layout-Sektion.
    const forms = page.locator('div.slds-form-element');
    const n = await forms.count();
    const idx: Record<string, number> = {};
    for (let i = 0; i < n; i++) {
      const t = await forms.nth(i).innerText().catch(() => '');
      const first = t.split('\n')[0]?.trim();
      if (first === FIELD_RATING_LABEL) idx.rating = i;
      if (first === FIELD_COUNT_LABEL) idx.count = i;
    }
    expect(idx.rating, 'Rating-Feld fehlt auf der Details-Seite').toBeDefined();
    expect(idx.count, 'Zähler-Feld fehlt auf der Details-Seite').toBeDefined();
    expect(Math.abs(idx.rating! - idx.count!), `Zähler bei #${idx.count} und Einstufung bei #${idx.rating} liegen nicht nebeneinander`)
      .toBe(1);
  });

  test('AK2/3 UI: live — 3 Cases offen = Erhöht, +2 offen = Kritisch, UI folgt (Grenzen inklusive)', async ({ page }) => {
    // Vorbedingung: die Haupt-Fixture (beforeAll) ist Kritisch (5 offen).
    // Hier wird ein zweiter, eigener Contact mit den Grenzwerten 3 und 5
    // gefahren: 3 offen => Erhoeht (obere Grenze AK3), danach 2 weitere
    // => 5 offen => Kritisch (untere Grenze der Regel-Tabelle).
    const c2 = createContact('SCR370 E2E Grenz');
    createdIds.push({ kind: 'Contact', id: c2 });
    const ids: string[] = [];
    try {
      for (let i = 1; i <= 3; i++) ids.push(createCase(c2, `SCR370 grenz ${i}`));
      const at3 = awaitOrgValue(c2, 'Erhoeht');
      expect(at3.count, '3 offen => Zähler 3').toBe(3);
      expect(at3.rating, '3 offen => Erhoeht (inklusive Grenze)').toBe('Erhoeht');

      ids.push(createCase(c2, 'SCR370 grenz 4'));
      ids.push(createCase(c2, 'SCR370 grenz 5'));
      const at5 = awaitOrgValue(c2, 'Kritisch');
      expect(at5.count, '5 offen => Zähler 5').toBe(5);
      expect(at5.rating, '5 offen => Kritisch (inklusive Grenze)').toBe('Kritisch');

      // UI zeigt den finalen Zustand — der Trigger hat beide Einstufungen
      // ohne jede manuelle Intervention berechnet.
      await openRecordDetails(page, `/lightning/r/Contact/${c2}/view`);
      const ui = await readDisplayValue(page, FIELD_RATING_LABEL);
      expect(ui, `UI „${ui}“ vs Org „Kritisch“`).toBe(ratingByApiValue['Kritisch']);
    } finally {
      for (const id of ids.reverse()) deleteRecord('Case', id);
      deleteRecord('Contact', c2);
      const idx = createdIds.findIndex((x) => x.id === c2);
      if (idx >= 0) createdIds.splice(idx, 1);
    }
  });
});

function flsOutcome(t: { Outcome?: string; outcome?: string }): string {
  return t.Outcome ?? t.outcome ?? '';
}
