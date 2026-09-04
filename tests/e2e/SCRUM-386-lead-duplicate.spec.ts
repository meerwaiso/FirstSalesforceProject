/**
 * [SCRUM-386] Lead-Dubletten-Markierung per E-Mail — E2E (Lightning UI)
 *
 * E2E deckt AC1: das Kennzeichen "Möglicher Doppeleintrag" und das Feld
 * "Doppelt zu" sind auf dem Lead-Layout sichtbar (Section "Dublettenprüfung").
 *
 * Funktionale Korrektheit (AC2–AC5, ADR-6, FLS neg/pos) wird von den in-org
 * Apex-Tests SCRUM386LeadDuplicateTest / SCRUM386LeadDuplicateFlsTest
 * automatisiert und ist hier nicht redundant abgedeckt — hier nur, was ein
 * Nutzer in der UI SIEHT.
 *
 * Testdaten werden per SOQL-Readback gegen die Test-Org verifiziert, BEVOR
 * sie als Fixtures für die UI-Asserts herhalten (Read-back, nicht Annahme).
 */
import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, expectFieldVisible } from './record-page';

const TAG = 'SCRUM-386';

function shellJson(out: string): any {
  const cleaned = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error('Kein JSON: ' + out.slice(0, 300));
  return JSON.parse(cleaned.slice(start, end + 1));
}

function query(soql: string): any[] {
  const out = execSync(
    `sf data query -o Test-Org -q "${soql}" --json`,
    { encoding: 'utf-8', timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  return shellJson(out)?.result?.records ?? [];
}

function createLead(fs: string, ln: string, email: string, company: string): string {
  const out = execSync(
    `sf data create record -s Lead -o Test-Org -v "FirstName='${fs}' LastName='${ln}' Email='${email}' Company='${company}'" --json`,
    { encoding: 'utf-8', timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  const id = shellJson(out)?.result?.id;
  if (!id) throw new Error(`Lead-Create ohne Id: ${out.slice(0, 300)}`);
  return String(id);
}

function delLeadSafe(id: string) {
  try {
    execSync(`sf data delete record -s Lead -i ${id} --target-org Test-Org --json`,
      { encoding: 'utf-8', timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });
  } catch {}
}

function getLead(id: string) {
  return query(`SELECT Likely_Duplicate__c, Duplicate_Of__c, Email FROM Lead WHERE Id='${id}'`)[0];
}

test.describe(`[${TAG}] Lead Dubletten-Markierung (AC1: Layout-Anzeige)`, () => {
  test.describe.configure({ timeout: 180000, retries: 1 });

  let refId: string;      // älter, Referenz-Email  -> NICHT markiert
  let dupId: string;      // jünger, case-varied    -> markiert, DupOf = Name(ref)
  let cleanId: string;    // eindeutige Email         -> NICHT markiert
  let refName: string;

  test.beforeAll(() => {
    // Einmaliger import, drei Schreibweisen derselben + eine eindeutige.
    // Reihenfolge = created-order (jeder create ~1s Abstand), damit
    // refId der "älteste" Lead der Dublettengruppe ist und DupOf = sein Name.
    refId   = createLead('T386', 'Ref',   'ac1ref@ex.pde',  `${TAG} Ref`);
    dupId   = createLead('T386', 'Dup',   'AC1REF@EX.PDE',  `${TAG} Dup`);
    cleanId = createLead('T386', 'Clean', 'ac1clean@ex.pde',`${TAG} Clean`);

    // Read-back, BEVOR die UI-Tests auf den Werten bauen (kein Annahmen).
    const ref = getLead(refId); const clean = getLead(cleanId); const dup = getLead(dupId);
    refName = query(`SELECT Name FROM Lead WHERE Id='${refId}'`)[0].Name;

    expect(clean?.Likely_Duplicate__c, 'AC1-clean: eindeutige E-Mail muss unmarkiert sein').toBe(false);
    expect(ref?.Likely_Duplicate__c,   'AC1-ref: Referenz-Lead muss unmarkiert sein').toBe(false);
    expect(dup?.Likely_Duplicate__c,   'AC1-dup: DubLETTE muss markiert sein').toBe(true);
    expect(dup?.Duplicate_Of__c,       'AC1-dup: "Doppelt zu" muss den Namen des ältesten Leads nennen')
      .toBe(refName);

    test.info().annotations.push({ type: 'seed', description: `ref=${refId} dup=${dupId} clean=${cleanId} refName="${refName}"` });
  });

  test.afterAll(() => {
    for (const id of [cleanId, dupId, refId]) if (id) delLeadSafe(id);
  });

  test('AC1: Section "Dublettenprüfung" zeigt Kennzeichen + "Doppelt zu"', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Lead/${dupId}/view`);
    // Die neue Section (zwischen Nachfassung und System Information)
    await expectFieldVisible(page, 'Dublettenprüfung');
    // Beide Felder sind im Layout (PO: systemgesetzt, Read-only)
    await expectFieldVisible(page, 'Möglicher Doppeleintrag');
    await expectFieldVisible(page, 'Doppelt zu');
  });

  test('AC1: "Doppelt zu" zeigt den Namen des älteren Leads auf der Dublettenseite', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Lead/${dupId}/view`);
    await expectFieldVisible(page, 'Doppelt zu');
    // Der Read-back-Wert aus beforeAll muss im Details-Tab sichtbar sein.
    await expect(page.getByText(refName, { exact: false }).first(),
      `"Doppelt zu"-Wert "${refName}" nicht im Details-Tab sichtbar`).toBeVisible({ timeout: 15000 });
  });

  test('AC1: Bei eindeutiger E-Mail ist kein "Doppelt zu"-Wert vorhanden', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Lead/${cleanId}/view`);
    await expectFieldVisible(page, 'Möglicher Doppeleintrag');
    await expectFieldVisible(page, 'Doppelt zu');
    // Der clean-lead hat keinen DupOf-Wert — kein anderer Lead-Name darf
    // im "Doppelt zu"-Kontext erscheinen. Verifizierte Referenz: der Dubletten-
    // Name darf hier NICHT auftauchen.
    await expect(page.getByText(refName, { exact: false })).toHaveCount(0, { timeout: 10000 });
  });
});
