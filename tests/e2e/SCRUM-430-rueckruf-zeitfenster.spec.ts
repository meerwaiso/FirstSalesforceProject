import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-430] E2E: Picklist "Rückruf-Zeitfenster" auf Contact in der Lightning-UI.
 *
 * Deckt die UI-Seite der Akzeptanzkriterien ab, die Apex-Tests nicht können:
 *
 *   AC2 — Feld sichtbar im Details-Tab OHNE aufklappbare Sektion (Haupt-Layout),
 *        Wert nach Belegung direkt lesbar.
 *   AC3 (UI-Seite) — Service-Nutzer öffnet einen Kontakt, ändert den Picklist-Wert
 *        über das Inline-Edit, speichert → SOQL-Read-Back bestätigt die Persistenz.
 *
 * Nicht hier abgedeckt (Apex, Hausmethode):
 *   AC1 — Wertematrix 3 Picklist-Werte, optional, Schema-Assert
 *   AC4 — Negativ-Test (Standard-User ohne PS, WITH USER_MODE → Exception)
 *
 * Picklist-DOM: Lightning rendert ein BUTTON[role=combobox] + DIV[role=listbox]
 * (beide mit aria-label "Rückruf-Zeitfenster"), daher count=2, nicht 1.
 * Empirisch verifiziert am 2026-09-25 via browser probe.
 */

const FIELD_LABEL = 'Rückruf-Zeitfenster';
const FIELD_API = 'Rueckruf_Zeitfenster__c';

// ── SF-CLI Helpers ──────────────────────────────────────────────────────

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function soql(soqlText: string): any {
  const out = execSync(
    `sf data query --query "${soqlText}" --target-org Test-Org --json`,
    {
      encoding: 'utf-8',
      timeout: 120000,
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 10 * 1024 * 1024,
      env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
    },
  );
  return shellJson(out).result;
}

let testContactId: string;

test.beforeAll(() => {
  const testTag = 'TEST-SCRUM430-E2E-' + Date.now().toString(36).toUpperCase();
  const out = execSync(
    `sf data create record -s Contact -v "LastName='${testTag}'" --target-org Test-Org --json`,
    {
      encoding: 'utf-8',
      timeout: 120000,
      env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
    },
  );
  const id = shellJson(out)?.result?.id || shellJson(out)?.id;
  if (!id) throw new Error(`Contact-Create fehlgeschlagen: ${out.slice(0, 300)}`);
  testContactId = String(id);
});

test.afterAll(() => {
  if (testContactId) {
    execSync(
      `sf data delete record -s Contact -i ${testContactId} --target-org Test-Org --json`,
      {
        encoding: 'utf-8',
        timeout: 120000,
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
      },
    );
  }
});

/** Select a picklist value and return to the view (no save yet). */
async function selectPicklistValue(page: import('@playwright/test').Page, value: string): Promise<void> {
  // Open the combobox (button) — the listbox is hidden until clicked
  const combobox = page.getByLabel(FIELD_LABEL, { exact: true }).nth(0);
  await combobox.click();
  await page.waitForTimeout(500);

  // Picklist options appear in a fixed/absolute positioned overlay
  const option = page.getByRole('option', { name: value, exact: true });
  await option.waitFor({ state: 'visible', timeout: 10000 });
  await option.click();
  await page.waitForTimeout(500);
}

// ── AC2: Feld sichtbar im Details-Tab ohne aufklappbare Sektion ─────────

test.describe('[SCRUM-430] AC2 — Sichtbarkeit in der UI', () => {

  test('Feld "Rückruf-Zeitfenster" ist auf dem Details-Tab sichtbar (kein Aufklappen nötig)', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Contact/${testContactId}/view`);

    // Das Feld-Label muss sichtbar sein — das beweist die Layout-Existenz im Details-Tab
    await expect(
      page.getByText(FIELD_LABEL, { exact: true }).first(),
      `Feld-Label "${FIELD_LABEL}" nicht auf dem Details-Tab gefunden — ` +
        `Layout-Eintrag fehlt oder das Feld wurde nicht deployed`
    ).toBeVisible({ timeout: 15000 });

    // Das Feld liegt NICHT in einer collapse section (aria-expanded=false wäre der Aufklapp-Marker):
    // Wir prüfen, dass der "Edit" Button direkt sichtbar ist ohne vorheriges Aufklappen
    const editBtn = page.getByRole('button', { name: `Edit ${FIELD_LABEL}` });
    await expect(editBtn, 'Edit-Button nicht direkt sichtbar — Feld liegt in einer aufklappbaren Sektion').toBeVisible({ timeout: 10000 });
  });

  test('Wert ist im UI sichtbar, nachdem er per SOQL gesetzt wurde', async ({ page }) => {
    // Setze den Wert direkt über sf-CLI (bypassing UI), dann prüfe UI-Sichtbarkeit
    execSync(
      `sf data update record -s Contact -i ${testContactId} -v '${FIELD_API}=Abends' --target-org Test-Org --json`,
      {
        encoding: 'utf-8',
        timeout: 120000,
        env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
      },
    );

    await openRecordDetails(page, `/lightning/r/Contact/${testContactId}/view`);

    // Der eingelesene Wert "Abends" muss im Detail-Tab im read-View sichtbar sein
    await expect(
      page.getByText('Abends', { exact: true }).first(),
      'Gewert "Abends" nicht im read-View sichtbar — Feld-Rendering kaputt oder Layout-Position falsch'
    ).toBeVisible({ timeout: 15000 });
  });
});

// ── AC3 (UI): Service editiert via Inline-Edit, Wert persistiert ─────────

test.describe('[SCRUM-430] AC3 — Inline-Edit & Persistenz', () => {

  test('Service-Nutzer wählt "Nachmittags" via Picklist, speichert, SOQL bestätigt Persistenz', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Contact/${testContactId}/view`);

    // Feld-Label muss existieren (Vorbedingung)
    await expect(page.getByText(FIELD_LABEL, { exact: true }).first()).toBeVisible({ timeout: 10000 });

    // Inline-Edit starten
    const editBtn = page.getByRole('button', { name: `Edit ${FIELD_LABEL}` });
    await editBtn.click();
    await page.waitForTimeout(800);

    // Picklist combobox ist jetzt im edit mode — Wert "Nachmittags" wählen
    await selectPicklistValue(page, 'Nachmittags');

    // Speichern
    const saveBtn = page.getByRole('button', { name: 'Save', exact: true });
    await expect(saveBtn, 'Save-Button nicht sichtbar nach Picklist-Änderung').toBeVisible({ timeout: 10000 });
    await saveBtn.click();

    // Warten bis Lightning die UI zurück ins read-View schaltet
    await page.waitForTimeout(5000);

    // SOQL-Read-Back: Wert muss in der Org persistiert sein
    const orgValue = soql(`SELECT ${FIELD_API} FROM Contact WHERE Id='${testContactId}'`).records[0][FIELD_API];
    expect(
      orgValue,
      `SOQL-Read-Back: erwartete "Nachmittags", Org enthält "${orgValue}" — UI-Save nicht wirksam`
    ).toBe('Nachmittags');
  });

});
