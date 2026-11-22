import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, saveInlineEdit } from './record-page';
import { requireData } from './preflight';

/**
 * [SCRUM-470] E2E: "Favorit Kontaktmethod" on Contact in the Lightning UI.
 *
 * Covers the UI-side of the acceptance criteria that Apex cannot reach:
 *   AC1 — a contact WITHOUT a preference opens, saves, and stays empty.
 *   AC2 — the preference is visible in the contact-information area directly
 *         next to Phone/Email, without horizontal scrolling.
 *   AC3 — an empty preference gets set to "email", survives reload + read-back.
 *   AC4 — "Phone" is changed to "Letter" (old value gone).
 *   AC5 — the value is cleared back to empty via the picker's empty option.
 *   AC7 — saving changes exactly that value: no second record touched,
 *         no validation error, no popup.
 *
 * NOT here (covered elsewhere, named in the coverage table):
 *   AC6 — negative access: Apex SCRUM470PreferredContactMethodFlsTest
 *         (System.runAs under a profile WITHOUT SCRUM470_ContactContactWay;
 *         no second Salesforce licence exists, so no second browser session).
 *   Value schema + Picklist shape: Apex SCRUM470PreferredContactMethodTest.
 *
 * Locators were probed against THIS org on 2026-11-22 (never guessed):
 *   node scratch/scr470_probe{3,4,5}.mjs (record-page Details tab, frontdoor
 *   storageState). Measured shapes:
 *   - View mode: ariaSnapshot line  `text: Favorit Kontaktmethod email` and
 *     button `Edit Favorit Kontaktmethod` (count 1).
 *   - `getByText('Favorit Kontaktmethod', {exact:true})` → count 1;
 *     `getByText('email', {exact:true})` → count 1 (value directly below label).
 *   - `getByLabel(...)` → count 0 in view mode: no <label for=> exists, so getByText
 *     is the locator here (house startInlineEdit would fail with its count===1).
 *   - Edit mode: `getByRole('combobox', {name:'Favorit Kontaktmethod', exact:true})`
 *     → count 1. Opening it renders exactly 4 role=option items whose
 *     textContent is EMPTY — the value rides in `data-value`:
 *     ['', 'Phone', 'Email', 'Letter'].  `[data-value="Email"]` is unique
 *     (count 1); `[data-value=""]` is NOT (count 2) → it is selected from the
 *     scoped option list instead.
 *   - `getByRole('button', {name:'Save', exact:true})` → count 1.
 *   - Geometry (Edit-Button boxes): Edit Phone x=803 y=422, Edit Email x=803 y=720,
 *     Edit Favorit Kontaktmethod x=803 y=768 in a 1280x720 viewport with
 *     document.body.scrollWidth = 1280 → same column, right after Email, no
 *     horizontal scroll.
 */

const FIELD_LABEL = 'Favorit Kontaktmethod';
const FIELD_API = 'Preferred_Contact_Method__c';

// ── org helpers ────────────────────────────────────────────────────────

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Answer: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function soql(soqlText: string): any {
  const out = execSync(
    `sf data query --query ${JSON.stringify(soqlText)} --target-org Test-Org --json`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0' } },
  );
  return shellJson(out).result;
}

function cli(cmd: string): any {
  return shellJson(
    execSync(cmd, { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0' } }),
  );
}

function fieldOf(rec: any, api: string): string | null {
  return rec == null || rec === '' ? null : (rec[api] ?? null);
}

const TAG = `TEST-SCRUM-470-E2E-${Date.now().toString(36)}`;
const NAMES = {
  ac1: `${TAG}-AC1-empty`,
  ac2: `${TAG}-AC2-set`,
  ac3: `${TAG}-AC3-empty`,
  ac4: `${TAG}-AC4-phone`,
  ac5: `${TAG}-AC5-letter`,
};
const ids: Record<string, string> = {};

test.beforeAll(() => {
  // A file-level beforeAll runs once per describe block — seeding must be
  // idempotent, otherwise every block would create a second copy of the fixtures.
  const existing = soql(`SELECT Id, LastName FROM Contact WHERE LastName LIKE '${TAG}%'`).records;
  if (existing.length === 0) {
    cli(`sf data create record -s Contact -v "LastName=${NAMES.ac1} Phone=+4911110000 Email=${NAMES.ac1}@example.com" --target-org Test-Org --json`);
    cli(`sf data create record -s Contact -v "LastName=${NAMES.ac2} Phone=+4922220000 Email=${NAMES.ac2}@example.com Preferred_Contact_Method__c=Email" --target-org Test-Org --json`);
    cli(`sf data create record -s Contact -v "LastName=${NAMES.ac3} Phone=+4933330000 Email=${NAMES.ac3}@example.com" --target-org Test-Org --json`);
    cli(`sf data create record -s Contact -v "LastName=${NAMES.ac4} Phone=+4944440000 Email=${NAMES.ac4}@example.com Preferred_Contact_Method__c=Phone" --target-org Test-Org --json`);
  }
  cli(`sf data create record -s Contact -v "LastName=${NAMES.ac5} Phone=+4955550000 Email=${NAMES.ac5}@example.com Preferred_Contact_Method__c=Letter" --target-org Test-Org --json`);

  const rows = soql(`SELECT Id, LastName FROM Contact WHERE LastName LIKE '${TAG}%'`).records;
  for (const row of rows) ids[row.LastName] = row.Id;

  // Org baseline only — each test asserts its own fixture state, because a
  // file-level beforeAll runs again before every describe block (values from
  // earlier blocks are already changed).
  requireData([
    { ac: 'baseline', what: 'Contact records in Test-Org (676 measured 2026-11-22)', soql: 'SELECT Id FROM Contact', min: 1 },
    { ac: 'fixtures', what: 'the five fixtures of this run', soql: `SELECT Id FROM Contact WHERE LastName LIKE '${TAG}%'`, min: 5 },
    { ac: 'AC2/AC4/AC5', what: 'contacts carrying a channel preference (0 before this run)', soql: `SELECT Id FROM Contact WHERE ${FIELD_API} != null`, min: 1 },
  ]);
});

test.afterAll(() => {
  // Fixtures stay in Test-Org otherwise; the org must be left as it was found.
  const rows = soql(`SELECT Id FROM Contact WHERE LastName LIKE '${TAG}%'`).records;
  for (const row of rows) {
    cli(`sf data delete record -s Contact -i ${row.Id} --target-org Test-Org --json`);
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

async function openDetails(page: import('@playwright/test').Page, id: string) {
  await openRecordDetails(page, `/lightning/r/Contact/${id}/view`);
  await dismissGuidance(page);
}

/** Details-Section as rendered: the aria lines that carry a field row. */
async function detailsRows(page: import('@playwright/test').Page): Promise<string[]> {
  // Measured (scratch/scr470_probe6.mjs): field rows are `- text: <label> <value>`,
  // section titles are `- heading "<title>" [level=N]` (quotes, no colon) — the filter
  // must keep both.
  const snap = await page.ariaSnapshot();
  return snap.split('\n').map((l) => l.trim()).filter((l) => /^- (text|heading|button)/.test(l));
}

/** Enter edit mode for ONE field first — measured: the combobox only exists after the
 * `Edit <label>` button was clicked (in view mode getByRole('combobox') → count 0). */
async function openEditForField(page: import('@playwright/test').Page, label: string) {
  const btn = page.getByRole('button', { name: `Edit ${label}`, exact: true });
  await expect(await btn.count(), `no single "Edit ${label}" button on the Details section`).toBe(1);
  await btn.first().click({ timeout: 15000 });
  await page.waitForTimeout(2500);
}

/** Open the picker for the preference field. Verified: getByRole combobox, count 1. */
async function openPicker(page: import('@playwright/test').Page) {
  const combos = page.getByRole('combobox', { name: FIELD_LABEL, exact: true });
  await expect(await combos.count(), `combobox "${FIELD_LABEL}" not on the page`).toBe(1);
  await combos.first().click({ timeout: 15000 });
  await page.waitForTimeout(1200);
}

/** The picker's offered values: measured as data-value, never as textContent. */
async function offeredValues(page: import('@playwright/test').Page): Promise<string[]> {
  const opts = await page.getByRole('option').all();
  const values: string[] = [];
  for (const el of opts) values.push((await el.getAttribute('data-value').catch(() => null)) ?? 'NO-ATTRIBUTE');
  return values;
}

async function pickValue(page: import('@playwright/test').Page, dataValue: string) {
  await openEditForField(page, FIELD_LABEL);
  await openPicker(page);
  const values = await offeredValues(page);
  expect(values, `picker "${FIELD_LABEL}" offers ${JSON.stringify(values)} — expected exactly empty + the three channels`)
    .toEqual(['', 'Phone', 'Email', 'Letter']);
  if (dataValue === '') {
    // `[data-value=""]` is NOT unique page-wide (measured count 2) → take it from
    // the scoped option list of THIS picker.
    const opts = await page.getByRole('option').all();
    const scoped = [] as any[];
    for (const el of opts) {
      if ((await el.getAttribute('data-value').catch(() => null)) === '') scoped.push(el);
    }
    expect(scoped.length, `the picker offers ${scoped.length} empty options (measured 1)`).toBe(1);
    await scoped[0].click({ timeout: 8000 });
  } else {
    const opt = page.locator(`[data-value="${dataValue}"]`);
    await expect(await opt.count(), `option "${dataValue}" not offered`).toBe(1);
    await opt.first().click({ timeout: 8000 });
  }
  await page.waitForTimeout(800);
}

async function currentValue(id: string): Promise<string | null> {
  const rows = soql(`SELECT Id, ${FIELD_API} FROM Contact WHERE Id = '${id}'`).records;
  expect(rows.length, `fixture ${id} not in the org any more`).toBe(1);
  return fieldOf(rows[0], FIELD_API);
}

async function contactFields(id: string, fields: string[]): Promise<any> {
  const rows = soql(`SELECT Id, ${fields.join(', ')} FROM Contact WHERE Id = '${id}'`).records;
  return rows[0];
}

async function countWithPreference(): Promise<number> {
  return soql(`SELECT Id FROM Contact WHERE ${FIELD_API} != null`).totalSize;
}

// ── AC2: visibility next to Phone and Email ────────────────────────────

test.describe('[SCRUM-470] AC2 — Visibility next to phone + email', () => {
  test('value is rendered in the contact-information area, directly after Email, no horizontal scroll', async ({ page }) => {
    await openDetails(page, ids[NAMES.ac2]);

    // The field label and its value must be on the Details tab at all.
    const label = page.getByText(FIELD_LABEL, { exact: true });
    await expect(await label.count(), `field label "${FIELD_LABEL}" not rendered once`).toBe(1);
    await expect(label.first()).toBeVisible({ timeout: 20000 });
    const value = page.getByText('email', { exact: true });
    await expect(await value.count(), 'the value of the preference is not rendered').toBe(1);
    await expect(value.first()).toBeVisible({ timeout: 20000 });

    // "next to the phone number and the email address": same rendered section,
    // the row sits directly after Email — measured on the Edit-buttons' boxes.
    const editEmail = page.getByRole('button', { name: 'Edit Email', exact: true });
    const editPref = page.getByRole('button', { name: `Edit ${FIELD_LABEL}`, exact: true });
    const editPhone = page.getByRole('button', { name: 'Edit Phone', exact: true });
    await expect(await editEmail.count(), 'no Edit Email button in the Details section').toBe(1);
    await expect(await editPhone.count(), 'no Edit Phone button in the Details section').toBe(1);
    await expect(await editPref.count(), 'no Edit button for the preference').toBe(1);

    const boxEmail = await editEmail.first().boundingBox();
    const boxPref = await editPref.first().boundingBox();
    const boxPhone = await editPhone.first().boundingBox();
    if (!boxEmail) throw new Error('Edit Email button has no bounding box — geometry not measurable');
    if (!boxPhone) throw new Error('Edit Phone button has no bounding box — geometry not measurable');
    if (!boxPref) throw new Error(`Edit ${FIELD_LABEL} button has no bounding box — the field is not on the page`);
    const viewport = await page.evaluate(() => ({ w: window.innerWidth, scroll: document.body.scrollWidth }));

    expect(boxPref.x, `preference is not in the same column as Phone/Email (x ${boxPref.x} vs ${boxEmail.x})`).toBe(boxEmail.x);
    expect(boxPref.y > boxEmail.y, 'preference renders above Email — not next to it').toBe(true);
    expect(boxPref.y - boxEmail.y, `gap of ${boxPref.y - boxEmail.y}px to Email is not "direct vicinity" (measured 48)`).toBeLessThan(120);
    expect(boxPref.x < viewport.w, 'preference sits outside the viewport → horizontal scrolling needed').toBe(true);
    expect(viewport.scroll, 'page is wider than the viewport → horizontal scrolling needed').toBe(viewport.w);
    expect(boxEmail.x === boxPhone.x, 'Phone and Email are not in one information area').toBe(true);

    // "next to the phone number and the email address" is proven by GEOMETRY, not DOM
    // order: the Details section is a two-column layout, so the aria row order interleaves
    // both columns (measured: NewsletterConsent's row sits between Email and the preference
    // in the aria dump while visually the preference is the next row under Email).
    // Measured 2026-11-22: Edit Phone x=803 y=422 · Edit Email x=803 y=720 ·
    // Edit Favorit Kontaktmethod x=803 y=768 · document.body.scrollWidth = innerWidth = 1280.
    const rows: string[] = await detailsRows(page);
    expect(
      rows.some((l: string) => /^- heading/.test(l)) && rows.some((l: string) => l.includes(FIELD_LABEL)),
      'the preference row is not inside a Details section'
    ).toBe(true);
    const iEmailRow = rows.findIndex((l: string) => /^- text: Email\b/.test(l));
    const iPrefRow = rows.findIndex((l: string) => l.includes(FIELD_LABEL));
    expect(iEmailRow, 'the Email field row is not rendered in the Details section').toBeGreaterThanOrEqual(0);
    expect(iPrefRow, 'the preference field row is not rendered in the Details section').toBeGreaterThanOrEqual(0);
    expect(iPrefRow > iEmailRow, 'the preference renders above Email, not beside/below it').toBe(true);
  });
});

// ── AC1: empty stays empty through a save ──────────────────────────────

test.describe('[SCRUM-470] AC1 — empty preference saves without error', () => {
  test('open + save without choosing anything leaves the field empty', async ({ page }) => {
    const id = ids[NAMES.ac1];
    await openDetails(page, id);
    await expect(page.getByText(FIELD_LABEL, { exact: true }).first()).toBeVisible({ timeout: 20000 });

    const before = await currentValue(id);
    expect(before, 'fixture must start empty').toBeNull();
    const beforeRecord = await contactFields(id, ['Phone', 'Email', 'LastName']);

    await openEditForField(page, FIELD_LABEL);
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    // no validation error anywhere on the page (AC7 hard scope: nothing blocks)
    const snap = await page.ariaSnapshot();
    expect(/snag|Validation|Error \(/i.test(snap), 'a validation/error message appeared on save').toBe(false);

    const after = await currentValue(id);
    expect(after, 'AC1: saving without a value must leave it empty').toBeNull();
    const untouched = await contactFields(id, ['Phone', 'Email', 'LastName']);
    expect(untouched.Email, 'the save must not touch the rest of the record').toBe(beforeRecord.Email);
    expect(untouched.Phone, 'the save must not touch the rest of the record').toBe(beforeRecord.Phone);
    expect(untouched.LastName, 'the record itself must stay').toBe(beforeRecord.LastName);
  });
});

// ── AC3: empty → email, persists over reload ───────────────────────────

test.describe('[SCRUM-470] AC3 — set the preference', () => {
  test('empty preference becomes email, reopens on the next opening', async ({ page }) => {
    const id = ids[NAMES.ac3];
    await openDetails(page, id);
    expect(await currentValue(id), 'AC3 fixture must start empty').toBeNull();

    await pickValue(page, 'Email');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    expect(await currentValue(id), 'AC3: SOQL read-back after save must be Email').toBe('Email');

    // reload: a fresh page shows the value again
    await page.goto(`/lightning/r/Contact/${id}/view`, { waitUntil: 'domcontentloaded' });
    await openDetails(page, id);
    await expect(page.getByText(FIELD_LABEL, { exact: true }).first()).toBeVisible({ timeout: 20000 });
    await expect(page.getByText('email', { exact: true }).first()).toBeVisible({ timeout: 20000 });
  });
});

// ── AC4: phone → letter, old value gone ────────────────────────────────

test.describe('[SCRUM-470] AC4 — change the preference', () => {
  test('Phone becomes Letter, the old value is gone', async ({ page }) => {
    const id = ids[NAMES.ac4];
    await openDetails(page, id);
    expect(await currentValue(id), 'AC4 fixture must start at Phone').toBe('Phone');
    await expect(page.getByText('telefon', { exact: true }).first()).toBeVisible({ timeout: 20000 });

    await pickValue(page, 'Letter');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    expect(await currentValue(id), 'AC4: stored value must be Letter').toBe('Letter');

    await page.goto(`/lightning/r/Contact/${id}/view`, { waitUntil: 'domcontentloaded' });
    await openDetails(page, id);
    await expect(page.getByText('Letter', { exact: true }).first()).toBeVisible({ timeout: 20000 });
    const phoneLabelGone = await page.getByText('telefon', { exact: true }).count();
    expect(phoneLabelGone, 'AC4: the old value telefon is still rendered').toBe(0);
  });
});

// ── AC5: clear back to empty ───────────────────────────────────────────

test.describe('[SCRUM-470] AC5 — clear the preference', () => {
  test('Letter is cleared, record saves, field empty again', async ({ page }) => {
    const id = ids[NAMES.ac5];
    await openDetails(page, id);
    expect(await currentValue(id), 'AC5 fixture must start at Letter').toBe('Letter');

    await pickValue(page, '');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    expect(await currentValue(id), 'AC5: value must be empty again').toBeNull();
    const stillThere = await contactFields(id, ['LastName']);
    expect(stillThere.LastName, 'AC5: clearing must not delete the record').toBe(NAMES.ac5);
  });
});

// ── AC7: nothing automatic ─────────────────────────────────────────────

test.describe('[SCRUM-470] AC7 — the save changes only that value', () => {
  test('one value save touches exactly one record and produces no error/popup', async ({ page }) => {
    const id = ids[NAMES.ac2];
    const baseline = await countWithPreference();
    const othersBefore: Record<string, string | null> = {};
    for (const r of soql(`SELECT Id, ${FIELD_API} FROM Contact WHERE LastName LIKE '${TAG}%'`).records) {
      othersBefore[r.Id] = r[FIELD_API] ?? null;
    }
    const before = await contactFields(id, ['Phone', 'Email', 'LastName']);

    await openDetails(page, id);
    await pickValue(page, 'Letter');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = await countWithPreference();
    expect(after, `AC7: ${baseline} contacts carried a value, expected still ${baseline} (this save CHANGES one value, it must not add or remove a preference elsewhere)`).toBe(baseline);

    const now = await contactFields(id, ['Phone', 'Email', 'LastName']);
    expect(now.Phone, 'AC7: the phone number changed').toBe(before.Phone);
    expect(now.Email, 'AC7: the email changed').toBe(before.Email);
    expect(now.LastName, 'AC7: the name changed').toBe(before.LastName);

    // The sibling fixtures prove the save leaked nowhere: only the target may differ.
    const nowAll = soql(`SELECT Id, LastName, ${FIELD_API} FROM Contact WHERE LastName LIKE '${TAG}%'`).records;
    const changed = nowAll.filter((r: any) => (r[FIELD_API] ?? null) !== othersBefore[r.Id]);
    expect(changed.length, `AC7: ${changed.length} of the fixtures changed value (only the target may)`).toBe(1);
    expect(changed[0].Id, `AC7: the record that changed (${changed[0].Id}) is not the one the UI saved (${id})`).toBe(id);
    expect(await currentValue(id), 'AC7: the intended value itself did not land').toBe('Letter');

    const snap = await page.ariaSnapshot();
    expect(/snag|Validation|Error \(|reminder/i.test(snap), 'a popup/reminder/validation message appeared').toBe(false);
    const dialogs = await page.getByRole('dialog').all();
    for (const d of dialogs) {
      const name = (await d.getAttribute('aria-label').catch(() => null)) ?? '';
      expect(/Try the new Salesforce Setup/i.test(name), `unexpected dialog on save: ${name}`).toBe(true);
    }
  });
});
