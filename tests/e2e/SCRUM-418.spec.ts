import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-418] AK4 — Wiederaufmachen über die Lightning-UI, dann
 * Reaktivierungszahl aus dem Org (SOQL) lesen.
 *
 * Der UI-Teil übt die INTERAKTION: Status inline Closed -> New, Speichern.
 * Lightning speichert per REST — derselbe externe API-Pfad, in dem der
 * Zähler in der Tester-Session (2026-09-18, Test-Org devops-agent@cline.test)
 * zweifach gehoben wurde (7x reproduziert):
 *
 *   In-Org-Apex-DML (sf apex run):  1 Reopen -> Zaehler 1  (korrekt)
 *   externes REST/CLI-Update:       1 Reopen -> Zaehler 2  (DEFECT)
 *
 * Der READBACK läuft per SOQL gegen das Zielsystem — das Feld steht in
 * geschlossener Shadow-Root (Classic-Layout-in-Lightning), Light-DOM-Reader
 * sind dort nicht tragfähig (Skill: salesforce-playwright-session §4b).
 *
 * Erwartet nach genau EINER Wiederaufmachung: Zaehler == 1.
 * Bekannter Defekt (Bug SCRUM-419): Zaehler == 2 -> dieser Test rot.
 * Nach dem Fix muss er Gruen werden — er ist der AK4-Verifikator.
 */

const ORG = 'devops-agent@cline.test';

function cli(args: string): string {
  return execSync(`FORCE_COLOR=0 NO_COLOR=1 sf ${args}`, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function sfJson(args: string): any {
  const raw = cli(args);
  return JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
}

/** frischen, sofort geschlossenen Case anlegen (Schliessen zaehlt NICHT).
 *  Origin wird mitgelegt: es ist ein Pflichtfeld (isRequired), und ohne
 *  Wert weist der org-seitige Save-Validator den Status-Change zurueck
 *  ("Case Origin — Complete this field.") — der Trigger bliebe dabei
 *  unerreichbar.  (VERIFIZIERT 2026-09-18: Error-Dialog nach Save.) */
function createClosedFixture(): string {
  const subject = `SCRUM418_UICASE_${Date.now()}`;
  const id = sfJson(
    `data create record -o ${ORG} -s Case -v 'Subject=${subject} Origin=Phone' --json`,
  ).result.id as string;
  sfJson(
    `data update record -o ${ORG} -s Case -i ${id} -v 'Status=Closed' --json`,
  );
  return id;
}

/** Reaktivierungszahl direkt aus der Org lesen (Zielsystem, nicht DOM).
 *  Wirft, wenn der Record nicht lesbar ist — ein stiller 0-Rückgabewert hat
 *  hier den Test in die Irre gefuehrt (falsch-Grün statt falsch-Rot). */
function readReactivationCount(caseId: string): number {
  const q = sfJson(
    `data query -o ${ORG} --query "SELECT Id, Reactivation_Count__c FROM Case WHERE Id = '${caseId}'" --json`,
  );
  const rec = q.result.records.find((r: any) => r.Id === caseId);
  if (!rec) throw new Error(`Readback: Case ${caseId} in der Org nicht lesbar`);
  return Number(rec.Reactivation_Count__c ?? 0);
}

async function reopenViaUi(page: Page, caseId: string): Promise<void> {
  await openRecordDetails(page, `/lightning/r/Case/${caseId}/view`);

  // Status inline editieren: Closed -> New.
  // VERIFIZIERT (2026-09-18, ariaSnapshot nach Klick):
  //   - Read-Mode: Feld rendert als Paragraph (kein Input!) + Button
  //     "Edit Status" (aria-label).  -> GETBYLABEL('STATUS') FINDET IN NICHTS.
  //   - Edit-Mode: ComboBox mit Accessible Name "Status" + Buttons
  //     "Save"/"Cancel".
  await page.getByRole('button', { name: 'Edit Status' }).first().click();
  await page.waitForTimeout(1500);

  const statusCombo = page.getByLabel('Status', { exact: true }).first();
  await statusCombo.click();
  await page.waitForTimeout(700);
  await page.getByRole('option', { name: 'New' }).first().click();
  await page.waitForTimeout(700);

  // Speichern.
  await page.getByRole('button', { name: 'Save' }).first().click();

  // Speichern-Effekt: Record-Seite rendert zurueck (Edit-Buttons verschwinden).
  await page
    .getByRole('button', { name: 'Edit Status' })
    .first()
    .waitFor({ state: 'visible', timeout: 15000 })
    .catch(() => {});
  await page.waitForTimeout(2000);
}

test.describe('[SCRUM-418] AK4 — Wiederaufmachen ueber Lightning-UI', () => {
  let caseId = '';

  test.beforeAll(() => {
    caseId = createClosedFixture();
  });

  test('AC4: Reopen ueber UI-Save -> Reaktivierungszahl steigt exakt um 1 (auf 1)', async ({
    page,
  }) => {
    const before = readReactivationCount(caseId);
    expect(before, 'Startwert: gerade geschlossener Fall muss Zaehler 0 haben').toBe(0);

    await reopenViaUi(page, caseId);

    // Der Reopen ist erst dann getestet, wenn der Status im Org WIRKLICH New ist.
    const q = sfJson(
      `data query -o ${ORG} --query "SELECT Id, Status FROM Case WHERE Id = '${caseId}'" --json`,
    );
    const statusAfter: string = q.result.records.find((r: any) => r.Id === caseId)?.Status ?? '';
    expect(statusAfter, 'UI-Save muss den Status auf New gebracht haben (sonst war der Trigger nie erreichbar)').toBe('New');

    const after = readReactivationCount(caseId);
    expect(
      after,
      `Zaehler nach genau EINEM Reopen ueber die UI: erwartet 1, beobachtet ${after} ` +
        `(Defekt SCRUM-419: REST-Save-Pfad feuert den Reaktivierungs-Trigger ` +
        `mehrfach — Debug-Log 07LWU00000Pbwhl2AB belegt 4 AfterUpdate-Feuerungen ` +
        `und 2 Handler-DB-Schreibungen je Reopen)`,
    ).toBe(1);
  });
});
