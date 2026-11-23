import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, saveInlineEdit } from './record-page';
import { requireData } from './preflight';

/**
 * [SCRUM-472] E2E: "Company Size" — one hand-filled Picklist on the standard Lead.
 *
 * Covered here (UI side of the acceptance criteria):
 *   AC1 — a sized lead renders its band on the Details tab in the company block.
 *   AC2 — choosing a range saves exactly that band, no other field changed.
 *   AC3 — a lead without a size saves cleanly and stays blank.
 *   AC4 — clearing the band = an Edit: value empty again, lead NOT deleted.
 *   AC5 — the picker offers exactly the four bands (+ the blank slot); there is
 *         no free-text entry point, and free text typed into the picker is not stored.
 *   AC7 — the size can be set at creation (Lightning new-record form).
 *   AC8 — setting/changing the band triggers nothing: no chatter post, no email,
 *         no task, no re-assignment, no extra record.
 *   AC9 — at go-live no existing lead carries a value (org-wide baseline).
 *
 * NOT here (named in the coverage table):
 *   AC6 — sorting/filtering leads by size: NO artefact exists (PO kept the column
 *         out of scope: no Company Size column in the existing Lead list views or
 *         Sales reports). Only the band grouping is measured here, see the comment.
 *   AC5 below the UI — measured, NOT enforceable: an out-of-band value IS stored
 *         via `sf data create record` (see docs/SCRUM-472-notizen-tester.md).
 *   Negative CRUD/FLS (a user WITHOUT SCRUM472_CompanySize cannot read or write the
 *   field): Apex SCRUM472CompanySizeFlsTest (System.runAs — the org has 2/2 Salesforce
 *   licences taken by System Administrators, so no second browser session exists).
 *   Blank-at-creation / change / clear + record identity: Apex SCRUM472CompanySizeTest.
 *
 * Locators were PROBED against THIS org on 2026-11-23 (never guessed):
 *   scratch/t472/probe472e|f|g.mjs — record page + Details tab, frontdoor storageState.
 *   Measured: view mode  getByText('Company Size',{exact:true}) = 1, the value sits in the
 *     same aria row (`- text: Company Size 11 to 50 employees`); getByLabel = 0 (no <label>).
 *   Edit mode  getByRole('button',{name:'Edit Company Size',exact:true}) = 1
 *              getByRole('combobox',{name:'Company Size',exact:true}) = 1
 *              getByRole('listbox',{name:'Company Size',exact:true}) = 1 holding EXACTLY 5
 *                [role=option] items, data-value = '' , up_to_10, 11_to_50, 51_to_250,
 *                more_than_250; the option labels exist only in the aria NAME
 *                (textContent is empty), and other picklists in the same section
 *                (Salutation, Lead Source, Industry, Product Interest, Lead Status)
 *                also render options -> always scope inside THIS listbox.
 *              getByRole('textbox',{name:'Company Size',exact:true}) = 0 -> no free text.
 *   New form   /lightning/o/Lead/new: textbox "Last Name" = 1, textbox "Company" = 1,
 *              combobox "Company Size" = 1, button "Save" (exact) = 1.
 *   NEVER use getByText('Company', {exact:true}) — measured count 2 on the page.
 *   The standard Lead.NumberOfEmployees ("No. of Employees", a spinbutton) is a DIFFERENT
 *   field and must never be compared with a band.
 */

const ORG = 'Test-Org';
const FIELD_LABEL = 'Company Size';
const FIELD_API = 'Company_Size__c';
const BAND_API = ['up_to_10', '11_to_50', '51_to_250', 'more_than_250'];
const BAND_LABELS = [
  'up to 10 employees',
  '11 to 50 employees',
  '51 to 250 employees',
  'more than 250 employees',
];

// ── org helpers (house shape, proven in SCRUM-470) ─────────────────────

/** sf writes a "update available" Warning to stderr AND exits non-zero -> execSync throws.
 * The JSON on stdout is the verdict: swallow stderr, and let "No JSON" be the failure. */
function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`No JSON in sf answer: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function soql(query: string): any {
  const out = execSync(
    // `|| true`: the CLI exits non-zero for its own stderr Warning; no JSON on stdout = real error.
    `sf data query --query ${JSON.stringify(query)} --target-org ${ORG} --json 2>/dev/null || true`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0' } },
  );
  return shellJson(out).result;
}

function cli(cmd: string): any {
  return shellJson(
    execSync(`${cmd} 2>/dev/null || true`, { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0' } }),
  );
}

const READ_COLS = [
  'Id', 'LastName', 'Company', 'Phone', 'Description', 'Owner.Name',
  'LastModifiedDate', FIELD_API, 'NumberOfEmployees',
];

function readRow(id: string): any {
  const r = soql(`SELECT ${READ_COLS.join(', ')} FROM Lead WHERE Id = '${id}'`);
  if (r.totalSize !== 1) {
    throw new Error(`record ${id} is not readable any more (totalSize ${r.totalSize}) — clearing must never delete a lead`);
  }
  return r.records[0];
}

const orgTotal = (): number => soql('SELECT Id FROM Lead').totalSize;
const orgSized = (): number => soql(`SELECT Id FROM Lead WHERE ${FIELD_API} != null`).totalSize;
const chatterTotal = (): number => soql('SELECT Id FROM FeedItem').totalSize;
const emailsTotal = (): number => soql('SELECT Id FROM EmailMessage').totalSize;
const tasksTotal = (): number => soql('SELECT Id FROM Task').totalSize;

// ── fixtures (idempotent: beforeAll/afterAll run again per describe block) ──

const TAG = `TEST-SCRUM-472-E2E-${Date.now().toString(36)}`;
const NAMES: Record<string, string> = {
  ac1: `${TAG}-AC1-sized`,
  ac2: `${TAG}-AC2-blank`,
  ac3: `${TAG}-AC3-blank`,
  ac4: `${TAG}-AC4-sized`,
  ac5: `${TAG}-AC5-sized`,
  ac6a: `${TAG}-AC6-up_to_10`,
  ac6b: `${TAG}-AC6-11_50`,
  ac6c: `${TAG}-AC6-51_250`,
  ac6d: `${TAG}-AC6-250plus`,
  ac8: `${TAG}-AC8-sized`,
};
const ids: Record<string, string> = {};

// `sf data create record -v` takes space-separated key=value pairs (measured: a bare
// value without `LastName=` fails 'Malformed key=value pair').
// Measured: `-v` splits on whitespace -> a value containing a space ('TEST ACME One')
// is refused ('Malformed key=value pair for value: ACME.'). Fixture values are single tokens.
const FIXTURE_EXTRA: Record<string, string> = {
  ac1: `Company=TEST-ACME-One Phone=+491****0000 ${FIELD_API}=11_to_50`,
  ac2: `Company=TEST-ACME-Two Phone=+492****0000 Description=TEST-band-empty`,
  ac3: `Company=TEST-ACME-Three Phone=+493****0000 Description=TEST-band-empty`,
  ac4: `Company=TEST-ACME-Four Phone=+494****0000 ${FIELD_API}=51_to_250`,
  ac5: `Company=TEST-ACME-Five Phone=+495****0000 ${FIELD_API}=more_than_250`,
  ac6a: `Company=TEST-ACME-SixA ${FIELD_API}=up_to_10`,
  ac6b: `Company=TEST-ACME-SixB ${FIELD_API}=11_to_50`,
  ac6c: `Company=TEST-ACME-SixC ${FIELD_API}=51_to_250`,
  ac6d: `Company=TEST-ACME-SixD ${FIELD_API}=more_than_250`,
  ac8: `Company=TEST-ACME-Eight Phone=+498****0000 Description=TEST-side-effects ${FIELD_API}=11_to_50`,
};

test.beforeAll(() => {
  // AC9 baseline BEFORE any fixture exists: nothing may carry a value at go-live.
  // SOQL note (measured 2026-11-23): `X != null AND NOT (Y LIKE 'a%')` is MALFORMED_QUERY in
  // this org, the plain `!= null AND Y LIKE 'a%'` is fine -> the foreign filter runs in JS.
  const sizedRows = soql(`SELECT Id, LastName, Company FROM Lead WHERE ${FIELD_API} != null`).records;
  const foreignSized = sizedRows.filter((r: any) => !String(r.LastName).startsWith(TAG));
  if (foreignSized.length > 0) {
    const who = foreignSized.slice(0, 3).map((r: any) => `${r.Id} ${r.LastName}`).join(', ');
    throw new Error(
      `AC9: ${foreignSized.length} leads ALREADY carry a band before this run (expected 0 at go-live) — ` +
      `the field was defaulted or backfilled: ${who}`,
    );
  }

  for (const key of Object.keys(FIXTURE_EXTRA)) {
    const name = NAMES[key];
    if (soql(`SELECT Id FROM Lead WHERE LastName = '${name}'`).totalSize === 0) {
      cli(`sf data create record -s Lead -v "LastName=${name} ${FIXTURE_EXTRA[key]}" --target-org ${ORG} --json`);
    }
  }
  for (const row of soql(`SELECT Id, LastName FROM Lead WHERE LastName LIKE '${TAG}%'`).records) {
    ids[row.LastName] = row.Id;
  }
  for (const key of ['ac1', 'ac2', 'ac3', 'ac4', 'ac5', 'ac6a', 'ac6b', 'ac6c', 'ac6d', 'ac8']) {
    if (!ids[NAMES[key]]) throw new Error(`fixture ${NAMES[key]} missing — seeding failed`);
  }

  requireData([
    { ac: 'baseline', what: 'Leads in Test-Org (66 measured 2026-11-23)', soql: 'SELECT Id FROM Lead', min: 1 },
    { ac: 'fixtures', what: 'the ten fixtures of this run', soql: `SELECT Id FROM Lead WHERE LastName LIKE '${TAG}%'`, min: 10 },
    { ac: 'AC1/AC4/AC5/AC8/AC6', what: 'fixture leads carrying a band', soql: `SELECT Id FROM Lead WHERE ${FIELD_API} != null`, min: 8 },
    { ac: 'AC3', what: 'a fixture lead WITHOUT a band', soql: `SELECT Id FROM Lead WHERE ${FIELD_API} = null AND LastName LIKE '${TAG}%'`, min: 2 },
    { ac: 'AC8', what: 'chatter posts in Test-Org (885 measured: makes the no-side-effect guard falsifiable)', soql: 'SELECT Id FROM FeedItem', min: 1 },
  ]);
});

test.afterAll(() => {
  // Fixtures must not stay in the org: leave it as it was found (0 leads carry a band).
  for (const row of soql(`SELECT Id FROM Lead WHERE LastName LIKE '${TAG}%'`).records) {
    cli(`sf data delete record -s Lead -i ${row.Id} --target-org ${ORG} --json`);
  }
});

// ── probed helpers ─────────────────────────────────────────────────────

async function dismissGuidance(page: import('@playwright/test').Page) {
  // house SCRUM-464: the "Try the new Salesforce Setup" dialog covers record-page buttons.
  const dlg = page.getByRole('dialog', { name: /Try the new Salesforce Setup/i });
  if ((await dlg.count()) > 0) {
    await dlg.getByRole('button').first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

async function openDetails(page: import('@playwright/test').Page, key: string) {
  await openRecordDetails(page, `/lightning/r/Lead/${ids[key]}/view`);
  await dismissGuidance(page);
}

/** Enter edit mode for the Company Size field (verified: the button exists exactly once). */
async function openEditForField(page: import('@playwright/test').Page, label: string) {
  const btn = page.getByRole('button', { name: `Edit ${label}`, exact: true });
  await expect(await btn.count(), `no single "Edit ${label}" button`).toBe(1);
  await btn.first().click({ timeout: 15000 });
  await page.waitForTimeout(2500);
}

/** The picker of THIS field. Verified: listbox named 'Company Size' -> count 1. */
async function pickerListbox(page: import('@playwright/test').Page) {
  const lb = page.getByRole('listbox', { name: FIELD_LABEL, exact: true });
  await expect(await lb.count(), `picker listbox "${FIELD_LABEL}" not on the page`).toBe(1);
  const combo = page.getByRole('combobox', { name: FIELD_LABEL, exact: true });
  await expect(await combo.count(), `combobox "${FIELD_LABEL}" not on the page`).toBe(1);
  return lb.first();
}

/** Click one picker slot, scoped INSIDE the Company Size listbox (other picklists are in the DOM too). */
async function pickOption(page: import('@playwright/test').Page, dataValue: string) {
  const lb = await pickerListbox(page);
  const opt = lb.locator(`[role=option][data-value="${dataValue}"]`);
  await expect(await opt.count(), `picker slot data-value="${dataValue}" not unique/absent in the Company Size listbox`).toBe(1);
  await opt.first().click({ timeout: 15000 });
  await page.waitForTimeout(1500);
}

/** The offered labels, read from the aria block of THIS listbox (option textContent is empty). */
async function pickerOptionLabels(page: import('@playwright/test').Page): Promise<string[]> {
  const snap = await page.ariaSnapshot();
  const lines = snap.split('\n');
  const start = lines.findIndex((l) => /listbox "Company Size"/.test(l));
  expect(start, 'aria block listbox "Company Size" missing').toBeGreaterThan(-1);
  const indent = (lines[start].match(/^\s*/) ?? [''])[0].length;
  const labels: string[] = [];
  for (let j = start + 1; j < lines.length; j++) {
    const line = lines[j];
    if (!/^\s*\S/.test(line)) continue;
    if ((line.match(/^\s*/) ?? [''])[0].length <= indent) break;
    const m = /- option "([^"]*)"/.exec(line);
    if (m) labels.push(m[1]);
  }
  return labels;
}

/** Field rows rendered between the Company row and the Company Size row (AC1 adjacency). */
async function rowsBetweenCompanyAndSize(page: import('@playwright/test').Page): Promise<number> {
  const lines = (await page.ariaSnapshot()).split('\n').map((l) => l.trim());
  const comp = lines.findIndex((l) => /^- text: Company (?!Size)/.test(l));
  const size = lines.findIndex((l) => /^- text: Company Size/.test(l));
  expect(comp, 'no `- text: Company <value>` row rendered').toBeGreaterThan(-1);
  expect(size, 'no `- text: Company Size <value>` row rendered').toBeGreaterThan(-1);
  const between = lines.slice(comp + 1, size);
  expect(between.filter((l) => /^- heading/.test(l)), 'Company Size renders in a different Details section than Company').toHaveLength(0);
  expect(size).toBeGreaterThan(comp);
  return between.filter((l) => /^- text: /.test(l)).length;
}

// ── AC1: visible on the opened lead, in the company block ──────────────

test.describe('[SCRUM-472] AC1 — the band is visible when the lead is opened', () => {
  test('a lead with a band shows the label AND the band label next to Company', async ({ page }) => {
    await openDetails(page, 'ac1');
    const before = readRow(ids.ac1);
    expect(before[FIELD_API], 'AC1 fixture must carry a band').toBe('11_to_50');

    const label = page.getByText(FIELD_LABEL, { exact: true });
    await expect(label, 'field label "Company Size" not visible on the Details tab').toBeVisible({ timeout: 15000 });
    await expect(await label.count(), 'the label "Company Size" is not unique').toBe(1);
    const value = page.getByText(BAND_LABELS[1], { exact: true });
    await expect(value, 'the band label "11 to 50 employees" not visible next to the label').toBeVisible({ timeout: 15000 });

    const gap = await rowsBetweenCompanyAndSize(page);
    // Measured 2026-11-23: the renderer puts exactly one field row (Fax) between them.
    expect(gap, 'Company Size must render in the company block (max 2 field rows below Company)').toBeLessThanOrEqual(2);
  });
});

// ── AC2: choosing a range saves exactly that band, nothing else changes ─

test.describe('[SCRUM-472] AC2 — selecting one range saves exactly that band', () => {
  test('empty lead gets the 51-250 band; Company/Phone/Description/Owner stay', async ({ page }) => {
    await openDetails(page, 'ac2');
    const before = readRow(ids.ac2);
    expect(before[FIELD_API], 'AC2 fixture starts without a band').toBeNull();

    await openEditForField(page, FIELD_LABEL);
    await pickOption(page, '51_to_250');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = readRow(ids.ac2);
    expect(after[FIELD_API], 'AC2: saved band must be exactly the chosen one').toBe('51_to_250');
    expect(after.Company, 'AC2: Company unchanged').toBe(before.Company);
    expect(after.Phone, 'AC2: Phone unchanged').toBe(before.Phone);
    expect(after.Description, 'AC2: Description unchanged').toBe(before.Description);
    expect((after.Owner ?? {}).Name ?? null, 'AC2: no re-assignment').toBe((before.Owner ?? {}).Name ?? null);
    expect(after.NumberOfEmployees, 'AC2: the standard Lead.NumberOfEmployees must stay untouched').toBeNull();
  });
});

// ── AC3: a lead without a size saves cleanly ───────────────────────────

test.describe('[SCRUM-472] AC3 — blank is allowed, the save is clean', () => {
  test('a blank lead is saved through the UI (another field edited) and stays blank', async ({ page }) => {
    await openDetails(page, 'ac3');
    const before = readRow(ids.ac3);
    expect(before[FIELD_API], 'AC3 fixture starts without a band').toBeNull();

    await openEditForField(page, 'Company');
    const companyInput = page.getByRole('textbox', { name: 'Company', exact: true });
    await expect(await companyInput.count(), 'no single Company input in edit mode').toBe(1);
    await companyInput.first().type('TEST ACME Three edited');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = readRow(ids.ac3);
    expect(after.Company, 'AC3: the save landed').toBe('TEST ACME Three edited');
    expect(after[FIELD_API], 'AC3: blank stays blank after a clean save').toBeNull();
  });
});

// ── AC4: clearing the band = Edit, the lead is NOT deleted ─────────────

test.describe('[SCRUM-472] AC4 — clearing the band saves empty, lead survives', () => {
  test('the 51-250 band is cleared via the picker blank slot', async ({ page }) => {
    await openDetails(page, 'ac4');
    const before = readRow(ids.ac4);
    expect(before[FIELD_API], 'AC4 fixture must start with a band').toBe('51_to_250');

    await openEditForField(page, FIELD_LABEL);
    await pickerListbox(page);
    const labels = await pickerOptionLabels(page);
    expect(labels, 'the picker must offer the blank slot first').toEqual(['--None--', ...BAND_LABELS]);
    await pickOption(page, '');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = readRow(ids.ac4);
    expect(after[FIELD_API], 'AC4: cleared back to empty').toBeNull();
    expect(after.LastName, 'AC4: clearing must not delete the lead').toBe(NAMES.ac4);
    expect(after.Company, 'AC4: nothing else changed').toBe(before.Company);
  });
});

// ── AC5: only the four ranges can be entered ───────────────────────────

test.describe('[SCRUM-472] AC5 — a value outside the four ranges cannot be entered', () => {
  test('picker offers exactly 4 bands + blank, no textbox, free text is not stored', async ({ page }) => {
    await openDetails(page, 'ac5');
    const before = readRow(ids.ac5);
    expect(before[FIELD_API], 'AC5 fixture must start with a band').toBe('more_than_250');

    await openEditForField(page, FIELD_LABEL);
    const lb = await pickerListbox(page);
    await expect(await lb.locator('[role=option]').count(), 'picker offers not exactly 5 slots (4 bands + blank)').toBe(5);
    const labels = await pickerOptionLabels(page);
    expect(labels, 'AC5: picker offers a label that is not one of the four PO bands').toEqual(['--None--', ...BAND_LABELS]);

    // no free-text entry point for the field (verified: 0 textboxes named Company Size)
    const textbox = page.getByRole('textbox', { name: FIELD_LABEL, exact: true });
    await expect(await textbox.count(), 'a free-text box for Company Size would allow out-of-band values').toBe(0);

    // typing free text into the picker must not reach the org
    const combo = page.getByRole('combobox', { name: FIELD_LABEL, exact: true });
    await combo.first().type('12 employees');
    await page.waitForTimeout(1000);
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = readRow(ids.ac5);
    expect(after[FIELD_API], 'AC5: free text must never be stored (still the band it had)').toBe('more_than_250');
  });
});

// ── AC6: grouping by the exact band (DATA ONLY — no UI artefact exists) ─

test.describe('[SCRUM-472] AC6 — the four bands stay four distinct values', () => {
  // NOT EXERCISABLE as a UI test: neither the existing Lead list views nor the Sales
  // reports carry a Company Size column (PO kept that out of scope). What CAN be proven
  // is that the stored values group by the exact band — asserted below, reported as
  // data-level only, never as PASS.
  test('four fixtures carry four different bands; each band groups by its exact value', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Lead/${ids.ac6c}/view`);
    await dismissGuidance(page);

    const rows = soql(`SELECT Id, ${FIELD_API} FROM Lead WHERE LastName LIKE '${TAG}-AC6%'`).records;
    expect(rows, 'AC6 needs four fixtures, one per band').toHaveLength(4);
    const stored = rows.map((r: any) => r[FIELD_API]);
    expect(stored.sort(), 'AC6: each fixture must hold a different exact band').toEqual([...BAND_API].sort());

    // org-wide grouping: every band is its own group, and only fixtures carry values.
    const perBand: Record<string, number> = {};
    for (const band of BAND_API) {
      perBand[band] = soql(`SELECT Id FROM Lead WHERE ${FIELD_API} = '${band}'`).totalSize;
    }
    const measured = Object.entries(perBand);
    for (const [band, count] of measured) {
      expect(count, `AC6: band "${band}" matches zero records -> untested`).toBe(1);
    }
    console.log(`AC6 grouping (org-wide, no UI artefact): ${measured.map(([b, c]) => `${b}=${c}`).join(' ')}; sized leads total: ${orgSized()}`);
  });
});

// ── AC7: the size can be set at creation ───────────────────────────────

test.describe('[SCRUM-472] AC7 — filling the band while creating a lead', () => {
  test('the Lightning new-record form creates the lead with the chosen band', async ({ page }) => {
    const newName = `${TAG}-AC7-created`;
    await page.goto('/lightning/o/Lead/new', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
    await page.waitForTimeout(3000);

    const lastName = page.getByRole('textbox', { name: 'Last Name', exact: true });
    await expect(await lastName.count(), 'no single Last Name input on the new-record form').toBe(1);
    await lastName.first().type(newName);
    const company = page.getByRole('textbox', { name: 'Company', exact: true });
    await expect(await company.count(), 'no single Company input on the new-record form').toBe(1);
    await company.first().type('TEST ACME Seven');

    const combo = page.getByRole('combobox', { name: FIELD_LABEL, exact: true });
    await expect(await combo.count(), 'no Company Size combobox on the new-record form').toBe(1);
    await combo.first().click({ timeout: 15000 });
    await page.waitForTimeout(2000);
    const lb = page.getByRole('listbox', { name: FIELD_LABEL, exact: true });
    await expect(await lb.count(), 'picker not opened on the new-record form').toBe(1);
    const slot = lb.first().locator('[role=option][data-value="up_to_10"]');
    await expect(await slot.count(), 'picker slot up_to_10 missing on the new-record form').toBe(1);
    await slot.first().click({ timeout: 15000 });
    await page.waitForTimeout(1500);

    const save = page.getByRole('button', { name: 'Save', exact: true });
    await expect(await save.count(), 'no single Save button on the new-record form').toBe(1);
    await save.first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const rows = soql(`SELECT Id, ${READ_COLS.join(', ')} FROM Lead WHERE LastName = '${newName}'`).records;
    expect(rows, 'AC7: the created lead is not in the org').toHaveLength(1);
    const created = rows[0];
    expect(created[FIELD_API], 'AC7: created with exactly the chosen band').toBe('up_to_10');
    expect(created.Company, 'AC7: Company as typed').toBe('TEST ACME Seven');
    ids.ac7 = newName;
  });
});

// ── AC8: setting/changing the band fires nothing ───────────────────────

test.describe('[SCRUM-472] AC8 — the save triggers no email, task, chatter or re-assignment', () => {
  test('changing the band touches exactly that record', async ({ page }) => {
    const before = readRow(ids.ac8);
    expect(before[FIELD_API], 'AC8 fixture must start with a band').toBe('11_to_50');
    const leadsBefore = orgTotal();
    const sizedBefore = orgSized();
    const chatterBefore = chatterTotal();
    const emailsBefore = emailsTotal();
    const tasksBefore = tasksTotal();

    await openDetails(page, 'ac8');
    await openEditForField(page, FIELD_LABEL);
    await pickOption(page, 'up_to_10');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = readRow(ids.ac8);
    expect(after[FIELD_API], 'AC8: the band moved exactly as chosen').toBe('up_to_10');
    expect(orgTotal(), 'AC8: no additional record created').toBe(leadsBefore);
    expect(orgSized(), 'AC8: the change stayed on one record (sized count unchanged)').toBe(sizedBefore);
    // falsifiable: 885 chatter posts exist in Test-Org, a chatter post would move this
    expect(chatterTotal(), 'AC8: no chatter/post created').toBe(chatterBefore);
    // measured 2026-11-23: EmailMessage and Task hold 0 rows in Test-Org -> 0-vs-0 guard
    expect(emailsTotal(), 'AC8: no email message created (vacuous guard: 0 rows in Test-Org)').toBe(emailsBefore);
    expect(tasksTotal(), 'AC8: no task created (vacuous guard: 0 rows in Test-Org)').toBe(tasksBefore);
    expect((after.Owner ?? {}).Name ?? null, 'AC8: the lead was not re-assigned').toBe((before.Owner ?? {}).Name ?? null);
    expect(after.Phone, 'AC8: untouched fields stay').toBe(before.Phone);
    expect(after.Description, 'AC8: untouched fields stay').toBe(before.Description);
    expect(after.NumberOfEmployees, 'AC8: Lead.NumberOfEmployees untouched').toBeNull();
    expect(new Date(after.LastModifiedDate).getTime())
      .toBeGreaterThan(new Date(before.LastModifiedDate).getTime());
  });
});

// ── AC9: nothing was defaulted or backfilled ───────────────────────────

test.describe('[SCRUM-472] AC9 — existing leads stayed empty at go-live', () => {
  test('every lead without a TEST tag is still empty', async ({ page }) => {
    const total = orgTotal();
    const sizedRows = soql(`SELECT Id, LastName FROM Lead WHERE ${FIELD_API} != null`).records;
    const foreignSized = sizedRows.filter((r: any) => !String(r.LastName).startsWith(TAG));
    const fixtures = soql(`SELECT Id FROM Lead WHERE LastName LIKE '${TAG}%'`).totalSize;
    const foreignEmpty = total - fixtures - foreignSized.length;
    expect(foreignSized, 'AC9: existing leads must not have gained a band').toHaveCount(0);
    expect(total - fixtures, 'AC9: every existing lead must still be readable and blank').toBe(foreignEmpty);
    console.log(`AC9 observed: total leads ${total}, fixtures ${fixtures}, existing blank ${foreignEmpty}, existing sized ${foreignSized.length}`);
  });
});
