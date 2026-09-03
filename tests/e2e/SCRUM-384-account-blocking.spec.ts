import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, expectFieldVisible, startInlineEdit, saveInlineEdit } from './record-page';

/**
 * [SCRUM-384] Account sperren (Gesperrt + Sperrgrund) — UI-E2E, Test-Org (Lightning).
 *
 * Self-contained: alle Setup-Accounts werden pro Run via CLI in die Test-Org
 * angelegt und in afterAll wieder gelöscht — keine hartkodierten IDs.
 *
 * FLS: PS SCRUM384_AccountBlocking muss vor dem Lauf an den UI-User
 *      (devops-agent@cline.test, System Admin) zugewiesen sein — ohne diese
 *      Zuweisung sind beide Felder unsichtbar und `sf data create record`
 *      gibt "No such column 'Is_Locked__c'" zurück.
 *
 * AC-Abdeckung:
 *   AC1 — beider Felder + Werte sichtbar im Details-Tab
 *   AC2 — Gesperrt=true ohne Grund → ValRule-Block, Meldung nennt „Sperrgrund"
 *   AC3 — Opportunity am gesperrten Account → Guard-Block, Meldung nennt
 *          Account-Namen UND Sperrgrund (CLI-Level; Primärbeweis: Apex-Test)
 *   AC4 — Gesperrt aufheben → Sperrgrund leer, Opp wieder anlegbar
 *   FLS — Negativ via Apex System.runAs(); Positiv: SysAdmin mit PS (dieser Lauf)
 */

const TAG = 'SCRUM-384-UI';

// ── SF-CLI Helpers ──────────────────────────────────────────────────────────

function shellJson(out: string): any {
  const cleaned = out
    .replace(/﻿/g, '')
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = cleaned.indexOf('{');
  const end   = cleaned.lastIndexOf('}');
  if (start < 0 || end < start) {
    throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  }
  return JSON.parse(cleaned.slice(start, end + 1));
}

function createAccount(fields: string): string {
  const out = execSync(
    `sf data create record -s Account -v "${fields}" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 60_000, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  const doc = shellJson(out);
  const id = doc?.result?.id;
  if (!id) throw new Error(`Account-Create lieferte keine Id: ${out.slice(0, 300)}`);
  return String(id);
}

/** Opportunity via REST anlegen; ok=true wenn persistiert, sonst errMessage. */
function tryCreateOpportunity(
  accountId: string,
  oppIds: string[],
): { ok: boolean; errMessage: string; id?: string } {
  const out = execSync(
    `sf data create record -s Opportunity ` +
    `-v "Name='${TAG}-opp' StageName='Prospecting' CloseDate=2027-06-01 AccountId='${accountId}'" ` +
    `--target-org Test-Org --json 2>&1`,
    { encoding: 'utf-8', timeout: 60_000, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  const doc = shellJson(out);
  if (doc?.status === 0 && doc?.result?.success) {
    const id = String(doc.result.id);
    if (oppIds) oppIds.push(id);
    return { ok: true, errMessage: '', id };
  }
  const err = doc?.data?.message ?? doc?.message ?? 'unbekannter Fehler';
  return { ok: false, errMessage: err };
}

function deleteAccountSafe(id: string) {
  try {
    execSync(`sf data delete record -s Account -i ${id} --target-org Test-Org --json`,
      { encoding: 'utf-8', timeout: 30_000, stdio: ['pipe', 'pipe', 'pipe'] });
  } catch { /* best effort */ }
}
function deleteOppSafe(id: string) {
  try {
    execSync(`sf data delete record -s Opportunity -i ${id} --target-org Test-Org --json`,
      { encoding: 'utf-8', timeout: 30_000, stdio: ['pipe', 'pipe', 'pipe'] });
  } catch { /* best effort */ }
}

/** Gesperrt-Checkbox lokalisieren (role=checkbox, Fallback [name=Is_Locked__c]). */
async function findGesperrtCheckbox(page: Page) {
  const byRole = page.getByRole('checkbox', { name: /Gesperrt/i }).first();
  const byName = page.locator('[name="Is_Locked__c"]').first();
  if ((await byRole.count()) > 0) return byRole;
  if ((await byName.count()) > 0) return byName;
  throw new Error(
    'Gesperrt-Checkbox nicht gefunden — Details-Tab muss offen sein und der ' +
    'UI-User FLS auf Is_Locked__c haben (PS SCRUM384_AccountBlocking zugewiesen?)',
  );
}

/** Checkbox gezielt toggle auf `target` (true=checked, false=unchecked). */
async function setCheckbox(page: Page, target: boolean) {
  const cb = await findGesperrtCheckbox(page);
  const cur = await cb.isChecked().catch(() => false);
  if (cur === target) return; // bereits im Zielzustand
  if (target) {
    await cb.check({ force: true }).catch(async () => { await cb.click({ force: true }); });
  } else {
    await cb.uncheck({ force: true }).catch(async () => { await cb.click({ force: true }); });
  }
}

test.describe('[SCRUM-384] Account sperren (Lightning UI)', () => {
  test.describe.configure({ timeout: 120_000 });

  let lockedId = '';
  let openId = '';
  const oppIds: string[] = [];

  test.beforeAll(() => {
    // Gemeinsame Setup-Accounts für AC1/AC2/AC3.
    openId   = createAccount(`Name='${TAG}-Open' Is_Locked__c=false`);
    lockedId = createAccount(`Name='${TAG}-Locked' Is_Locked__c=true Lock_Reason__c='offene Forderung'`);
  });

  test.afterAll(() => {
    // Alle Opportunities, dann beide Setup-Accounts.
    for (let i = oppIds.length - 1; i >= 0; i--) deleteOppSafe(oppIds[i]);
    if (lockedId) deleteAccountSafe(lockedId);
    if (openId)   deleteAccountSafe(openId);
  });

  // ── AC1 ─────────────────────────────────────────────────────────────────────
  test('AC1: Gesperrt + Sperrgrund und Werte sind im Details-Tab sichtbar', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Account/${lockedId}/view`);
    await expectFieldVisible(page, 'Gesperrt');
    await expectFieldVisible(page, 'Sperrgrund');
    await expect(
      page.getByText('offene Forderung', { exact: true }).first(),
      'Sperrgrund-Wert „offene Forderung" nicht sichtbar',
    ).toBeVisible({ timeout: 15_000 });
  });

  // ── AC2 ─────────────────────────────────────────────────────────────────────
  test('AC2: Gesperrt ohne Sperrgrund → ValRule blockiert, Meldung nennt „Sperrgrund"', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Account/${openId}/view`);
    await startInlineEdit(page, 'Gesperrt');
    await setCheckbox(page, true);          // Gesperrt=true, Sperrgrund bleibt leer
    await saveInlineEdit(page);

    // ValRule-Fehlermeldung mit dem Wort „Sperrgrund" muss sichtbar sein.
    await expect(
      page.locator('text=Sperrgrund').first(),
      'ValRule-Fehlermeldung mit „Sperrgrund" nicht sichtbar',
    ).toBeVisible({ timeout: 15_000 });

    // Reload → Gesperrt darf nicht persistiert sein.
    await openRecordDetails(page, `/lightning/r/Account/${openId}/view`);
    const cb = await findGesperrtCheckbox(page);
    const stillChecked = await cb.isChecked().catch(() => false);
    expect(stillChecked, 'Gesperrt darf nach ValRule-Block NICHT persistiert sein').toBe(false);
  });

  // ── AC3 ─────────────────────────────────────────────────────────────────────
  test('AC3: Opportunity am gesperrten Account blockiert — Meldung nennt Account + Sperrgrund', async () => {
    const res = tryCreateOpportunity(lockedId, oppIds);
    expect(res.ok, `Opp am gesperrten Account muss blockiert sein; msg=${res.errMessage}`).toBe(false);
    expect(res.errMessage.length, 'Fehlermeldung darf nicht leer sein').toBeGreaterThan(0);
    expect(res.errMessage.includes('TEST-SCRUM-384-UI-Locked'),
      `Meldung muss Account-Namen nennen; erhalten: ${res.errMessage}`).toBe(true);
    expect(res.errMessage.includes('offene Forderung'),
      `Meldung muss Sperrgrund-Wert nennen; erhalten: ${res.errMessage}`).toBe(true);
  });

  // ── AC4 ─────────────────────────────────────────────────────────────────────
  test('AC4: Gesperrt aufheben leert Sperrgrund, Opportunity wieder anlegbar', async ({ page }) => {
    // Eigenes AC4-Frisko (kein Sharing mit den Setup-Accounts).
    const id = createAccount(`Name='${TAG}-AC4' Is_Locked__c=true Lock_Reason__c='Zahlungsrückstand'`);

    try {
      await openRecordDetails(page, `/lightning/r/Account/${id}/view`);
      await expectFieldVisible(page, 'Gesperrt');
      await expect(
        page.getByText('Zahlungsrückstand', { exact: true }).first(),
      ).toBeVisible({ timeout: 15_000 });

      // Gesperrt unchecken → Save.
      await startInlineEdit(page, 'Gesperrt');
      await setCheckbox(page, false);
      await saveInlineEdit(page);
      await page.waitForURL(/view$/, { timeout: 30_000 });

      // Reload → Sperrgrund-Wert automatisch weg.
      await openRecordDetails(page, `/lightning/r/Account/${id}/view`);
      await expect(
        page.getByText('Zahlungsrückstand', { exact: true }),
        'Sperrgrund-Wert muss nach Aufheben automatisch geleert sein',
      ).toHaveCount(0, { timeout: 10_000 });

      // Opportunity wieder anlegbar.
      const res = tryCreateOpportunity(id, oppIds);
      expect(res.ok, `Nach Entsperrung muss Opp anlegbar sein; msg=${res.errMessage}`).toBe(true);
    } finally {
      deleteAccountSafe(id);
    }
  });
});
