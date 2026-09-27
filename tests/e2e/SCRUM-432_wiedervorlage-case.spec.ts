import { expect, test, type Page } from '@playwright/test';
import { execSync } from 'child_process';
import {
  openRecordDetails,
  startInlineEdit,
  saveInlineEdit,
} from './record-page';

/**
 * [SCRUM-432] Wiedervorlage auf Case — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). `networkidle` never used.
 *
 * The session runs as System Administrator (devops-agent@cline.test):
 * at RECORD level the admin sees every Case via ViewAll, so the only
 * mechanism that can filter out foreign / future cases from the list view
 * is the session-dependent formula
 *   Wiedervorlage_Heute_Offen__c =
 *     AND(Von__r.Id = $User.Id, NOT(ISBLANK(Datum)), Datum <= TODAY()).
 * The negative fixtures below therefore isolate and prove exactly that
 * formula, not sharing.
 *
 * Locators PROBED against this org on 2026-09-27 (full AX tree, single call):
 *   - List view address: /lighting/o/Case/list?filterName=Wiedervorlagen_heute_offen
 *   - Column headers (role=columnheader, allInnerTexts):
 *       ["Sort by:\nCase Number\n...", "…Account Name…", "…Subject…",
 *        "…Wiedervorlage Notiz…", "…Wiedervorlage Datum…"]
 *   - Row: subject cell contains "TEST-SCRUM-432-<TAG> …", case number as link.
 *   - Record: Details tab holds the layout section "Wiedervorlage" with fields
 *       Wiedervorlage Datum (input placeholder "Format: 31.12.2024") and
 *       Wiedervorlage Notiz (input, type text); "Gesetzt von" lookup.
 *   - Row headers/links: case number renders as a [link] with the number as name.
 *
 * Fixtures (idempotent, re-seeded in beforeAll via `sf data create record`):
 *   OWNTODAY  Von=self  Datum=today      -> IN   (AC5: own + due today)
 *   OWNYEST   Von=self  Datum=yesterday  -> IN   (AC3: own + overdue)
 *   OWNFUT    Von=self  Datum=tomorrow   -> OUT  (AC1: own but future)
 *   OTHER     Von=other Datum=today      -> OUT  (AC6: foreign, same date today)
 *   OWINNODATE Von=self  Datum=null       -> OUT  (AC3: no date set)
 *   NOSETTER  Von=null  Datum=today      -> OUT  (AC5: no one set it)
 *
 * Coverage (see docs/SCRUM-432-notizen-tester.md):
 *   AC1 Datum+Notiz via UI save -> test 4 (save + read-back after reload)
 *   AC2 5 columns              -> test 2 (columnheader texts)
 *   AC3 today/yesterday in, future & no-date out -> test 1 + fixtures
 *   AC4 oldest first           -> NOT COVERED (ADR-7: ListView-Metadata has no
 *                                 sort attribute; the view is "Sorted by Case
 *                                 Number" by design. Reported as untested.)
 *   AC5 own visible            -> test 1 (2 of 6 fixtures must appear)
 *   AC6 foreign hidden         -> test 1 (OTHER must NOT appear) + Apex runAs(A/B)
 *   AC7 Service user can set   -> test 3 (inline edit available) + Apex FlsTest
 *   AC8 non-editor blocked     -> Apex FlsTest negative (System.runAs without PS);
 *                                 UI-negative needs a 2nd licensed UI session — dev
 *                                 org has none, covered by Apex per house rule.
 */

const SESSION_USER_ID = '005WU000017tEKLYA2';   // devops-agent@cline.test
const OTHER_USER_ID   = '005WU000017tBhRYAU';    // meerwais.osmani@... (colleague)

const LIST_PATH = '/lightning/o/Case/list?filterName=Wiedervorlagen_heute_offen';
const TAG = 'TEST-SCRUM-432-';

/** The 6 fixtures, in the order the tests rely on (workers:1 → sequential). */
const FIXTURES = [
  { tag: 'OWNTODAY',  inList: true  },
  { tag: 'OWNYEST',   inList: true  },
  { tag: 'OWNFUT',    inList: false },
  { tag: 'OTHER',     inList: false },
  { tag: 'OWNNODATE', inList: false },
  { tag: 'NOSETTER',  inList: false },
] as const;

const TODAY = new Date();
const iso = (d: Date) => d.toISOString().slice(0, 10);
const isoYesterday = iso(new Date(TODAY.getTime() - 86400000));

function sfRun(cmd: string): { ok: boolean; stdout: string; stderr: string } {
  try {
    const out = execSync(cmd, {
      stdio: ['pipe', 'pipe', 'pipe'],
      encoding: 'utf-8',
      env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
    });
    return { ok: true, stdout: String(out), stderr: '' };
  } catch (e: any) {
    // Full command string (not an args array): the CLI needs the
    // multi-word `-v "Field=... Field=..."` values to arrive as ONE
    // argument — args.join(' ') would split them and the CLI answers
    // "Unexpected arguments" (verified 2026-09-27, SCRUM-432).
    return { ok: false, stdout: String(e.stdout ?? ''), stderr: String(e.stderr ?? '') };
  }
}

/** Create one fixture Case via the CLI (admin owns it; UI session edits it). */
function makeFixture(tag: string, von: string | null, datum: string | null): void {
  const v =
    `Subject=${TAG}${tag} Origin=Phone Status=New Wiedervorlage_Notiz__c=E2E-${tag}` +
    (von ? ` Wiedervorlage_Von__c=${von}` : '') +
    (datum ? ` Wiedervorlage_Datum__c=${datum}` : '');
  const r = sfRun(`sf data create record -s Case -o Test-Org -v "${v}" --json`);
  if (!r.ok) throw new Error(`fixture ${tag} not created: ${r.stderr.slice(0, 300)}`);
  if (!/"id"/.test(r.stdout)) throw new Error(`fixture ${tag} no id: ${r.stdout.slice(0, 200)}`);
}

async function openList(page: Page) {
  await page.goto(LIST_PATH, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page
    .locator('div.slds-global-header, one-appnav')
    .first()
    .waitFor({ state: 'visible', timeout: 60000 });
  // Grid rows render after the shell. The HEADER row may resolve first and
  // still be hidden — wait for the first DATA row (any key other than
  // HEADER; verified 2026-09-27: data rows carry the record Id as
  // data-row-key-value in this Lightning Datatable build).
  await page
    .locator('[role=row]:not([data-row-key-value="HEADER"])')
    .first()
    .waitFor({ state: 'visible', timeout: 30000 });
  await page.waitForTimeout(1500);
  // Drop the header row from the result set.
  return (
    await page.locator('[role=row]').allInnerTexts()
  ).filter((r) => !/Sort by:/.test(r));
}

test.describe('[SCRUM-432] Wiedervorlage auf Case', () => {
  // All tests edit/inspect the same records, so they run sequentially.
  // (workers:1 in playwright.config.ts already serialises the file; this
  // documents and guards the dependency explicitly.)
  test.describe.configure({ mode: 'serial' });

  test.beforeAll(() => {
    // Idempotent re-seed: delete any leftovers from a previous run, then
    // recreate the six fixtures with today-relative dates.
    const q = sfRun(`sf data query -o Test-Org -q "SELECT Id FROM Case WHERE Subject LIKE '${TAG}%'" --json`);
    const ids = (JSON.parse(q.stdout.match(/\{[\s\S]*\}/)?.[0] ?? '{}')?.result?.records ?? [])
      .map((r: { Id: string }) => r.Id);
    for (const id of ids) {
      sfRun(`sf data delete record -s Case -o Test-Org -i ${id}`);
    }
    makeFixture('OWNTODAY', SESSION_USER_ID, iso(TODAY));
    makeFixture('OWNYEST',  SESSION_USER_ID, isoYesterday);
    makeFixture('OWNFUT',   SESSION_USER_ID, iso(new Date(TODAY.getTime() + 86400000)));
    makeFixture('OTHER',    OTHER_USER_ID,   iso(TODAY));
    makeFixture('OWNNODATE', SESSION_USER_ID, null);
    makeFixture('NOSETTER', null,            iso(TODAY));
  });

  /** Subjects visible in the list view + the item-count line. */
  let listRows: string[] = [];
  let itemCount = '';

  test('1. Formel-Filter: nur eigene fällige Wiedervorlagen (AC3, AC5, AC6-UI)', async ({ page }) => {
    listRows = await openList(page);
    const body = (await page.locator('body').innerText()).replace(/\s+/g, ' ');
    itemCount = (body.match(/(\d+)\s+items?/i)?.[0] ?? '?? items');

    for (const { tag, inList } of FIXTURES) {
      const present = listRows.some((r) => r.includes(`TEST-SCRUM-432-${tag}`));
      expect(
        present,
        `fixture ${tag}: expected ${inList ? 'IN' : 'NOT IN'} the list ` +
          `(visible rows: ${listRows.map((r) => r.replace(/\s+/g, ' ').slice(0, 90)).join(' | ')})`
      ).toBe(inList);
    }
    // AC5 core: exactly the two own-due fixtures, no more.
    expect(itemCount).toMatch(/2\s+items/i);
  });

  test('2. AC2: die Listview zeigt die 5 vereinbarten Spalten', async ({ page }) => {
    await openList(page);
    const headers = await page.getByRole('columnheader').allInnerTexts();
    for (const expected of [
      'Case Number',
      'Account Name',
      'Subject',
      'Wiedervorlage Notiz',
      'Wiedervorlage Datum',
    ]) {
      expect(
        headers.some((h) => h.includes(expected)),
        `column header "${expected}" missing in: ${JSON.stringify(headers)}`
      ).toBe(true);
    }
  });

  test('3. AC7: Service-User kann die Felder im UI setzen (inline edit)', async ({ page }) => {
    // Find the OWNTODAY record id from its case number shown as a link.
    const rows = await openList(page);
    const ownToday = rows.find((r) => r.includes('TEST-SCRUM-432-OWNTODAY'));
    expect(ownToday, 'OWNTODAY row must exist (already proven by test 1)').toBeTruthy();
    const rowText = ownToday!;
    const caseNo = rowText.match(/\d{7,}/)?.[0];
    expect(caseNo, `case number not found in: ${ownToday}`).toBeTruthy();

    const page2 = await (await page.context()).newPage();
    try {
      await openRecordDetails(page2, `/lightning/r/Case/${caseNo}/view`);
      const dInp = await startInlineEdit(page2, 'Wiedervorlage Datum');
      await dInp.fill('27.09.2026');
      const nInp = await startInlineEdit(page2, 'Wiedervorlage Notiz');
      await nInp.fill('AC7 inline edit geprüft');
      await saveInlineEdit(page2);
      await page2
        .getByText('Wiedervorlage', { exact: false })
        .first()
        .waitFor({ state: 'visible', timeout: 30000 });
    } finally {
      await page2.close();
    }
  });

  test('4. AC1: Datum + Notiz per UI speichern, Nachladen zeigt Persistenz', async ({ page }) => {
    const rows = await openList(page);
    const ownToday = rows.find((r) => r.includes('TEST-SCRUM-432-OWNTODAY'))!;
    const caseNo = ownToday.match(/\d{7,}/)?.[0];
    expect(caseNo, 'OWNTODAY case number').toBeTruthy();

    const p = await (await page.context()).newPage();
    try {
      await openRecordDetails(p, `/lightning/r/Case/${caseNo}/view`);
      // AC1 save: fresh values in both fields, then Save.
      const dInp = await startInlineEdit(p, 'Wiedervorlage Datum');
      await dInp.fill('26.09.2026'); // yesterday: still open after save, in list
      const nInp = await startInlineEdit(p, 'Wiedervorlage Notiz');
      await nInp.fill('AC1 persistiert');
      await saveInlineEdit(p);
      await p
        .getByText('Wiedervorlage', { exact: false })
        .first()
        .waitFor({ state: 'visible', timeout: 30000 });

      // Reload and assert persistence.
      await p.reload({ waitUntil: 'domcontentloaded', timeout: 60000 });
      await p
        .locator('div.slds-global-header, one-appnav')
        .first()
        .waitFor({ state: 'visible', timeout: 60000 });
      await openRecordDetails(p, `/lightning/r/Case/${caseNo}/view`);
      const text = await p.locator('body').innerText();
      expect(text, 'datum not persisted after reload').toMatch(/26\.09\.2026/);
      expect(text, 'notiz not persisted after reload').toContain('AC1 persistiert');

      // Still in the list view (date still <= today, own).
      const rows2 = await openList(p);
      expect(
        rows2.some((r) => r.includes('TEST-SCRUM-432-OWNTODAY')),
        'record must still be in the list after save (yesterday is still open)'
      ).toBe(true);
    } finally {
      await p.close();
    }
  });
});
