import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-412] E2E — Ansprechpartner eines Accounts direkt in der Kontaktübersicht
 *
 * Ziel: Auf dem Account-Record zeigt die Contact-Related-List Name, Telefon, E-Mail
 * der zugehörigen Kontakte — live aus den Contact-Feldern, keine Duplizierung.
 *
 * AC1: Kontakte mit Name/Phone/Email-Spalten sichtbar
 * AC2: Phone-Änderung wirkt live in der Account-Übersicht
 * AC3: Name-/Email-Änderung wirkt live
 * AC4: Account ohne Kontakte → leere Übersicht
 * AC5: FLS wird respektiert (von Tester mit eingeschränktem Nutzer geprüft)
 *
 * Mechanismus: keine Metadata-Änderung — die standardisierte Related-List-Konfiguration
 * auf Account-Layouts (Classic) bzw. Lightning-Record-Page-Related-List-Block trägt
 * die Spalten FULL_NAME, CONTACT.EMAIL, CONTACT.PHONE1. Der Test verifiziert das
 * Ergebniss im UI, nicht die Datei. Seeded: [SCRUM-412-e2e]-Tags für Cleanup.
 */

function sfJson(command: string): any {
  const raw = execSync(command, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
}

function recId(result: any): string {
  return result?.attributes?.recordId ?? result?.id ?? '';
}

/** Seeded: 3 Accounts mit je 2 Kontakten (Name/Phone/Email) + 1 Account ohne Kontakte */
function seedE2EData(): { accIds: string[]; contactIds: string[]; acctNoContactsId: string } {
  const tag = Date.now();

  const saProfileId = sfJson(
    "sf data query -o Test-Org --json -q \"SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1\""
  ).result.records[0].Id;

  const accIds: string[] = [];
  for (let i = 0; i < 3; i++) {
    const a = sfJson(
      `sf data create record -s Account -v 'Name=[SCRUM-412-e2e] Akte ${i}' --target-org Test-Org --json`
    ).result;
    accIds.push(recId(a));
  }

  const contactIds: string[] = [];
  // Contacts für die ersten 2 Accounts (AC1, AC2, AC3)
  for (let i = 0; i < 2; i++) {
    const c1 = sfJson(
      `sf data create record -s Contact -v 'FirstName=Ansprech' 'LastName=Partner ${i}a' 'AccountId=${accIds[i]}' 'Phone=0800-${100+i}' 'Email=ansprech${i}a@beispiel.invalid' --target-org Test-Org --json`
    ).result;
    contactIds.push(recId(c1));
    const c2 = sfJson(
      `sf data create record -s Contact -v 'FirstName=Ansprech' 'LastName=Partner ${i}b' 'AccountId=${accIds[i]}' 'Phone=0800-${200+i}' 'Email=ansprech${i}b@beispiel.invalid' --target-org Test-Org --json`
    ).result;
    contactIds.push(recId(c2));
  }
  // Dritter Account bleibt ohne Kontakte (AC4)
  const acctNoContactsId = accIds[2];

  return { accIds, contactIds, acctNoContactsId };
}

/** Lightning-Record-Page auf einem Account öffnen und Related-List warten */
async function openAccount(page: any, accId: string) {
  await page.goto(`/lightning/r/Account/${accId}/view`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  // Lightning Header als Indikator, dass die Seite geladen ist
  await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
  // Die Contact-Related-List muss gerendert sein
  await page.locator('.related-list-container, .slds-related-list, table[data-object-api-name="Contact"]').first().waitFor({ state: 'attached', timeout: 30000 });
}

test.describe('[SCRUM-412] Account-Kontaktübersicht — Name, Telefon, E-Mail (Test-Org)', () => {
  test('AC1: Kontaktdaten der Kontakte in der Account-Related-List sichtbar', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccount(page, accIds[0]);

    // AC1: Die Kontakt-Related-List zeigt mindestens 2 Zeilen
    const contactRows = page.locator('.slds-table_row, tr.slds-hint-parent').filter({ hasNot: page.locator('th, thead') });
    await expect(contactRows.first()).toBeVisible({ timeout: 20000 });
    const rowCount = await contactRows.count();
    expect(rowCount).toBeGreaterThanOrEqual(2);

    // Spalten: Name, Telefon, E-Mail
    await expect(contactRows.first()).toContainText(/^Ansprech Partner 0a$/i);
    await expect(contactRows.first()).toContainText(/0\d+-\d+/);   // Telefon
    await expect(contactRows.first()).toContainText(/ansprech.*@beispiel\.invalid/i); // E-Mail

    // Zweiter Kontakt ebenfalls sichtbar
    await expect(contactRows.nth(1)).toContainText(/^Ansprech Partner 0b$/i);
  }, 120000);

  test('AC2: Änderung der Telefonnummer eines Kontakts wirkt live in der Account-Übersicht', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();
    const originalPhone = sfJson(
      `sf data query -o Test-Org --json -q "SELECT Id, Phone FROM Contact WHERE Id IN ('${contactIds[0]}')"`
    ).result.records[0].Phone;

    await openAccount(page, accIds[0]);
    await expect(page.locator('.related-list-container, .slds-related-list, table').first()).toContainText(/0\d+-\d+/);

    // Telefonnummer im Contact ändern
    const newPhone = '0800-NEUAUS';
    sfJson(
      `sf data update record -s Contact -i ${contactIds[0]} -v "Phone=${newPhone}" --target-org Test-Org --json`
    );

    // Account-Page neu laden → Related-List muss den neuen Wert zeigen
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
    await page.locator('.slds-table_row, tr.slds-hint-parent').first().waitFor({ state: 'attached', timeout: 30000 });

    // Neuer Wert muss sichtbar sein (alter Wert weg)
    await expect(page.locator('body')).toContainText(newPhone, { timeout: 20000 });
  }, 120000);

  test('AC3: Änderung von Name und E-Mail des Kontakts wirkt live', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccount(page, accIds[1]);

    const newLastName = 'Geändert';
    const newEmail = 'geandert@beispiel.invalid';

    // Name und Email im Contact ändern
    sfJson(
      `sf data update record -s Contact -i ${contactIds[2]} -v "LastName=${newLastName} Email=${newEmail}" --target-org Test-Org --json`
    );

    // Neu laden und prüfen
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
    await page.locator('.slds-table_row, tr.slds-hint-parent').first().waitFor({ state: 'attached', timeout: 30000 });

    await expect(page.locator('body')).toContainText(newLastName, { timeout: 20000 });
    await expect(page.locator('body')).toContainText(newEmail, { timeout: 20000 });
  }, 120000);

  test('AC4: Account ohne Kontakte → leere Übersicht', async ({ page }) => {
    const { acctNoContactsId } = seedE2EData();

    await openAccount(page, acctNoContactsId);

    // Contact-Related-List vorhanden, aber leer (kein Zeileninhalt außer dem Hinweis)
    const contactRows = page.locator('.slds-table_row').filter({ hasNot: page.locator('th, thead') });
    const rowCount = await contactRows.count();
    // Keine Datenzeilen — die Related-List bleibt leer
    expect(rowCount).toBe(0);
  }, 60000);
});
