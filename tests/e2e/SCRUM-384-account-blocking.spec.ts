import { test, expect, type Page } from '@playwright/test';
import { execSync, execFileSync } from 'node:child_process';
import { openRecordDetails, expectFieldVisible, startInlineEdit, saveInlineEdit } from './record-page';

const TAG = 'SCRUM-384-UI';

function shellJson(out: string): any {
  const cleaned = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error('Kein JSON: ' + out.slice(0,300));
  return JSON.parse(cleaned.slice(start, end + 1));
}

function createAccount(fields: string): string {
  const out = execSync(
    `sf data create record -s Account -v "${fields}" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 60000, stdio: ['pipe','pipe','pipe'] },
  );
  const doc = shellJson(out);
  const id = doc?.result?.id;
  if (!id) throw new Error('Account-Create ohne Id: ' + out.slice(0,300));
  return String(id);
}

function tryCreateOpp(
  accountId: string,
  oppIds: string[],
): { ok: boolean; errMessage: string; id?: string } {
  const args = [
    'data','create','record','-s','Opportunity',
    '-v', `Name='${TAG}-opp' StageName='Prospecting' CloseDate=2027-06-01 AccountId='${accountId}'`,
    '--target-org','Test-Org','--json',
  ];
  let out = '';
  try {
    out = execFileSync('sf', args, { encoding: 'utf-8', timeout: 60000 });
  } catch (err: any) {
    out = (err?.stdout ?? '') + (err?.stderr ?? '');
  }
  const doc = shellJson(out);
  if (doc?.status === 0 && doc?.result?.success) {
    const id = String(doc.result.id);
    if (oppIds) oppIds.push(id);
    return { ok: true, errMessage: '', id };
  }
  const err = doc?.data?.message ?? doc?.message ?? out.slice(0,400);
  return { ok: false, errMessage: err };
}

function delAccSafe(id: string) {
  try {
    execSync(`sf data delete record -s Account -i ${id} --target-org Test-Org --json`,
      { encoding: 'utf-8', timeout: 30000, stdio: ['pipe','pipe','pipe'] });
  } catch {}
}
function delOppSafe(id: string) {
  try {
    execSync(`sf data delete record -s Opportunity -i ${id} --target-org Test-Org --json`,
      { encoding: 'utf-8', timeout: 30000, stdio: ['pipe','pipe','pipe'] });
  } catch {}
}

function queryIsLocked(id: string): boolean {
  const out = execSync(
    `sf data query -q "SELECT Is_Locked__c FROM Account WHERE Id='${id}'" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 60000, stdio: ['pipe','pipe','pipe'] },
  );
  const doc = shellJson(out);
  return !!doc?.result?.records?.[0]?.Is_Locked__c;
}

async function findGesperrtCb(page: Page) {
  // Proven locator: startInlineEdit already relies on this exact getByLabel
  // (returns count=1, visible in edit mode). Reuse it instead of the
  // role/name scans — the checkbox is exposed via its accessible label
  // "Gesperrt", NOT via a checkbox role name or a [name] attribute, so the
  // getByRole('checkbox',{name:...}) and [name="Is_Locked__c"] selectors
  // both find 0 hits (verified by AX-tree probe on 001WU00002C3j2TYAR).
  const byLabel = page.getByLabel('Gesperrt', { exact: true }).first();
  try {
    await byLabel.waitFor({ state: 'visible', timeout: 20000 });
  } catch {
    throw new Error('Gesperrt-Checkbox (getByLabel) nach 20s nicht sichtbar');
  }
  return byLabel;
}

async function setCb(page: Page, target: boolean) {
  const cb = await findGesperrtCb(page);
  const cur = await cb.isChecked().catch(() => false);
  if (cur === target) return;
  if (target) {
    await cb.check({ force: true }).catch(async () => { await cb.click({ force: true }); });
  } else {
    await cb.uncheck({ force: true }).catch(async () => { await cb.click({ force: true }); });
  }
}

test.describe('[SCRUM-384] Account sperren (Lightning UI)', () => {
  test.describe.configure({ timeout: 180000 });

  let lockedId = '';
  let openId = '';
  const oppIds: string[] = [];

  test.beforeAll(() => {
    openId = createAccount(`Name='${TAG}-Open' Is_Locked__c=false`);
    lockedId = createAccount(`Name='${TAG}-Locked' Is_Locked__c=true Lock_Reason__c='offene Forderung'`);
  });

  test.afterAll(() => {
    for (let i = oppIds.length - 1; i >= 0; i--) delOppSafe(oppIds[i]);
    if (lockedId) delAccSafe(lockedId);
    if (openId)   delAccSafe(openId);
  });

  test('AC1: Gesperrt + Sperrgrund und Werte sichtbar im Details-Tab', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Account/${lockedId}/view`);
    await expectFieldVisible(page, 'Gesperrt');
    await expectFieldVisible(page, 'Sperrgrund');
    await expect(
      page.getByText('offene Forderung', { exact: true }).first(),
      'Sperrgrund-Wert nicht sichtbar',
    ).toBeVisible({ timeout: 15000 });
  });

  test('AC2: Gesperrt ohne Sperrgrund wird blockiert, Meldung nennt Sperrgrund', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Account/${openId}/view`);
    await startInlineEdit(page, 'Gesperrt');
    await setCb(page, true);
    await saveInlineEdit(page);

    // VR-Meldung: 'Gesperrt darf nur gesetzt … „Sperrgrund" …'. Nach dem
    // fehlgeschlagenen Save ist das Wort „Sperrgrund" ≥2× sichtbar: 1× als
    // Feld-Label, 1× IN der Fehlermeldung (robust gegen UI-Word-Wrap).
    await expect.poll(
      async () => (await page.getByText('Sperrgrund').count()),
      { timeout: 20000 },
    ).toBeGreaterThanOrEqual(2);

    // Persistenz: Is_Locked__c muss via SOQL nach dem blockierten Save
    // immer noch false sein (authoritativer Readback, nicht UI-Checkbox).
    expect(queryIsLocked(openId), 'Gesperrt darf nach ValRule-Block NICHT persistiert sein').toBe(false);
  });

  test('AC3: Opportunity am gesperrten Account blockiert, Meldung nennt Account + Sperrgrund', async () => {
    const res = tryCreateOpp(lockedId, oppIds);
    expect(res.ok, `Opp am gesperrten Account muss blockiert sein; msg=${res.errMessage}`).toBe(false);
    expect(res.errMessage.length, 'Fehlermeldung darf nicht leer sein').toBeGreaterThan(0);
    expect(
      res.errMessage.includes(`${TAG}-Locked`),
      `Meldung muss Account-Namen nennen; erhalten: ${res.errMessage}`,
    ).toBe(true);
    expect(
      res.errMessage.includes('offene Forderung'),
      `Meldung muss Sperrgrund-Wert nennen; erhalten: ${res.errMessage}`,
    ).toBe(true);
  });

  test('AC4: Gesperrt aufheben leert Sperrgrund, Opportunity wieder anlegbar', async ({ page }) => {
    const id = createAccount(`Name='${TAG}-AC4' Is_Locked__c=true Lock_Reason__c='Zahlungsrückstand'`);
    try {
      await openRecordDetails(page, `/lightning/r/Account/${id}/view`);
      await expectFieldVisible(page, 'Gesperrt');
      await expect(
        page.getByText('Zahlungsrückstand', { exact: true }).first(),
      ).toBeVisible({ timeout: 15000 });

      await startInlineEdit(page, 'Gesperrt');
      await setCb(page, false);
      await saveInlineEdit(page);
      await page.waitForURL(/view$/, { timeout: 30000 });

      await openRecordDetails(page, `/lightning/r/Account/${id}/view`);
      await expect(
        page.getByText('Zahlungsrückstand', { exact: true }),
        'Sperrgrund-Wert muss nach Aufheben automatisch geleert sein',
      ).toHaveCount(0, { timeout: 10000 });

      const res = tryCreateOpp(id, oppIds);
      expect(res.ok, `Nach Entsperrung muss Opp anlegbar sein; msg=${res.errMessage}`).toBe(true);
    } finally {
      delAccSafe(id);
    }
  });
});

