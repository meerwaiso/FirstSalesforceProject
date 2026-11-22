import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-471] Key Account mark on the customer record — the UI half.
 *
 * Covers the acceptance criteria that are about what a colleague SEES and SAVES
 * on the Account detail page (the Apex pair SCRUM471KeyAccountTest /
 * SCRUM471KeyAccountFlsTest on the same branch covers the FLS split AC5/AC6/AC7
 * — a read-only colleague cannot be produced in this browser: both licences in
 * Test-Org are held by System Administrators and both PS holders hold Read AND Set).
 *
 *   AC1  a newly created customer reads "No" (new-record form + record page)
 *   AC2  set the mark and save -> the record reads "Yes" (rendered + SOQL)
 *   AC3  clear the mark and save -> the record reads "No" again (rendered + SOQL)
 *   AC4  the mark sits in the FIRST Details section next to Account Name, above
 *        the fold (no scrolling) — render proof, not layout XML
 *   AC8  setting/clearing changes nothing else: no EmailMessage, no Task, no new
 *        record, the customer's other fields untouched (count-based, non-vacuous
 *        halves: Case 681, Opportunity 157, Account count)
 *   AC9  the 251 customers that exist today still read "No" (0 marked before any
 *        test marks one)
 *
 * LOCATORS — every one probed against Test-Org on 2026-11-22
 * (`scratch/probe471b.mjs` / `probe471c.mjs`, storage state from the smoke run),
 * never guessed:
 *   - The record page opens on Related; the house helper openRecordDetails clicks
 *     Details and verifies the switch.
 *   - Page level `page.ariaSnapshot()` is the only read that sees the Details
 *     fields (closed shadow roots; `document.body.innerText` shows none of them).
 *     The field renders as one line: `- text: Key Account <value> Key Account`,
 *     where <value> is "True" when marked and "False" when not — a Checkbox in
 *     this org's locale renders True/False, NOT Yes/No.
 *   - Order of the first Details section (measured): Account Name, Phone,
 *     Key Account, Parent Account, Website. The next section heading
 *     (`heading "Wartungsvertrag" [level=3]`) comes AFTER the mark, so the mark
 *     is in the section carrying the name.
 *   - `button "Edit Key Account"` count = 1 on the Details tab (enters inline edit).
 *   - In edit mode the mark is exactly one `input[name="Is_Key_Account__c"]`
 *     type=checkbox; `.click()` toggles it (checked true -> false), bounding box
 *     top 536 px on a 720 px viewport => above the fold.
 *   - `page.getByLabel('Key Account', {exact:true})` matches 0 elements on the
 *     read-only Details tab — labels there are text nodes, not form controls.
 *   - Save: exactly one `button "Save"` in edit mode (measured: ['Save']).
 */

const MARK_API = 'Is_Key_Account__c';
const MARK_LABEL = 'Key Account';

/* --------------------------- sf-CLI helper (house) --------------------------- */
function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}
function soql(query: string): any {
  const out = execSync(
    `sf data query --query "${query}" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 10 * 1024 * 1024, env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } },
  );
  return shellJson(out).result;
}
function soqlCount(query: string): number {
  const r = soql(query);
  if (typeof r.totalSize !== 'number') throw new Error(`COUNT() query ohne totalSize: ${JSON.stringify(r).slice(0, 300)}`);
  return r.totalSize;
}
function createAccount(name: string): string {
  // `sf data create record` separates field pairs with SPACES, not commas.
  const out = execSync(
    `sf data create record --sobject Account --values "Name=${name} Phone=+49704710000 Website=https://scr471-e2e.example.com" --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } },
  );
  const id = shellJson(out).result?.id;
  if (!id) throw new Error(`Account "${name}" not created: ${out.slice(0, 300)}`);
  return id;
}

const TAG = 'TEST-SCRUM471-' + Date.now().toString(36).toUpperCase();
let markId: string;    // the record the toggle tests run on (AC2/AC3/AC4/AC8)
const preflight: Record<string, number> = {};

test.beforeAll(() => {
  markId = createAccount(`${TAG}-TOGGLE`);
  // AC9 pre-flight: every pre-existing customer must still read "No".
  preflight.accounts = soqlCount('SELECT COUNT() FROM Account');
  // SOQL cannot negate a term with `NOT ... LIKE` in Test-Org (measured:
  // `AND Name NOT LIKE 'x%'` and `AND NOT (Name LIKE 'x%')` both -> MALFORMED_QUERY),
  // so the pre-existing count is measured by subtraction of this ticket's own fixtures.
  preflight.markedAll = soqlCount('SELECT COUNT() FROM Account WHERE Is_Key_Account__c = true');
  preflight.markedTest = soqlCount(`SELECT COUNT() FROM Account WHERE Is_Key_Account__c = true AND Name LIKE 'TEST-SCRUM471%'`);
  preflight.markedNonTest = preflight.markedAll - preflight.markedTest;
  preflight.cases = soqlCount('SELECT COUNT() FROM Case');
  preflight.opps = soqlCount('SELECT COUNT() FROM Opportunity');
  preflight.email = soqlCount('SELECT COUNT() FROM EmailMessage');
  preflight.tasks = soqlCount('SELECT COUNT() FROM Task');
  if (preflight.markedNonTest !== 0) {
    throw new Error(`AC9 precondition: ${preflight.markedNonTest} pre-existing customers are already marked (expected 0 — nobody may be marked before the test marks one)`);
  }
});

/** The rendered value of the mark on the Details tab: 'True' | 'False' | null. */
async function renderedMark(page: Page): Promise<string | null> {
  const snap = await page.ariaSnapshot();
  // Measured shape (probe471b): `        - text: Key Account False Key Account`.
  // The `text:` prefix keeps the `button "Edit Key Account"` line out of the match.
  const line = snap.split('\n').find((l) => /text: Key Account\s+\w+/.test(l));
  if (!line) return null;
  const m = line.match(/text: Key Account\s+(\w+)/);
  return m ? m[1] : null;
}

/** Index of the mark's line and of the next section heading in the aria snapshot. */
async function markSection(page: Page): Promise<{ markLine: number; nameLine: number; nextHeading: number }> {
  const lines = (await page.ariaSnapshot()).split('\n');
  const nameLine = lines.findIndex((l) => /text: Account Name/.test(l));
  const markLine = lines.findIndex((l) => /text: Key Account/.test(l));
  const nextHeading = lines.findIndex((l, i) => i > nameLine && /heading .*level=3/.test(l));
  return { markLine, nameLine, nextHeading };
}

/** Toggle the mark through the UI (Edit -> checkbox click -> Save) and prove the save. */
async function setMark(page: Page, path: string, want: 'true' | 'false') {
  await openRecordDetails(page, path);
  const editBtn = page.getByRole('button', { name: `Edit ${MARK_LABEL}` });
  await expect(editBtn, `"Edit ${MARK_LABEL}" button not on the Details tab — the field is not directly editable where it was laid out`).toBeVisible({ timeout: 20000 });
  await editBtn.click();
  await page.waitForTimeout(1500);

  const cb = page.locator(`input[name="${MARK_API}"]`);
  await expect(await cb.count(), 'the mark must be exactly one checkbox control in edit mode').toBe(1);
  await expect(cb.first()).toBeVisible({ timeout: 15000 });
  const before = await cb.first().evaluate((el) => el.checked);
  if (before !== (want === 'true')) await cb.first().click();
  const after = await cb.first().evaluate((el) => el.checked);
  expect(after, `AC2/AC3: the mark control must read ${want} before saving`).toBe(want);

  const save = page.getByRole('button', { name: 'Save' });
  await expect(save.first()).toBeVisible({ timeout: 15000 });
  await save.first().click();
  await page.waitForTimeout(2500);
}

test.describe('[SCRUM-471] Key Account mark on the customer record', () => {

  test('AC9: the customers that exist today all read No', async ({ page }) => {
    // 251 pre-existing customers, 0 marked (measured by the Developer and the
    // PO; re-measured here so the number travels into the coverage table).
    expect(preflight.markedNonTest, 'AC9: no pre-existing customer may carry the mark before management marks one').toBe(0);
    expect(preflight.accounts, 'AC9: there must be pre-existing customers to check at all').toBeGreaterThan(0);
    await page.goto(`/lightning/r/Account/${markId}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await openRecordDetails(page, `/lightning/r/Account/${markId}/view`);
    const value = await renderedMark(page);
    expect(value, 'AC9: a customer nobody marked renders the mark as False/No').toBe('False');
    test.info().annotations.push({ type: 'observed', description: `AC9: ${preflight.accounts} Account records, ${preflight.markedNonTest} pre-existing marked, ${preflight.markedAll} marked overall; page renders ${value}` });
  });

  test('AC1: a newly created customer reads No (new-record form, nothing typed)', async ({ page }) => {
    const name = `${TAG}-NEWFORM`;
    await page.goto('/lightning/o/Account/new', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    // The form paints its fields seconds after the header (measured ~6 s).
    await expect(page.getByText(MARK_LABEL, { exact: true }).first()).toBeVisible({ timeout: 45000 });
    const nameField = page.getByLabel(/Account Name/).first();
    await nameField.click();
    await nameField.fill(name);
    // The mark is a real control the team could check — but nothing is checked here.
    const cb = page.getByRole('checkbox', { name: MARK_LABEL });
    await expect(await cb.count(), 'AC1: the mark must be offered on the new-record form').toBe(1);
    const checked = await cb.first().evaluate((el) => el.checked);
    expect(checked, 'AC1: a new customer starts unchecked (No)').toBe(false);
    await page.getByRole('button', { name: 'Save' }).first().click();
    await expect(page.getByText(/was created/i).first(), 'AC1: the form must announce the created record').toBeVisible({ timeout: 30000 });
    await page.waitForTimeout(2000);

    const rows = soql(`SELECT Id, Name, ${MARK_API}, Phone, Website FROM Account WHERE Name = '${name}'`).records;
    expect(rows.length, 'AC1: the new customer exists after the save').toBe(1);
    const rec = rows[0].attributes;
    expect(rec['Is_Key_Account__c'], 'AC1: the saved customer carries No').toBe(false);
    // And it renders as No on the detail page, where the mark is supposed to be visible.
    await openRecordDetails(page, `/lightning/r/Account/${rec.Id}/view`);
    const value = await renderedMark(page);
    expect(value, 'AC1: the new customer renders the mark as False').toBe('False');
    test.info().annotations.push({ type: 'observed', description: `AC1: created ${rec.Id} via /lightning/o/Account/new, unchecked on the form, saved with Is_Key_Account__c=false, renders ${value}` });
  });

  test('AC2: a colleague sets the mark, saves, and the record reads Yes', async ({ page }) => {
    await setMark(page, `/lightning/r/Account/${markId}/view`, 'true');
    const rows = soql(`SELECT Id, ${MARK_API} FROM Account WHERE Id = '${markId}'`).records;
    expect(rows.length, 'AC2: the fixture record must exist').toBe(1);
    expect(rows[0].attributes[MARK_API], 'AC2: after the save the customer is a key account').toBe(true);
    // Post-reload persistence: a fresh navigation renders the saved value.
    await page.goto(`/lightning/r/Account/${markId}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await openRecordDetails(page, `/lightning/r/Account/${markId}/view`);
    const value = await renderedMark(page);
    expect(value, 'AC2: after reload the page renders the mark as True').toBe('True');
    test.info().annotations.push({ type: 'observed', description: `AC2: save via UI -> SOQL true -> reload renders ${value}` });
  });

  test('AC3: the same colleague clears the mark, saves, and it reads No again', async ({ page }) => {
    await setMark(page, `/lightning/r/Account/${markId}/view`, 'false');
    const rows = soql(`SELECT Id, ${MARK_API} FROM Account WHERE Id = '${markId}'`).records;
    expect(rows.length, 'AC3: the fixture record must exist').toBe(1);
    expect(rows[0].attributes[MARK_API], 'AC3: after clearing the customer reads No').toBe(false);
    await page.goto(`/lightning/r/Account/${markId}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await openRecordDetails(page, `/lightning/r/Account/${markId}/view`);
    const value = await renderedMark(page);
    expect(value, 'AC3: after reload the page renders No again').toBe('False');
    test.info().annotations.push({ type: 'observed', description: `AC3: clear via UI -> SOQL false -> reload renders ${value}` });
  });

  test('AC4: the mark sits next to the name in the first section, above the fold', async ({ page }) => {
    await setMark(page, `/lightning/r/Account/${markId}/view`, 'true');
    await page.goto(`/lightning/r/Account/${markId}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await openRecordDetails(page, `/lightning/r/Account/${markId}/view`);

    // (a) The label is on the page at all.
    await expect(page.getByText(MARK_LABEL, { exact: true }).first()).toBeVisible({ timeout: 20000 });
    // (b) It sits in the SAME section as Account Name: both lines come after the
    //     field block opens and before the next section heading.
    const sec = await markSection(page);
    expect(sec.nameLine, 'AC4: Account Name must be on the Details tab').toBeGreaterThan(-1);
    expect(sec.markLine, 'AC4: the mark must render on the Details tab').toBeGreaterThan(-1);
    expect(sec.markLine, 'AC4: the mark renders after the customer name').toBeGreaterThan(sec.nameLine);
    expect(sec.nextHeading, `AC4: no section heading between the name and the mark (next heading at line ${sec.nextHeading}, mark at ${sec.markLine})`).toBeGreaterThan(sec.markLine);

    // (c) Both are above the fold — nobody scrolls to find the mark.
    const nameBox = await page.getByText('Account Name', { exact: true }).first().boundingBox();
    const markBox = await page.getByText(MARK_LABEL, { exact: true }).first().boundingBox();
    const viewport = await page.evaluate(() => window.innerHeight);
    expect(nameBox.y, 'AC4: the name label is on the first screen').toBeLessThan(viewport);
    expect(markBox.y, 'AC4: the mark is on the first screen (no scrolling)').toBeLessThan(viewport);
    expect(markBox.y - nameBox.y, 'AC4: the mark sits in the block below the name, not further down the page').toBeLessThan(400);
    expect(markBox.y, 'AC4: the mark is below the name label, next to it').toBeGreaterThan(nameBox.y);
    test.info().annotations.push({ type: 'observed', description: `AC4: aria lines name=${sec.nameLine} mark=${sec.markLine} nextSectionHeading=${sec.nextHeading}; label tops name=${nameBox.y} mark=${markBox.y} viewport=${viewport}` });
  });

  test('AC8: setting and clearing the mark triggers nothing', async ({ page }) => {
    const before = {
      accounts: soqlCount('SELECT COUNT() FROM Account'),
      cases: soqlCount('SELECT COUNT() FROM Case'),
      opps: soqlCount('SELECT COUNT() FROM Opportunity'),
      email: soqlCount('SELECT COUNT() FROM EmailMessage'),
      tasks: soqlCount('SELECT COUNT() FROM Task'),
      feed: soqlCount('SELECT COUNT() FROM FeedItem'),
    };
    const fixtureBefore = soql(`SELECT Id, Name, Phone, Website, OwnerId, Is_Key_Account__c FROM Account WHERE Id = '${markId}'`).records[0].attributes;

    await setMark(page, `/lightning/r/Account/${markId}/view`, 'false');
    await setMark(page, `/lightning/r/Account/${markId}/view`, 'true');

    const after = {
      accounts: soqlCount('SELECT COUNT() FROM Account'),
      cases: soqlCount('SELECT COUNT() FROM Case'),
      opps: soqlCount('SELECT COUNT() FROM Opportunity'),
      email: soqlCount('SELECT COUNT() FROM EmailMessage'),
      tasks: soqlCount('SELECT COUNT() FROM Task'),
      feed: soqlCount('SELECT COUNT() FROM FeedItem'),
    };
    const fixtureAfter = soql(`SELECT Id, Name, Phone, Website, OwnerId, Is_Key_Account__c FROM Account WHERE Id = '${markId}'`).records[0].attributes;

    for (const k of Object.keys(before)) {
      // EmailMessage/Task hold 0 records in Test-Org (measured): their equality
      // compares 0 with 0 and is VACUOUS — the non-vacuous halves are Case (681),
      // Opportunity (157) and the Account count, which are asserted here too.
      expect(after[k], `AC8: ${k} count changed by the mark toggle (${before[k]} -> ${after[k]})`).toBe(before[k]);
    }
    expect(after.cases, 'AC8: non-vacuous half — the 681 Case records must be untouched').toBeGreaterThan(0);
    expect(after.opps, 'AC8: non-vacuous half — the 157 Opportunity records must be untouched').toBeGreaterThan(0);
    for (const field of ['Name', 'Phone', 'Website', 'OwnerId']) {
      expect(fixtureAfter[field], `AC8: ${field} on the customer changed by the mark toggle`).toBe(fixtureBefore[field]);
    }
    expect(fixtureAfter[MARK_API], 'AC8: the mark itself is the only field that changed').toBe(true);
    test.info().annotations.push({ type: 'observed', description: `AC8 before/after: accounts ${before.accounts}->${after.accounts}, cases ${before.cases}->${after.cases}, opportunities ${before.opps}->${after.opps}, email ${before.email}->${after.email}, tasks ${before.tasks}->${after.tasks}, feeds ${before.feed}->${after.feed}; Phone/Website/Name/OwnerId unchanged` });
  });
});
