import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-410] E2E — Betreuungs-Übergabe als Quick Action auf dem User-Record,
 * Lightning UI, Test-Org.
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (nie hardcoded). Network niemals networkidle auf Lightning.
 *
 * Mechanismus: das LWC betreuungsuebergabe läuft als RecordAction (Quick
 * Action) auf dem User-Objekt. Teamleitung öffnet den User-Record der
 * abgebenden Person → „Betreuung übergeben" → „Abgibt" ist vorausgefüllt
 * (dieser Record, via getRecord User.Name) → „Übernimmt" ist ein Picker über
 * alle aktiven Nutzer außer der abgebenden → „Vorschau" zeigt die 4 Counts
 * (AC1, read-only Apex) → „Übergeben (jetzt ausführen)" startet den atomaren
 * Queueable (AC2). Danach ist die Audit-Zeile im Org (AC6) — via SOQL
 * read-back verifiziert, nicht via UI (Ask the Tool).
 *
 * Seeded: 3 Accounts / 3 Kontakte / 2 offene Cases / 2 offene Opps, alles
 * owner = fromUser. Tags [SCRUM410-e2e], damit Nachvollzug und Cleanup
 * per SOQL möglich sind.
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

function seedE2EData() {
  const tag = Date.now();
  const profileQ =
    'ProfileId=(SELECT Id FROM Profile WHERE Name=\'System Administrator\' LIMIT 1)';

  const fromUser = sfJson(
    [
      'sf data create record -s User -v',
      profileQ,
      `'LastName=Scr410E2e From' 'Alias=scr410f'`,
      `'Email=scr410e2efrom_${tag}@example.invalid' 'Username=scr410e2efrom_${tag}@example.invalid'`,
      'EmailEncodingKey=UTF-8 LanguageLocaleKey=en_US LocaleSidKey=en_US TimeZoneSidKey=America/Los_Angeles',
      '--target-org Test-Org --json',
    ].join(' ')
  ).result;
  const fromId = recId(fromUser);

  const toUser = sfJson(
    [
      'sf data create record -s User -v',
      profileQ,
      `'LastName=Scr410E2e To' 'Alias=scr410t'`,
      `'Email=scr410e2eto_${tag}@example.invalid' 'Username=scr410e2eto_${tag}@example.invalid'`,
      'EmailEncodingKey=UTF-8 LanguageLocaleKey=en_US LocaleSidKey=en_US TimeZoneSidKey=America/Los_Angeles',
      '--target-org Test-Org --json',
    ].join(' ')
  ).result;
  const toId = recId(toUser);

  const accountIds: string[] = [];
  for (let i = 0; i < 3; i++) {
    const a = sfJson(
      `sf data create record -s Account -v 'Name=[SCRUM410-e2e] Akte ${i}' 'OwnerId=${fromId}' --target-org Test-Org --json`
    ).result;
    accountIds.push(recId(a));
  }
  for (let i = 0; i < 3; i++) {
    sfJson(
      `sf data create record -s Contact -v 'FirstName=E2E' 'LastName=Scr410 ${i}' 'AccountId=${accountIds[i]}' 'OwnerId=${fromId}' --target-org Test-Org --json`
    );
  }
  for (let i = 0; i < 2; i++) {
    sfJson(
      `sf data create record -s Case -v 'Status=New' 'Subject=[SCRUM410-e2e] offen ${i}' 'OwnerId=${fromId}' --target-org Test-Org --json`
    );
  }
  for (let i = 0; i < 2; i++) {
    sfJson(
      `sf data create record -s Opportunity -v 'Name=[SCRUM410-e2e] Chance ${i}' 'StageName=Prospecting' 'OwnerId=${fromId}' --target-org Test-Org --json`
    );
  }

  return { fromUserId: fromId, toUserId: toId };
}

test.describe('[SCRUM-410] Betreuungs-Übergabe Quick Action (Test-Org)', () => {
  test('AC1+AC2+AC6: Vorschau zählt exakt, Ausführung überträgt, Audit-Zeile landet im Org', async ({ page }) => {
    const { fromUserId, toUserId } = seedE2EData();

    await page.goto(`/lightning/r/User/${fromUserId}/view`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    // Lightning: structural landmark, nie networkidle.
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });

    // Quick Action über das Record-Header-Menü („Nutzer"/„User" > „Betreuung übergeben").
    const qaButton = page.getByText('Betreuung übergeben', { exact: false }).first();
    const inMenu = await qaButton.isVisible({ timeout: 15000 }).catch(() => false);
    if (!inMenu) {
      // Im Record-Header muss ggf. erst das „More"-Menü (Nutzer-Aktionen) geöffnet werden.
      const more = page
        .locator('button.slds-button_neutral, button[data-name=\"moreActions\"], [data-testid=\"moreActions\"]')
        .first();
      if (await more.isVisible({ timeout: 5000 }).catch(() => false)) {
        await more.click();
        await page.waitForTimeout(1000);
      }
      await qaButton.waitFor({ state: 'visible', timeout: 20000 });
    }
    await qaButton.click();

    // LWC im Side Panel: „Abgibt" ist read-only vorausgefüllt,
    // „Übernimmt" ist ein native <select> (lightning-combobox wird nicht im
    // Quick-Action-Panel gerendert — ein select ist die robuste Wahl).
    await expect(page.getByRole('textbox', { name: /Gibt ab/i }).first()).toBeVisible({ timeout: 20000 });
    const toSelect = page.locator('select').first();
    await toSelect.selectOption({ label: 'Scr410E2e To' });

    // AC1: Vorschau — die 4 Counts exakt (3/3/2/2).
    await page.getByRole('button', { name: 'Vorschau' }).click();
    await expect(page.getByText('Bei Ausführung würde wechseln:', { exact: false })).toBeVisible({ timeout: 20000 });
    const items = page.locator('.transfer__preview-list li');
    await expect(items.nth(0)).toContainText('3');
    await expect(items.nth(1)).toContainText('3');
    await expect(items.nth(2)).toContainText('2');
    await expect(items.nth(3)).toContainText('2');

    // AC2: Ausführung — der Status-Text erscheint.
    await page.getByRole('button', { name: /Übergeben \(jetzt ausführen\)/ }).click();
    await expect(page.getByText('Übergabe abgestoßen.', { exact: false }).first()).toBeVisible({ timeout: 30000 });

    // AC6 + AC7 (live read-back via SOQL, nicht UI): Audit-Zeile + Ownership-Wechsel.
    await page.waitForTimeout(4000); // Queueable läuft unmittelbar nach enqueue.
    const latestRun = sfJson(
      'sf data query --target-org Test-Org --json -q "SELECT Status__c, Accounts_Transferred__c, Contacts_Transferred__c, Open_Cases_Transferred__c, Open_Opportunities_Transferred__c, From_User__c FROM CustomerTransfer__c ORDER BY CreatedDate DESC LIMIT 1"'
    ).result;
    expect(Number(latestRun.totalSize)).toBeGreaterThanOrEqual(1);
    const row = latestRun.records[0];
    expect(row.Status__c).toBe('Abgeschlossen');
    expect(Number(row.Accounts_Transferred__c)).toBeGreaterThanOrEqual(3);
    expect(Number(row.Contacts_Transferred__c)).toBeGreaterThanOrEqual(3);
    expect(Number(row.Open_Cases_Transferred__c)).toBeGreaterThanOrEqual(2);
    expect(Number(row.Open_Opportunities_Transferred__c)).toBeGreaterThanOrEqual(2);
    expect(row.From_User__c).toBe(fromUserId);

    // Die geseedeten Accounts gehören jetzt dem Übernehmer: fromUser hält keinen mehr.
    const remaining = sfJson(
      `sf data query --target-org Test-Org --json -q "SELECT COUNT(Id) FROM Account WHERE OwnerId='${fromUserId}' AND Name LIKE '%[SCRUM410-e2e]%'"`
    ).result;
    expect(Number(remaining.totalSize)).toBe(0);
    void toUserId;
  }, 120000);
});
