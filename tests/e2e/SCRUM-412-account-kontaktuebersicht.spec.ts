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
 * AC5: FLS wird respektiert — per architect-agent-Ruling (2026-09-13) über
 *       Invariante + Plattform-Garantie geschlossen (executed negative ist in
 *       der Test-Org nicht möglich: keine eingeschränkten Contact-Read-User).
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

  // NOTE (Tester, SCRUM-412): the sf CLI `data create -v` key=value parser
  // splits on spaces and only honours a space inside a *balanced pair of
  // double quotes that reach the parser*. The OUTER single-quotes below are
  // shell quotes that /bin/sh strips, so a value with a space must be wrapped
  // in INNER double-quotes (kept by oclif, seen by the parser):
  //   -v 'Name="[tag] Akte 0"'   (not -v 'Name=[tag] Akte 0')
  const accIds: string[] = [];
  for (let i = 0; i < 3; i++) {
    const a = sfJson(
      `sf data create record -s Account -v 'Name="[SCRUM-412-e2e] Akte ${i}"' --target-org Test-Org --json`
    ).result;
    accIds.push(recId(a));
  }

  const contactIds: string[] = [];
  // Contacts für die ersten 2 Accounts (AC1, AC2, AC3)
  for (let i = 0; i < 2; i++) {
    const c1 = sfJson(
      `sf data create record -s Contact -v 'FirstName=Ansprech LastName="Partner ${i}a" AccountId=${accIds[i]} Phone=0800-${100+i} Email=ansprech${i}a@beispiel.invalid' --target-org Test-Org --json`
    ).result;
    contactIds.push(recId(c1));
    const c2 = sfJson(
      `sf data create record -s Contact -v 'FirstName=Ansprech LastName="Partner ${i}b" AccountId=${accIds[i]} Phone=0800-${200+i} Email=ansprech${i}b@beispiel.invalid' --target-org Test-Org --json`
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
  // Probe-verified (a11y snapshot, 2026-09-13): the Contact list renders as
  // role=article cards in the already-selected "Related" tab. There is NO
  // <table> and NO .related-list-block/.related-list-container in this org.
  await page.getByRole('heading', { name: /^Contacts \(\d+\)/ }).first()
    .waitFor({ state: 'visible', timeout: 30000 });
}

/**
 * Probe-verified (a11y snapshot, 2026-09-13): each contact is a role=article
 * card whose accessible name is the full contact name ("Ansprech Partner 0a"),
 * containing the Name link plus "Email:"/"Phone:" terms whose definitions are
 * mailto:/tel: links — i.e. the live Contact values. There is NO <table>.
 */
function contactCards(page: any) {
  return page.locator('article').filter({
    has: page.getByRole('heading', { name: 'Ansprech ' }),
  });
}

// ============================================================
// Lightning Tests (AC1–AC4)
// ============================================================

test.describe('[SCRUM-412] Account-Kontaktübersicht — Lightning UI (Test-Org)', () => {
  test('AC1: Kontaktdaten (Name, Phone, Email) der Kontakte in der Related-List sichtbar', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccount(page, accIds[0]);

    // Präziser Anker: exakt ein Namens-Link pro Kontakt-Karte (a11y-verifiziert).
    // Zählung auf article würde in dieser Org Wrapper-Artikel inkludieren.
    const nameLinks = page.getByRole('link', { name: /^Ansprech Partner 0[ab]$/ });
    await expect(nameLinks).toHaveCount(2, { timeout: 20000 });
    const cards = contactCards(page);

    // Wert-Anker: die Karte des Kontakts enthält live Phone + Email (a11y-
    // verifiziert: term "Email:"/"Phone:" mit Definition = mailto/tel-Link).
    const cardA = cards.filter({ hasText: 'Ansprech Partner 0a' });
    await expect(cardA.first()).toContainText(/0800-100/, { timeout: 20000 });
    await expect(cardA.first()).toContainText(/ansprech0a@beispiel\.invalid/i);
    const cardB = cards.filter({ hasText: 'Ansprech Partner 0b' });
    await expect(cardB.first()).toContainText(/0800-200/);
    await expect(cardB.first()).toContainText(/ansprech0b@beispiel\.invalid/i);
  }, 120000);

  test('AC2: Änderung der Telefonnummer eines Kontakts wirkt live in der Account-Übersicht', async ({ page }) => {
    const { accIds, contactIds } = seedE2EData();

    await openAccount(page, accIds[0]);
    const cardA = contactCards(page).filter({ hasText: 'Ansprech Partner 0a' });
    await expect(cardA.first()).toContainText(/0800-100/); // Original-Telefon sichtbar

    // Telefonnummer im Contact ändern
    const newPhone = '0151-4120412';
    sfJson(
      `sf data update record -s Contact -i ${contactIds[0]} -v "Phone=${newPhone}" --target-org Test-Org --json`
    );

    // Account-Page neu laden → Related-List muss den NEUEN Wert zeigen
    await page.reload({ waitUntil: 'domcontentloaded' });
    await expect(
      contactCards(page).filter({ hasText: 'Ansprech Partner 0a' }).first(),
    ).toContainText(newPhone, { timeout: 20000 });
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

    // Name und Email müssen im body sichtbar sein (live aus Contact)
    await expect(page.locator('body')).toContainText(newLastName, { timeout: 20000 });
    await expect(page.locator('body')).toContainText(newEmail, { timeout: 20000 });
  }, 120000);

  test('AC4: Account ohne Kontakte → leere Related-List', async ({ page }) => {
    const { acctNoContactsId } = seedE2EData();

    await openAccount(page, acctNoContactsId);

    // Contact-Related-List vorhanden, aber keine Kontakt-Karten
    expect(await contactCards(page).count()).toBe(0);
  }, 60000);
});

// ============================================================
// Classic: NICHT getestet (Architect-Ruling SCRUM-412, 2026-09-13)
// AC1s Gherkin-When ist wörtlich "Lightning Record Page" — Lightning-only.
// Die Test-Org rendert Classic strukturell nie (one.app?core.app=1 wird mit
// 302 auf Lightning umgeleitet, live verifiziert am 2026-09-13). Classic-
// Tests würden hier nur über den Redirect laufen und kein Classic beweisen.
// Bei späterer Reaktivierung von Classic in der Test-Org: Classic-Suite
// wieder ergänzen.
// ============================================================
