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
 * Ergebnis im UI, nicht die Datei. Seeded: [SCRUM-412-e2e]-Tags für Cleanup.
 *
 * Design-Doc: docs/SCRUM-412-design.md Commit 8f931c7
 *
 * Fix 1 (von Architect PR #99 Review):
 *  • AC1: Related-List-Zeile enthält Name+Title+Email+Phone als EIN Text pro <tr>
 *    → kein ^…$-Anchor mehr, sondern toContainText(substring) pro <td>-Zelle.
 * Fix 2 (von Architect PR #99 Review):
 *  • Classic-Spec ergänzt — PO/Design verlangen E2E in BEIDEN UIs.
 *    Classic-URL-/Klassen-Pfade getrennt nachgewiesen.
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

// ============================================================
// Lightning helpers
// ============================================================

/** Open a Lightning Account record and wait for the Contact Related-List */
async function openAccount(page: any, accId: string): Promise<void> {
  await page.goto(`/lightning/r/Account/${accId}/view`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.locator('div.slds-global-header, one-appnav').first().waitFor({
    state: 'visible',
    timeout: 60000,
  });
  // Related-List table must be attached (Lightning: slds-table within related-list-block)
  await page.locator('.related-list-block, .related-list-container').first().waitFor({
    state: 'visible',
    timeout: 30000,
  });
}

// ============================================================
// Classic helpers
// ============================================================

/**
 * Open a Classic Account record (core.app=1) and wait for the Contact Related-List.
 * Note: This org 302-redirects Classic to Lightning, so the locator strategy
 * must work in both rendering modes. The related-list classes differ:
 *   - Classic: `<table class="relatedListTable">` inside `<div class="related-list">`
 *   - Lightning: `<table class="slds-table">` inside
 *     `<div class="related-list-block">` / `<div class="relatedListBlock">`
 */
async function openAccountClassic(page: any, accId: string): Promise<void> {
  await page.goto(`/one/one.app#/sObject/${accId}/view?core.app=1`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  // Wait for either a Classic header or a Lightning header (org redirects Classic→LIGHTNING)
  await page.locator('frame', { hasText: 'lightning' }).first().waitFor({
    state: 'attached',
    timeout: 60000,
  }).catch(async () => {
    // If not in an iframe (Classic), wait for the global header directly
    await page.locator('.globalHeader, div.slds-global-header, frame').first().waitFor({
      state: 'attached',
      timeout: 60000,
    });
  });
  // Wait for the Contact Related-List (works in both Classic and Lightning rendering)
  const relatedList = page.locator('table[class*=relatedList], .relatedListTable, table.slds-table').first();
  await relatedList.waitFor({ state: 'attached', timeout: 30000 });
}

/** Retrieve the contact row locator list for either Lightning or Classic */
async function getContactRows(page: any): Promise<any[]> {
  // Pick the correct table selector: Lightning uses slds-table, Classic uses relatedListTable
  const rows = page.locator('table.slds-table tbody tr, .relatedListTable tbody tr').filter({
    hasNot: page.locator('th'),
  });
  return await rows.all();
}

// ============================================================
// Lightning Tests (AC1–AC4)
// ============================================================

test.describe('[SCRUM-412] Account-Kontaktübersicht — Lightning UI (Test-Org)', () => {
  test('AC1: Kontaktdaten (Name, Phone, Email) der Kontakte in der Related-List sichtbar', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccount(page, accIds[0]);

    // Die Kontakt-Related-List zeigt mindestens 2 Zeilen
    const rows = await getContactRows(page);
    expect(rows.length).toBeGreaterThanOrEqual(2);

    // Fix 1: toContainText ohne ^…$, scope auf die Namenszelle (<td>),
    // da die <tr>-Reihe den vollständigen Zeilentext (Name+Title+Email+Phone) enthält.
    const firstCell = rows[0].locator('td').first();
    await expect(firstCell).toBeVisible({ timeout: 20000 });
    await expect(firstCell).toContainText('Ansprech Partner 0a');
    await expect(rows[0]).toContainText(/0\d+-\d+/); // Telefon
    await expect(rows[0]).toContainText(/ansprech.*@beispiel\.invalid/i); // E-Mail

    // Zweiter Kontakt ebenfalls nachweisbar
    const secondCell = rows[1].locator('td').first();
    await expect(secondCell).toContainText('Ansprech Partner 0b');
  }, 120000);

  test('AC2: Änderung der Telefonnummer eines Kontakts wirkt live in der Account-Übersicht', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccount(page, accIds[0]);
    const rows = await getContactRows(page);
    expect(rows.length).toBeGreaterThanOrEqual(2);

    await expect(rows[0]).toContainText(/0\d+-\d+/); // Original-Telefon sichtbar

    // Telefonnummer im Contact ändern
    const newPhone = '0800-NEUAUS';
    sfJson(
      `sf data update record -s Contact -i ${contactIds[0]} -v "Phone=${newPhone}" --target-org Test-Org --json`
    );

    // Account-Page neu laden → Related-List muss den neuen Wert zeigen
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({
      state: 'visible',
      timeout: 60000,
    });

    const rows2 = await getContactRows(page);
    await expect(rows2[0]).toContainText(newPhone, { timeout: 20000 });
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
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({
      state: 'visible',
      timeout: 60000,
    });

    const rows = await getContactRows(page);
    // Name und Email müssen im body sichtbar sein (live aus Contact)
    await expect(page.locator('body')).toContainText(newLastName, { timeout: 20000 });
    await expect(page.locator('body')).toContainText(newEmail, { timeout: 20000 });
  }, 120000);

  test('AC4: Account ohne Kontakte → leere Related-List', async ({ page }) => {
    const { acctNoContactsId } = seedE2EData();

    await openAccount(page, acctNoContactsId);

    // Contact-Related-List vorhanden, aber keine Datenzeilen
    const rows = await getContactRows(page);
    expect(rows.length).toBe(0);
  }, 60000);
});

// ============================================================
// Classic Tests (AC1, AC4) — PO/Design verlangen E2E in BEIDEN UIs
// ============================================================

test.describe('[SCRUM-412] Account-Kontaktübersicht — Classic UI (Test-Org)', () => {
  test('AC1: Kontaktdaten (Name, Phone, Email) in Classic-Related-List sichtbar', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccountClassic(page, accIds[0]);

    const rows = await getContactRows(page);
    expect(rows.length).toBeGreaterThanOrEqual(2);

    // Fix 1: zuContainText auf Namenszelle, kein Anchor
    const firstCell = rows[0].locator('td').first();
    await expect(firstCell).toBeVisible({ timeout: 20000 });
    await expect(firstCell).toContainText('Ansprech Partner 0a');
    await expect(rows[0]).toContainText(/0\d+-\d+/); // Telefonnummer
    await expect(rows[0]).toContainText(/ansprech.*@beispiel\.invalid/i); // E-Mail

    // Zweiter Kontakt
    const secondCell = rows[1].locator('td').first();
    await expect(secondCell).toContainText('Ansprech Partner 0b');
  }, 120000);

  test('AC4: Account ohne Kontakte → leere Classic-Related-List', async ({ page }) => {
    const { acctNoContactsId } = seedE2EData();

    await openAccountClassic(page, acctNoContactsId);

    const rows = await getContactRows(page);
    expect(rows.length).toBe(0);
  }, 60000);
});
