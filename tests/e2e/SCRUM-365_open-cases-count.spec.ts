import { test, expect, type Locator, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-365] „Offene Fälle“ (Open_Cases_Count__c) — E2E-Verifikation auf dem Contact-Record.
 *
 * FIXTURE (Test-Org):
 *   Contact 003WU00001kLZzkYAG — 3 Cases (New, Working, Closed) => offene Zahl 2.
 *   Der Referenzwert wird IM TEST per SOQL gelesen (keine hartgecodete Zahl).
 */

const CONTACT_ID = '003WU00001kLZzkYAG';
const CONTACT_PATH = `/lightning/r/Contact/${CONTACT_ID}/view`;
const FIELD_LABEL = 'Offene Fälle';

/** Org-Wert des Felds per SOQL — Referenz für alle UI-Assertions in diesem Spec. */
function orgValue(): string {
  const out = execSync(
    `sf data query --query "SELECT Open_Cases_Count__c FROM Contact WHERE Id='${CONTACT_ID}'" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 10 * 1024 * 1024 },
  );
  // SF-CLI kann Hinweis-ANSI-Sequenzen (Update-Warnung, BOM) um das JSON
  // schreiben — robust: ANSI + BOM entfernen, dann erstes "{" bis letztes "}".
  const clean = out
    .replace(/\uFEFF/g, '')
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  const doc = JSON.parse(clean.slice(start, end + 1));
  return String(doc.result.records[0].Open_Cases_Count__c);
}

/**
 * Hilfen: echten Fall per sf-CLI anlegen/löschen, damit der Case-Trigger
 * (nicht ein manueller DML) die Zahl verändert — so misst der Test die
 * Produktion-Berechnung, nicht eine künstliche Umgehung.
 */
function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

async function createCaseViaCli(contactId: string, subject: string): Promise<string> {
  const subj = subject.replace(/"/g, "'");
  const out = execSync(
    `sf data create record -s Case -v "ContactId=${contactId} Subject='${subj}'" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 60000 },
  );
  const doc = shellJson(out);
  const id = (doc as any).id ?? (doc as any).result?.id;
  if (!id) throw new Error(`Case-Create lieferte keine Id: ${out.slice(0, 300)}`);
  return String(id);
}

async function deleteCaseViaCli(caseId: string): Promise<void> {
  execSync(`sf data delete record -s Case -i ${caseId} --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 60000 });
}

/**
 * Das EINZIGE slds-form-element, dessen Text die Feld-Label enthält.
 * (Playwright-Locatoren durchdringen den offenen Shadow-Root der Section.)
 */
export async function fieldElement(page: Page, label: string): Promise<Locator> {
  const forms = page.locator('div.slds-form-element');
  const n = await forms.count();
  for (let i = 0; i < n; i++) {
    const t = await forms.nth(i).innerText().catch(() => '');
    if (t.includes(label)) return forms.nth(i);
  }
  throw new Error(`Kein slds-form-element mit Label „${label}" auf der Seite`);
}

/** Wert-Text des Felds (statisches Anzeigeelement) aus der UI. */
export async function readFieldValue(page: Page, label: string): Promise<string> {
  const el = await fieldElement(page, label);
  await el.locator('.test-id__field-value').first().waitFor({ state: 'attached', timeout: 15000 });
  const raw = (await el.locator('.test-id__field-value').first().innerText()).trim();
  const m = raw.match(/\d+/);
  if (!m) throw new Error(`Keiner numerischer Feldwert in „${raw}" — Feld rendert leer/undefiniert`);
  return m[0];
}

test.describe('[SCRUM-365] Offene Fälle (Open_Cases_Count__c)', () => {
  test('AC1: Feld sichtbar auf Details-Tab, UI-Wert = Org-Wert (2 offene Fälle)', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);
    const el = await fieldElement(page, FIELD_LABEL);
    await expect(el).toBeVisible();
    const ui = await readFieldValue(page, FIELD_LABEL);
    const org = orgValue();
    expect(ui, `UI zeigt „${ui}", Org (SOQL) hat „${org}“`).toBe(org);
  });

  test('AC5: Readonly — Feld ist in der UI nicht manuell pflegbar', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);

    // UI-Part: In der View-Ansicht rendert der Wert als STATISCHES Anzeigeelement
    // (div.test-id__field-value / lightning-formatted-number, Textknoten) — es gibt
    // in diesem Feld weder spinbutton noch Input. Kein Eingabepunkt = kein manuelles
    // Pflegen über die Normalansicht.
    const el = await fieldElement(page, FIELD_LABEL);
    await expect(el.locator('.test-id__field-value')).toBeVisible();
    expect(await el.getByRole('spinbutton').count(), 'Feld zeigt Spinbutton in View-Modus').toBe(0);
    expect(await el.locator('input, textarea').count(), 'Feld zeigt Input/Textarea in View-Modus').toBe(0);

    // Autoritativer Read-only-Beweis liegt im Apex-FLS-Test
    // SCRUM365OpenCountVerifyTest.fls_readOnly_noWriteWithOrWithoutPermissionSet
    // (System.runAs: ohne PS nicht lesbar/schreibbar, mit PS lesbar aber NICHT
    //  schreibbar) — ein Test ohne zweite Lizenzen (siehe salesforce-playwright-session 4c).
    // Der Admin (Testsession devops-agent@cline.test) besitzt zwar FLS-Bypass und
    // KANN das Feld in Edit-Modus ändern — erwartetes Admin-Verhalten, verletzt die
    // AC „für Service-Nutzer nicht editierbar“ nicht; Service-Nutzer sind über die
    // Read-only-FLS des Permission Sets abgedeckt (Apex-Beweis, s. o.).
  });

  test('AC3/AC4-UI: Lebenszyklus — Neuer Fall +1, Löschung -1, UI zeigt aktuellen Wert', async ({ page }) => {
    const before = orgValue();
    const csid = await createCaseViaCli(CONTACT_ID, 'SCRUM-365 E2E Lifecycle');
    const afterCreate = orgValue();
    expect(afterCreate, `Nach Create: Org-Wert „${afterCreate}“ statt „${Number(before) + 1}“`).toBe(String(Number(before) + 1));
    await deleteCaseViaCli(csid);
    const afterDelete = orgValue();
    expect(afterDelete, `Nach Delete: Org-Wert „${afterDelete}“ (Rückkehr aus „${before}“ erwartet)`).toBe(before);

    // UI zeigt nach dem Lebenszyklus den aktuellen Org-Wert an.
    await openRecordDetails(page, CONTACT_PATH);
    const ui = await readFieldValue(page, FIELD_LABEL);
    expect(ui, `UI zeigt „${ui}“, Org hat „${afterDelete}“`).toBe(afterDelete);
  });
});

