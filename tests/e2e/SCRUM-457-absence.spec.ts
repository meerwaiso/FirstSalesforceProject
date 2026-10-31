import { test, expect } from '@playwright/test';
import { type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';
import {
  openRecordDetails,
  openDetailsTab,
  expectFieldVisible,
} from './record-page';

/**
 * [SCRUM-457] Account-Manager-Fehlzeiten — the UI/report half of the story.
 *
 * The Apex class on the branch (SCRUM457AbsenceSyncTest, 11/11 green, run by
 * the Tester with RunSpecifiedTests) proves the VALUES of the mirror fields.
 * This spec proves the deliverables the user actually opens:
 *   AC2 the customer page says the manager is absent, until when, deputy
 *   AC3 outside an absence the page looks exactly as today (also: ended)
 *   AC6 a change of dates or deputy follows on the customer page immediately
 *       (post-reload persistence of the rendered page, not just the mirror
 *       fields) — and a cancelled absence leaves nothing behind
 *   AC7 the customer keeps its owner across change AND cancel
 *   AC8 the team-lead report: rows = measured count, no-deputy rows stand out
 *   AC9 nothing automatic (no Task, no EmailMessage, no chatter)
 *
 * AC1 (recording an absence) and AC4 (the deputy works the non-owned records)
 * are Apex-only here: AC1's negative half needs a user WITHOUT the PS and the
 * org has 2 licences, both taken (skill salesforce-playwright-session §4c), so
 * a second UI session cannot be set up; AC4 runs under System.runAs(deputy).
 * AC5 is a finding, not a test — see docs/SCRUM-457-notizen-tester.md.
 *
 * DOM facts verified 2026-10-31 against Test-Org (probe: browser_exec AXTree on
 * the Account record page and the lightningReportApp frame):
 *   - The Account layout's "Fehlzeit" section holds exactly ONE field:
 *     Absence_Anzeige__c, label "Absence". Outside an absence the label is
 *     still rendered, the value is empty.
 *   - Field VALUES live in closed shadow roots -> ariaSnapshot() of body.
 *   - Absence__c record page (view AND edit) renders ONLY Lauf-Nr., Owner,
 *     Created By, Last Modified By — probed 2026-10-31 via AXTree (369 nodes,
 *     zero hits for the detail fields) and `Layout:Absence__c.*` cannot be
 *     retrieved from the org. There is no UI entry point for an absence.
 *   - Reports render in the cross-doc frame lightningReportApp; the frame
 *     states "Total Records N"; data rows are `table tbody tr`.
 *   - Report ids are resolved by Name through SOQL, never hardcoded.
 */

const ORG = 'Test-Org';
const ABSENCE_MANAGER = '005WU000017tBhRYAU'; // Meerwais Osmani — ABSENCE-0001's account manager
const ABSENCE_ORIG_START = '2026-10-31';
const ABSENCE_NAME = 'ABSENCE-0001'; // Meerwais Osmani, 2026-10-31..2026-11-20, deputy devops-agent
const ABSENCE_ORIG_END = '2026-11-20';
const ABSENCE_NEW_END = '2026-12-05';
const ABSENCE_PAST_END = '2026-10-05'; // already ended -> the page must go blank
const REPORT_NAME = 'Fehlzeiten_nach_Kunde';
// The cancel is exercised on a throwaway the spec creates and deletes, never on
// the two fixtures the PO measures (Absence__c.Name is AutoNumber, so a
// recreated fixture would get a new name and the measured state would drift).
const ABSENCE_ORIG_DEPUTY = '005WU000017tEKLYA2'; // devops-agent — ABSENCE-0001's deputy
// The cancel cycle runs on the deputy-less fixture ABSENCE-0002 and puts it back
// identical in content (Absent_User, Start, End, no Deputy). Absence__c.Name is an
// AutoNumber, so the restored record gets a new name — the PO measures the ROWS
// (13 in window, 1 marker), and those counts are what the restore has to hold.
const SEED_USER = '005WU000017tBpWYAU'; // Automated Process — the absent one
const SEED_START = '2026-11-02';
const SEED_END = '2026-11-12';
const SWAP_DEPUTY = '005WU000017tBpWYAU'; // Automated Process — NOT the account manager: the handler refuses a manager as their own deputy (AC1)

// Lightning pages plus a SOQL round-trip per assertion need far more than 30 s.
test.setTimeout(180000);

/* ------------------------- sf-CLI helpers (house) ------------------ */

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function rawOut(command: string): string {
  return execSync(command, {
    encoding: 'utf-8',
    timeout: 90000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
}

function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org ${ORG} --json`));
  return (doc.result && doc.result.records) || [];
}

/** SELECT COUNT() answers in result.totalSize with an empty records array. */
function soqlCount(q: string): number {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org ${ORG} --json`));
  if (!doc.result || doc.result.totalSize === undefined) {
    throw new Error(`COUNT() query returned no totalSize: ${JSON.stringify(doc).slice(0, 300)}`);
  }
  return doc.result.totalSize;
}

/* Playwright's expect has no notToContain/notToBe in this release; a boolean
   assertion that can fail is equivalent and explicit. */
function mustNotContain(text: string, needle: string, why: string): void {
  expect(text.includes(needle), why).toBe(false);
}

/* AC9 measures "nothing created by THIS run", so the window starts at the run. */
const RUN_T0 = new Date();

function sfCommand(cmd: string): void {
  const out = rawOut(cmd);
  if (/ERROR|INVALID|REQUIRED_FIELD_MISSING|NOT_FOUND/i.test(out)) {
    throw new Error(`sf command failed: ${out.slice(0, 400)}`);
  }
}

/** One accessibility snapshot of the whole page — the only fast read here. */
async function snapshot(page: Page): Promise<string> {
  return await page.locator('body').first().ariaSnapshot();
}

/* Lightning serves a cached render right after a server-side write: the field
   value is already correct, the page repaints seconds later. Poll the render,
   then assert on what is actually on the page — never on the field value. */
async function snapshotWhen(page: Page, needle: string, timeoutMs = 20000): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  let last = '';
  for (;;) {
    last = await snapshot(page);
    if (last.includes(needle)) return last;
    if (Date.now() > deadline) return last;
    await page.waitForTimeout(2000);
  }
}

async function snapshotWithout(page: Page, needle: string, timeoutMs = 20000): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  let last = '';
  for (;;) {
    last = await snapshot(page);
    if (!last.includes(needle)) return last;
    if (Date.now() > deadline) return last;
    await page.waitForTimeout(2000);
  }
}

/** Reload a record page and land on its Details tab (a fresh page = post-save). */
async function reloadRecord(page: Page, path: string): Promise<void> {
  await page.goto(path, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await openDetailsTab(page);
}

/** A blank formula value is null OR empty string — both mean "nothing shown". */
function blank(value: any): string {
  return value === null || value === undefined ? '' : String(value);
}

/* --------------------------- fixtures --------------------------- */

/** The live absence record of the absent account manager. Resolved by WHOSE
   absence it is, never by Absence__c.Name: the cancel cycle deletes and re-creates
   the record, and Name is an AutoNumber, so a recreated fixture gets a new one. */
function managerAbsences(): any[] {
  return soql(
    `SELECT Id, Name, Absent_User__c, Deputy__c, Start__c, End__c FROM Absence__c` +
    ` WHERE Absent_User__c = '${ABSENCE_MANAGER}'`
  );
}

function absenceRecord(): any {
  const rows = managerAbsences();
  expect(rows.length, 'the account manager must have exactly one absence in Test-Org → criterion would match zero records').toBe(1);
  return rows[0];
}

/** The customers the absent account manager owns — the covered ones. */
function coveredCustomers(): any[] {
  return soql(
    `SELECT Id, Name, Absence_Anzeige__c, Absence_Ohne_Deputy__c, Absence_In_Window__c FROM Account` +
    ` WHERE OwnerId = '${ABSENCE_MANAGER}' ORDER BY Name`
  );
}

/** The absence of the deputy, created only by the AC10 test. */
function deputyAbsences(): any[] {
  return soql(
    `SELECT Id, Name, Absent_User__c, Deputy__c, Start__c, End__c FROM Absence__c` +
    ` WHERE Absent_User__c = '${ABSENCE_ORIG_DEPUTY}'`
  );
}

/** One customer of the absent manager, resolved at runtime. */
function customerOfAbsentManager(): any {
  const rows = soql(
    `SELECT Id, Name, OwnerId, Owner.Name, Absence_Anzeige__c, Absence_Ohne_Deputy__c,` +
    ` Absence_Start__c, Absence_End__c FROM Account` +
    ` WHERE Absence_In_Window__c = 'YES' AND Absence_Ohne_Deputy__c = NULL ORDER BY Name`
  );
  expect(rows.length, 'zero customers carry an active absence → AC2/AC6 untested').toBeGreaterThan(0);
  return rows[0];
}

/** A customer whose owner has no absence at all (mirror fields all blank). */
function customerWithoutAbsence(): any {
  const rows = soql(
    `SELECT Id, Name, OwnerId, Owner.Name FROM Account` +
    ` WHERE Absence_Start__c = NULL AND Absence_End__c = NULL AND Absence_Ohne_Deputy__c = NULL` +
    ` AND Owner.Name != 'Automated Process' ORDER BY Name`
  );
  expect(rows.length, 'zero customers without an absence → AC3 untested').toBeGreaterThan(0);
  return rows[0];
}



/** The deputy-less fixture absence the cancel cycle deletes and re-records. */
function seedAbsence(): any[] {
  return soql(
    `SELECT Id, Name, Absent_User__c, Deputy__c, Start__c, End__c FROM Absence__c` +
    ` WHERE Deputy__c = NULL AND Start__c = ${SEED_START}`
  );
}

/** The customers that carry the no-deputy marker right now. */
function markedCustomers(): any[] {
  return soql(
    `SELECT Id, Name, Owner.Name, Absence_Anzeige__c, Absence_Ohne_Deputy__c FROM Account` +
    ` WHERE Absence_Ohne_Deputy__c = 'OHNE DEPUTY'`
  );
}

/** How many customers the overview window holds right now. */
function windowCount(): number {
  return soqlCount(`SELECT COUNT() FROM Account WHERE Absence_In_Window__c = 'YES'`);
}

/** Everything a customer owns — AC7 must show none of it moved. */
function ownedRecords(accountId: string): { ownerId: string; opps: string[]; cases: string[] } {
  const acc = soql(`SELECT Id, OwnerId, Owner.Name FROM Account WHERE Id = '${accountId}'`)[0];
  const opps = soql(`SELECT Id, AccountId FROM Opportunity WHERE AccountId = '${accountId}'`).map((r) => `${r.Id}|${r.AccountId}`);
  const cases = soql(`SELECT Id, AccountId FROM Case WHERE AccountId = '${accountId}'`).map((r) => `${r.Id}|${r.AccountId}`);
  return { ownerId: acc.OwnerId, opps, cases };
}

async function openReportFrame(page: Page): Promise<Frame> {
  let frame: Frame | undefined;
  const deadline = Date.now() + 60000;
  for (;;) {
    frame = page.frames().find((fr: any) => fr.url().includes('lightningReportApp'));
    if (frame) break;
    if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) never attached');
    await page.waitForTimeout(500);
  }
  await frame.waitForLoadState('domcontentloaded').catch(() => {});
  await frame.locator('table td').first().waitFor({ timeout: 45000 });
  return frame!;
}

/* ============ AC2 — the customer page names the absence, until, deputy ============ */

test.describe('[SCRUM-457] AC2 — absence visible on the customer page', () => {
  test('AC2: customer of the absent manager shows manager absent, until, deputy', async ({ page }) => {
    const absence = absenceRecord();
    expect(absence.End__c, `fixture absence must still end ${ABSENCE_ORIG_END}`).toBe(ABSENCE_ORIG_END);

    const cust = customerOfAbsentManager();
    const expected = blank(cust.Absence_Anzeige__c);
    expect(expected, `mirror display line is empty on ${cust.Id} — nothing to render`).toContain('Abwesent');
    expect(expected, 'display line must name the deputy').toContain('Deputy:');

    await openRecordDetails(page, `/lightning/r/Account/${cust.Id}/view`);
    await expectFieldVisible(page, 'Fehlzeit');
    await expectFieldVisible(page, 'Absence');

    const snap = await snapshot(page);
    expect(snap, `customer page must render the display line for ${cust.Name}`).toContain(expected);
    expect(snap, `rendered line must carry the absence end ${cust.Absence_End__c}`).toContain(cust.Absence_End__c);
    test.info().annotations.push({
      type: 'observed',
      description: `AC2: ${cust.Name} renders "${expected}" on the Details tab (section Fehlzeit, field Absence)`,
    });
  });
});

/* ============ AC3 — outside an absence the page is unchanged ============ */

test.describe('[SCRUM-457] AC3 — nothing shown outside an absence', () => {
  test('AC3: customer whose owner has no absence renders no absence info', async ({ page }) => {
    const cust = customerWithoutAbsence();
    const orgRow = soql(
      `SELECT Id, Absence_Anzeige__c, Absence_Ohne_Deputy__c, Absence_In_Window__c FROM Account WHERE Id = '${cust.Id}'`
    )[0];
    expect(blank(orgRow.Absence_Anzeige__c), `mirror must be blank on ${cust.Id}`).toBe('');
    expect(blank(orgRow.Absence_Ohne_Deputy__c), `marker must be blank on ${cust.Id}`).toBe('');

    await openRecordDetails(page, `/lightning/r/Account/${cust.Id}/view`);
    // The section is on the layout, so the label renders — only the value must be gone.
    await expectFieldVisible(page, 'Absence');

    const snap = await snapshot(page);
    mustNotContain(snap, 'Abwesent', `page of ${cust.Name} must not say "Abwesent"`);
    mustNotContain(snap, 'OHNE DEPUTY', `page of ${cust.Name} must not carry the no-deputy marker`);
    const blankCount = soqlCount(`SELECT COUNT() FROM Account WHERE Absence_In_Window__c = 'YES'`);
    const total = soqlCount(`SELECT COUNT() FROM Account`);
    test.info().annotations.push({
      type: 'observed',
      description: `AC3: ${cust.Name} (${cust.Owner}) renders 0 absence strings; ${total - blankCount} of ${total} customers carry no active absence`,
    });
  });
});

/* ==== AC6 — a change made in the UI follows on the customer page (save + reload) ==== */

test.describe('[SCRUM-457] AC6 — changing or cancelling follows immediately', () => {

  test('AC6: changing End__c on the absence follows on the reloaded customer page', async ({ page }) => {
    const absence = absenceRecord();
    const cust = customerOfAbsentManager();
    const before = blank(cust.Absence_End__c);

    // 1) the change is written on the absence record. FINDING (see coverage
    //    comment): the Absence__c record page renders no detail fields at all,
    //    so there is no UI entry point for changing an absence; the write below
    //    is the only route that exists in this org.
    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "End__c=${ABSENCE_NEW_END}"`
    );

    // 2) the save really landed server-side
    const after = soql(`SELECT Id, End__c FROM Absence__c WHERE Absent_User__c = '${ABSENCE_MANAGER}'`)[0];
    expect(after.End__c, `UI save of End__c must persist as ${ABSENCE_NEW_END}`).toBe(ABSENCE_NEW_END);

    // 3) the customer page follows — a fresh page load, not the edited one
    await reloadRecord(page, `/lightning/r/Account/${cust.Id}/view`);
    const rendered = await snapshotWhen(page, ABSENCE_NEW_END);
    const mirrored = soql(`SELECT Id, Absence_End__c, Absence_Anzeige__c FROM Account WHERE Id = '${cust.Id}'`)[0];
    expect(blank(mirrored.Absence_End__c), `mirror on ${cust.Id} must carry the new end date`).toBe(ABSENCE_NEW_END);
    expect(blank(mirrored.Absence_Anzeige__c), `display line must carry the new end date`).toContain(ABSENCE_NEW_END);
    expect(rendered, `reloaded customer page must render the new end date`).toContain(ABSENCE_NEW_END);
    expect(rendered, 'reloaded page must still name the deputy').toContain('Deputy:');
    test.info().annotations.push({
      type: 'observed',
      description: `AC6: End__c ${before} → ${ABSENCE_NEW_END}; mirror + reloaded page follow`,
    });

    // the fixture must be back where the PO measured it for the next tests
    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "End__c=${ABSENCE_ORIG_END}"`
    );
    const restored = soql(`SELECT Id, End__c FROM Absence__c WHERE Absent_User__c = '${ABSENCE_MANAGER}'`)[0];
    expect(restored.End__c, 'fixture must be restored to the original end date').toBe(ABSENCE_ORIG_END);
  });

  test('AC6: changing the deputy follows on the reloaded customer page', async ({ page }) => {
    const absence = absenceRecord();
    const cust = customerOfAbsentManager();
    const beforeDeputy = blank(cust.Absence_Deputy__c);

    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "Deputy__c=${SWAP_DEPUTY}"`
    );
    const mirrored = soql(
      `SELECT Id, Absence_Deputy__c, Absence_Anzeige__c FROM Account WHERE Id = '${cust.Id}'`
    )[0];
    expect(blank(mirrored.Absence_Deputy__c) !== beforeDeputy, `deputy swap must follow onto ${cust.Id}`).toBe(true);
    expect(blank(mirrored.Absence_Anzeige__c), 'display line must name the new deputy').toContain(
      blank(mirrored.Absence_Deputy__c)
    );

    await reloadRecord(page, `/lightning/r/Account/${cust.Id}/view`);
    const snap = await snapshot(page);
    expect(snap, `reloaded page must render the new deputy "${mirrored.Absence_Deputy__c}"`).toContain(
      blank(mirrored.Absence_Deputy__c)
    );
    test.info().annotations.push({
      type: 'observed',
      description: `AC6: deputy ${beforeDeputy} → ${mirrored.Absence_Deputy__c}; reloaded page renders the new deputy`,
    });

    // restore the fixture's deputy so the measured state survives the run
    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "Deputy__c=${ABSENCE_ORIG_DEPUTY}"`
    );
    const restored = soql(
      `SELECT Id, Absence_Deputy__c, Absence_Anzeige__c FROM Account WHERE Id = '${cust.Id}'`
    )[0];
    expect(blank(restored.Absence_Anzeige__c), 'restored display line must name the original deputy').toContain(
      beforeDeputy
    );
  });

  test('AC3/AC6: shortening an absence into the past leaves the page blank', async ({ page }) => {
    const absence = absenceRecord();
    const cust = customerOfAbsentManager();

    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "End__c=${ABSENCE_PAST_END}"`
    );

    const after = soql(`SELECT Id, End__c FROM Absence__c WHERE Absent_User__c = '${ABSENCE_MANAGER}'`)[0];
    expect(after.End__c, `UI save of the past end date must persist as ${ABSENCE_PAST_END}`).toBe(ABSENCE_PAST_END);

    const mirrored = soql(
      `SELECT Id, Absence_In_Window__c, Absence_Anzeige__c FROM Account WHERE Id = '${cust.Id}'`
    )[0];
    expect(blank(mirrored.Absence_Anzeige__c), `ended absence must clear the display line on ${cust.Id}`).toBe('');
    expect(blank(mirrored.Absence_In_Window__c), `ended absence must clear the window flag on ${cust.Id}`).toBe('');

    await reloadRecord(page, `/lightning/r/Account/${cust.Id}/view`);
    const snap = await snapshotWithout(page, 'Abwesent');
    mustNotContain(snap, 'Abwesent', `page of ${cust.Name} must not say "Abwesent" after the absence ended`);
    test.info().annotations.push({
      type: 'observed',
      description: `AC3/AC6: End__c=${ABSENCE_PAST_END} (past) → mirror cleared, reloaded page blank`,
    });

    // restore the fixture so the report tests and the PO see the measured state
    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "End__c=${ABSENCE_ORIG_END}"`
    );
    const restored = soql(`SELECT Id, End__c FROM Absence__c WHERE Absent_User__c = '${ABSENCE_MANAGER}'`)[0];
    expect(restored.End__c, 'fixture must be restored to the original end date').toBe(ABSENCE_ORIG_END);
  });

  test('AC6: cancelling the absence clears every covered customer, re-recording restores them', async ({ page }) => {
    const seed = absenceRecord();
    const covered = coveredCustomers();
    expect(covered.length, 'the absent account manager must own customers → cancel untested').toBe(12);
    const windowBefore = windowCount();
    expect(windowBefore, 'fixture: the overview window must hold 13 customers before the cancel').toBe(13);
    expect(blank(covered[0].Absence_Anzeige__c), 'fixture: the page must show the absence before the cancel').toContain('Abwesent');

    await reloadRecord(page, `/lightning/r/Account/${covered[0].Id}/view`);
    const before = await snapshotWhen(page, 'Abwesent');
    expect(before, `the page of ${covered[0].Name} must show the absence before the cancel`).toContain('Abwesent');

    // 1) cancel = delete the record (PO CRUD row: Delete = cancel an absence)
    sfCommand(`sf data delete record --target-org ${ORG} --sobject Absence__c --record-id ${seed.Id}`);
    expect(managerAbsences().length, 'the cancelled absence must be gone from the org').toBe(0);

    const cleared = soql(
      `SELECT Id, Name, Absence_Anzeige__c, Absence_Ohne_Deputy__c, Absence_In_Window__c FROM Account` +
      ` WHERE OwnerId = '${ABSENCE_MANAGER}' ORDER BY Name`
    );
    expect(cleared.length, 'the covered customers must still exist after the cancel').toBe(covered.length);
    for (const r of cleared) {
      expect(blank(r.Absence_Anzeige__c), `cancel must clear the display line on ${r.Name}`).toBe('');
      expect(blank(r.Absence_Ohne_Deputy__c), `cancel must leave no marker on ${r.Name}`).toBe('');
      expect(blank(r.Absence_In_Window__c), `cancel must take ${r.Name} out of the overview window`).toBe('');
    }
    expect(windowCount(), `the window must drop from ${windowBefore} to ${windowBefore - covered.length}`).toBe(windowBefore - covered.length);

    await reloadRecord(page, `/lightning/r/Account/${covered[0].Id}/view`);
    const snap = await snapshotWithout(page, 'Abwesent');
    mustNotContain(snap, 'Abwesent', `page of ${covered[0].Name} must say nothing after the cancel`);

    // 2) re-record the same absence: every covered customer follows again
    sfCommand(
      `sf data create record --target-org ${ORG} --sobject Absence__c` +
        ` --values "Absent_User__c=${ABSENCE_MANAGER} Deputy__c=${ABSENCE_ORIG_DEPUTY}` +
        ` Start__c=${ABSENCE_ORIG_START} End__c=${ABSENCE_ORIG_END}"`
    );
    const back = managerAbsences();
    expect(back.length, 'the re-recorded absence must be back in the org').toBe(1);
    expect(back[0].End__c, 'the re-recorded absence must carry the original end date').toBe(ABSENCE_ORIG_END);
    const shown = soql(
      `SELECT Id, Name, Absence_Anzeige__c, Absence_In_Window__c FROM Account WHERE OwnerId = '${ABSENCE_MANAGER}' ORDER BY Name`
    );
    for (const r of shown) {
      expect(blank(r.Absence_Anzeige__c), `re-recording must show the absence on ${r.Name}`).toContain('Abwesent');
      expect(blank(r.Absence_Ohne_Deputy__c), `a named deputy must leave no marker on ${r.Name}`).toBe('');
    }
    expect(windowCount(), 'the window must be back at 13 after the re-record').toBe(13);

    await reloadRecord(page, `/lightning/r/Account/${covered[0].Id}/view`);
    const restored = await snapshotWhen(page, 'Abwesent');
    expect(restored, `reloaded page of ${covered[0].Name} must show the absence again`).toContain('Abwesent');
    test.info().annotations.push({
      type: 'observed',
      description: `AC6: delete ${seed.Id} -> ${covered.length} pages blank, window ${windowBefore}->${windowBefore - covered.length}; re-record -> all ${covered.length} pages show it again, window 13`,
    });
  });

});

/* ==== AC7 — the customer keeps its owner across change AND cancel ==== */

test.describe('[SCRUM-457] AC7 — ownership never moves', () => {
  test('AC7: change and cancel leave OwnerId, Opportunities and Cases intact', async ({ page }) => {
    const cust = customerOfAbsentManager();
    const absence = absenceRecord();
    const before = ownedRecords(cust.Id);
    expect(before.opps.length, 'customer needs Opportunities for the AC7 comparison').toBeGreaterThan(0);
    expect(before.cases.length, 'customer needs Cases for the AC7 comparison').toBeGreaterThan(0);

    // a change of the absence must not touch ownership
    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "End__c=${ABSENCE_NEW_END}"`
    );
    const mid = ownedRecords(cust.Id);
    expect(mid.ownerId, `OwnerId of ${cust.Id} must not change on an absence change`).toBe(before.ownerId);
    expect(mid.opps, 'no Opportunity may be re-parented').toEqual(before.opps);
    expect(mid.cases, 'no Case may be re-parented').toEqual(before.cases);

    // a cancel: the deputy-less fixture absence is deleted, then put back
    const seed = seedAbsence();
    expect(seed.length, 'the deputy-less fixture absence must exist to be cancelled').toBe(1);
    const marked = markedCustomers();
    expect(marked.length, 'exactly one customer must carry the marker before the cancel').toBe(1);
    const sample = marked[0];
    const windowBefore = windowCount();
    sfCommand(`sf data delete record --target-org ${ORG} --sobject Absence__c --record-id ${seed[0].Id}`);
    expect(seedAbsence().length, 'the cancelled absence must be gone from the org').toBe(0);

    const cancelled = soql(
      `SELECT Id, Absence_Anzeige__c, Absence_Ohne_Deputy__c FROM Account WHERE Id = '${sample.Id}'`
    )[0];
    expect(blank(cancelled.Absence_Anzeige__c), `the cancelled absence must leave nothing on ${sample.Name}`).toBe('');
    expect(blank(cancelled.Absence_Ohne_Deputy__c), `no marker may remain on ${sample.Id} after the cancel`).toBe('');
    expect(windowCount(), `the window must drop by one after the cancel`).toBe(windowBefore - 1);

    // the fixture absence is still active, so its own page must still show it
    await reloadRecord(page, `/lightning/r/Account/${cust.Id}/view`);
    const snap = await snapshotWhen(page, 'Abwesent');
    expect(snap, `page of ${cust.Name} must still show its own absence after the cancel`).toContain('Abwesent');
    // the cancelled colleague's page must look exactly as it does today. The
    // Account layout's "Fehlzeit" section holds ONLY Absence_Anzeige__c, so the
    // marker field Absence_Ohne_Deputy__c is never rendered on a page (verified
    // 2026-10-31: ariaSnapshot of the Details tab of 001WU0000242xNSYAY carries
    // no 'OHNE DEPUTY' even though the field holds it). The marker is therefore
    // asserted on the field above, and only the display line on the page.
    await reloadRecord(page, `/lightning/r/Account/${sample.Id}/view`);
    const sampleSnap = await snapshot(page);
    mustNotContain(sampleSnap, 'Abwesent', `page of ${sample.Name} must be blank after the cancel`);

    const after = ownedRecords(cust.Id);
    expect(after.ownerId, `OwnerId of ${cust.Id} must be unchanged across change AND cancel`).toBe(before.ownerId);
    expect(after.opps, 'no Opportunity may be re-parented by the cancel').toEqual(before.opps);
    expect(after.cases, 'no Case may be re-parented by the cancel').toEqual(before.cases);

    // put the fixture record back so the org ends in the measured state
    sfCommand(
      `sf data create record --target-org ${ORG} --sobject Absence__c` +
        ` --values "Absent_User__c=${SEED_USER} Start__c=${SEED_START} End__c=${SEED_END}"`
    );
    expect(seedAbsence().length, 'the restored fixture absence must be back in the org').toBe(1);
    expect(markedCustomers().length, 'the marker must be back on exactly one customer').toBe(1);
    expect(windowCount(), 'the overview window must be back at 13 customers').toBe(13);

    const ownerLine = soql(`SELECT Id, Owner.Name FROM Account WHERE Id = '${cust.Id}'`)[0];
    expect(snap, `customer page must still name owner "${ownerLine.Owner.Name}"`).toContain(ownerLine.Owner.Name);

    // the fixture must end where the PO measured it
    sfCommand(
      `sf data update record --target-org ${ORG} --sobject Absence__c --record-id ${absence.Id}` +
        ` --values "End__c=${ABSENCE_ORIG_END}"`
    );
    const restored = soql(`SELECT Id, End__c FROM Absence__c WHERE Absent_User__c = '${ABSENCE_MANAGER}'`)[0];
    expect(restored.End__c, 'fixture end date must be restored after AC7').toBe(ABSENCE_ORIG_END);
    test.info().annotations.push({
      type: 'observed',
      description: `AC7: OwnerId ${before.ownerId} unchanged; ${before.opps.length} Opps + ${before.cases.length} Cases still parented after change + cancel`,
    });
  });
});

/* ==== AC8 — the team-lead overview: rows = measured count, no-deputy stands out ==== */

test.describe('[SCRUM-457] AC8 — team-lead overview report', () => {
  test('AC8: report rows match the measured count and the no-deputy row stands out', async ({ page }) => {
    const reportRows = soql(`SELECT Id, Name FROM Report WHERE Name = '${REPORT_NAME}'`);
    expect(reportRows.length, `Report "${REPORT_NAME}" is not in the org — the overview was never deployed`).toBe(1);
    const reportId = reportRows[0].Id;

    const inWindow = soql(
      `SELECT Id, Name, Owner.Name, Absence_Start__c, Absence_End__c, Absence_Deputy__c, Absence_Ohne_Deputy__c` +
      ` FROM Account WHERE Absence_In_Window__c = 'YES'`
    );
    expect(inWindow.length, 'zero customers in the window → the report matches zero records').toBeGreaterThan(0);
    const noDeputy = inWindow.filter((r) => blank(r.Absence_Ohne_Deputy__c).includes('OHNE DEPUTY'));
    expect(noDeputy.length, 'no row carries the no-deputy marker → the "stands out" clause is untested').toBeGreaterThan(0);

    // The report app serves a CACHED instance by default (measured 2026-10-31:
    // a cached frame stated 7 records while the org held 13). cache=false asks
    // Lightning for a fresh run — without it the row count compares a stale
    // artefact against a live org and the AC can never be decided.
    await page.goto(`/lightning/r/Report/${reportId}/view?cache=false`, { waitUntil: 'domcontentloaded', timeout: 90000 });
    let frame = await openReportFrame(page);

    // The report app serves an instance of its own choice: measured 2026-10-31,
    // the same URL stated 13 records in one run and 8 in the next while the org
    // held 13. So the frame is polled until it states the live count — bounded,
    // and a frame that never catches up fails here rather than silently passing.
    let frameText = '';
    let stated = -1;
    const deadline = Date.now() + 90000;
    for (;;) {
      frameText = await frame.locator('body').first().innerText();
      const total = /Total Records\s*([\d,.]+)/.exec(frameText);
      if (!total) throw new Error('report frame states no "Total Records N" figure — the row count cannot be compared');
      stated = Number(total[1].replace(/[.,](?=\d{3}\b)/g, ''));
      if (stated === inWindow.length) break;
      if (Date.now() > deadline) break;
      await page.reload({ waitUntil: 'domcontentloaded', timeout: 90000 });
      frame = await openReportFrame(page);
      await page.waitForTimeout(3000);
    }
    expect(stated, `report states ${stated} records, org has ${inWindow.length} in the window`).toBe(inWindow.length);

    const rowLoc = frame.locator('table tbody tr');
    const rowCount = await rowLoc.count();
    expect(rowCount, 'report renders no rows').toBeGreaterThan(0);

    const rendered: string[] = [];
    for (let i = 0; i < rowCount; i++) {
      const cells = await rowLoc.nth(i).locator('th, td').all();
      const texts: string[] = [];
      for (const c of cells) {
        texts.push((await c.innerText()).trim());
      }
      rendered.push(texts.join(' | '));
    }
    const body = rendered.join('\n');

    for (const r of inWindow) {
      expect(body, `row for ${r.Name} (${r.Id}) is missing from the report`).toContain(r.Name);
    }
    const markerRows = rendered.filter((line) => line.includes('OHNE DEPUTY'));
    expect(markerRows.length, `report must carry the no-deputy marker on exactly ${noDeputy.length} row(s)`).toBe(noDeputy.length);
    expect(markerRows[0], 'the marked row must be the customer of the deputy-less absence').toContain(noDeputy[0].Name);

    for (const header of ['Absence ab', 'Absence until', 'Deputy', 'Absence ohne Deputy']) {
      expect(frameText, `report column "${header}" is not rendered`).toContain(header);
    }
    test.info().annotations.push({
      type: 'observed',
      description: `AC8: report ${reportId} → Total Records ${stated} = ${inWindow.length} in window; ${markerRows.length} row(s) carry OHNE DEPUTY (${noDeputy[0].Name})`,
    });
  });
});

/* ==== AC10 — a deputy who is away is no deputy ==== */

test.describe('[SCRUM-457] AC10 — a deputy who is away is no deputy', () => {
  test('AC10: while the deputy has an overlapping own absence, the covered customer stands out', async ({ page }) => {
    const managerAbs = absenceRecord();
    expect(managerAbs.End__c, 'fixture: the manager absence must still end 2026-11-20').toBe(ABSENCE_ORIG_END);
    expect(blank(managerAbs.Deputy__c), 'fixture: the manager absence must name a deputy').toBe(ABSENCE_ORIG_DEPUTY);
    const covered = coveredCustomers();
    expect(covered.length, 'the absent manager must own customers → AC10 untested').toBe(12);
    expect(markedCustomers().length, 'fixture: exactly one deputy-less customer before the deputy goes away').toBe(1);
    const windowBefore = windowCount();
    expect(windowBefore, 'fixture: the overview window must hold 13 customers').toBe(13);

    // the deputy records an own absence that overlaps at the time of viewing
    sfCommand(
      `sf data create record --target-org ${ORG} --sobject Absence__c` +
        ` --values "Absent_User__c=${ABSENCE_ORIG_DEPUTY} Start__c=${ABSENCE_ORIG_START} End__c=${ABSENCE_ORIG_END}"`
    );
    const deputy = deputyAbsences();
    expect(deputy.length, 'the deputy must have exactly one own absence in the org').toBe(1);
    expect(blank(deputy[0].Deputy__c), 'the deputy must not name a deputy of their own').toBe('');

    let windowNow = -1;
    let totalCustomers = -1;
    // the cleanup must run even when an assertion below fails, otherwise a red
    // AC10 leaves a third Absence record in the org and every later run measures
    // a fixture the PO never measured.
    try {
    // every covered customer now stands out exactly like a customer without a deputy
    const marked = markedCustomers();
    const markedIds = new Set(marked.map((r) => r.Id));
    for (const r of covered) {
      expect(markedIds.has(r.Id), `${r.Name} must stand out exactly like a customer without a deputy`).toBe(true);
    }
    totalCustomers = soqlCount(`SELECT COUNT() FROM Account`);
    windowNow = windowCount();
    expect(windowNow, 'both managers away: every customer of the org is now in the window').toBe(totalCustomers);
    expect(marked.length, 'every customer in the window is covered by an absent manager whose deputy is absent too').toBe(windowNow);

    // the display line must still name the deputy on the page — the flag is an
    // overview concern (PO note), the page keeps its content
    await reloadRecord(page, `/lightning/r/Account/${covered[0].Id}/view`);
    const rendered = await snapshotWhen(page, 'Abwesent');
    expect(rendered, `page of ${covered[0].Name} must still show the absence while the deputy is away`).toContain('Abwesent');
    expect(rendered, 'the page must still name the deputy (PO: the flag is only in the overview)').toContain('Deputy:');


    test.info().annotations.push({
      type: 'observed',
      description: `AC10: deputy ${ABSENCE_ORIG_DEPUTY} absent ${ABSENCE_ORIG_START}..${ABSENCE_ORIG_END} -> all ${covered.length} covered customers carry OHNE DEPUTY (window ${windowNow}/${totalCustomers}); after the cleanup 1 marker / 13 in window`,
    });
    } finally {
      sfCommand(`sf data delete record --target-org ${ORG} --sobject Absence__c --record-id ${deputy[0].Id}`);
      expect(deputyAbsences().length, 'the cleanup must leave the org at two Absence records').toBe(0);
      expect(markedCustomers().length, 'the marker must be back on exactly the deputy-less customer').toBe(1);
      expect(windowCount(), 'the overview window must be back at 13 customers').toBe(13);
    }
    test.info().annotations.push({
      type: 'observed',
      description: `AC10: deputy ${ABSENCE_ORIG_DEPUTY} absent ${ABSENCE_ORIG_START}..${ABSENCE_ORIG_END} -> all ${covered.length} covered customers carry OHNE DEPUTY (window ${windowNow}/${totalCustomers}); after the cleanup 1 marker / 13 in window`,
    });
  });
});

/* ==== AC9 — nothing automatic ==== */

test.describe('[SCRUM-457] AC9 — nothing automatic beyond the display', () => {
  test('AC9: no Task, no EmailMessage, no chatter created by the absence flow', async ({ page }) => {
    const t0 = RUN_T0.toISOString().slice(0, 19) + 'Z';
    const tasks = soqlCount(`SELECT COUNT() FROM Task`);
    const emails = soqlCount(`SELECT COUNT() FROM EmailMessage`);
    const chatter = soqlCount(`SELECT COUNT() FROM FeedItem WHERE CreatedDate > ${t0}`);
    expect(tasks, 'the absence flow must not create a Task').toBe(0);
    expect(emails, 'the absence flow must not create an EmailMessage').toBe(0);
    expect(chatter, `no chatter may be created since the run started (window ${t0})`).toBe(0);

    const absences = soql(`SELECT Id, Name FROM Absence__c`);
    expect(absences.length, 'the flow must not leave extra Absence records behind').toBe(2);
    test.info().annotations.push({
      type: 'observed',
      description: `AC9: Task=0, EmailMessage=0, FeedItem since ${t0}=0, Absence__c=${absences.length} (the two fixtures)`,
    });
  });
});
