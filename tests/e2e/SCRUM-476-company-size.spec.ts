import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, saveInlineEdit } from './record-page';
import { requireData } from './preflight';

/**
 * [SCRUM-476] E2E: "Company Size" on the customer (Account) — carried from the lead.
 *
 * Covered here (the UI side — the only place the customer record is opened, the
 * convert button is pressed and the band is maintained by hand):
 *   AC1  a lead with a band converted into a NEW customer shows exactly that band.
 *   AC2  a lead without a band converts cleanly, the new customer stays empty.
 *   AC3  the lead itself still shows its own band after the conversion.
 *   AC4  attach onto a customer that already has a band -> the customer keeps ITS band,
 *        even though the lead carries a DIFFERENT one (the PO's conflicting pair).
 *   AC5  attach onto a customer without a band -> it takes the lead's band.
 *   AC6  attach a band-less lead onto a band-less customer -> stays empty, saves cleanly.
 *   AC7  changing the band on the customer by hand shows the new band, no lead changes.
 *   AC8  clearing the band saves empty, no error, the customer is NOT deleted.
 *   AC9  only the four ranges (+ blank) can be entered — no free-text entry point.
 *   AC10 the band renders right below "Account Name" on the opened customer.
 *   AC11 at go-live no existing customer carries a band; nothing is defaulted/backfilled.
 *   AC12 setting/changing/clearing touches nothing else: no chatter post, email, task,
 *        re-assignment or extra record (delta measured on non-empty tables).
 *   AC13 changing an old lead's band after the customer has one never moves the customer's.
 *   batch: three conversions in one run, each new customer carries ITS OWN lead's band.
 *
 * NOT here (named in the coverage table, see docs/SCRUM-476-notizen-tester.md):
 *   200-record batch conversion — the org refuses it (one convertLead over 20 rows dies
 *   LIMIT_EXCEEDED at row 0; 30 single-record conversions die Too many SOQL queries: 101).
 *   Negative CRUD/FLS — Apex SCRUM476CompanySizeFlsTest (System.runAs; both Salesforce
 *   licences of this Developer Edition org are held by System Administrators, so no second
 *   browser session exists).
 *   AC13 on the Apex path — update of a converted Lead dies CANNOT_UPDATE_CONVERTED_LEAD.
 *
 * Locators were PROBED against THIS org on 2026-11-24 (never guessed):
 *   scratch/t476b/probe476c|d|e.mjs — Account record page, Details tab, edit mode, picker;
 *   scratch/t476b/probe476b.mjs — the Convert-Lead form.
 *   Measured: Account page `- text: Account Name <name>` then `- text: Phone` then
 *   `- text: Company Size <band label>` (one field row between, no heading);
 *   `button "Edit Company Size"`=1, `getByText('Company Size',{exact:true})`=1,
 *   combobox=1 only in edit mode, picker listbox "Company Size"=1 with 5 [role=option]
 *   (data-values '' , up_to_10, 11_to_50, 51_to_250, more_than_250 — labels only in the
 *   aria name); Lead page `button "Convert"`=1; after that click the form renders in place
 *   (URL unchanged): textbox "Account Name *" prefilled, combobox "Account Search"
 *   (= Choose Existing Account), combobox "Converted Status" (options 'Closed - Not
 *   Converted' / 'Converted'), then `button "Convert"` + `button "Cancel"`.
 */

const ORG = 'Test-Org';
const LABEL = 'Company Size';
const API = 'Company_Size__c';
const BANDS = ['up_to_10', '11_to_50', '51_to_250', 'more_than_250'];
const BAND_LABELS = [
  'up to 10 employees',
  '11 to 50 employees',
  '51 to 250 employees',
  'more than 250 employees',
];
// BANDS and BAND_LABELS are index-parallel (measured in the picker's data-values).
const labelOf = (v: string | null) => (v === null ? null : BAND_LABELS[BANDS.indexOf(v as string)]);

function shellJson(out: string): any {
  const clean = out.replace(/\[[0-9;]*[a-zA-Z]/gi, '');
  const s = clean.indexOf('{');
  const e = clean.lastIndexOf('}');
  if (s < 0 || e < s) throw new Error(`No JSON in sf answer: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(s, e + 1));
}
function soql(query: string): any {
  const out = execSync(
    `sf data query --query ${JSON.stringify(query)} --target-org ${ORG} --json 2>/dev/null || true`,
    { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0' } },
  );
  return shellJson(out).result;
}
function cli(cmd: string): any {
  // 2>&1, not 2>/dev/null: a failed seed must name its cause in the run log, not vanish.
  const parsed = shellJson(execSync(`${cmd} 2>&1 || true`, { encoding: 'utf-8', timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0' } }));
  if (parsed.status !== 0) console.log(`SEED/CLI ERROR ${cmd.slice(0, 120)} -> ${JSON.stringify(parsed).slice(0, 400)}`);
  else if (parsed.result && parsed.result.id) console.log(`SEED OK ${cmd.slice(0, 95)} -> id ${parsed.result.id}`);
  return parsed;
}

const accRows = (name: string) => soql(`SELECT Id, Name, ${API} FROM Account WHERE Name = '${name}'`).records;
const leadRows = (name: string) => soql(`SELECT Id, LastName, Company, ${API}, IsConverted, ConvertedAccountId FROM Lead WHERE LastName = '${name}'`).records;
const countOf = (q: string) => soql(q).totalSize;
// Chatter is attributed to the actor: a global FeedItem count also carries OTHER runs' posts
// (measured 2026-11-24: a sized conversion showed delta 6 vs 3 because an Apex/CI run posted
// in between), so the equality test must count only this session's user's posts.
let myUserId: string | null = null;
function resolveMyUser() {
  const rows = soql('SELECT Id, Username FROM User').records.filter((r: any) => String(r.Username).startsWith('devops-agent@'));
  if (rows.length !== 1) throw new Error(`the E2E session's org user is not resolvable (${rows.length} rows for devops-agent@)`);
  myUserId = rows[0].Id;
}
resolveMyUser();
const chatter = () => countOf(`SELECT Id FROM FeedItem WHERE CreatedById = '${myUserId}'`);
const chatterAll = () => countOf('SELECT Id FROM FeedItem');
const emails = () => countOf('SELECT Id FROM EmailMessage');
const tasks = () => countOf('SELECT Id FROM Task');
const contacts = () => countOf('SELECT Id FROM Contact');
const opps = () => countOf('SELECT Id FROM Opportunity');
const cases = () => countOf('SELECT Id FROM Case');
const accounts = () => countOf('SELECT Id FROM Account');

// ── fixtures ───────────────────────────────────────────────────────────
const TAG = 'TEST-SCRUM-476-E2E';

const CUST: Record<string, string> = {
  newSized: `${TAG}-C-NEW-SIZED`,
  newBlank: `${TAG}-C-NEW-BLANK`,
  existSized: `${TAG}-C-EXIST-SIZED`,
  existBlank: `${TAG}-C-EXIST-BLANK`,
  existBlank2: `${TAG}-C-EXIST-BLANK2`,
  hand: `${TAG}-C-HAND`,
  b1: `${TAG}-C-B1`,
  b2: `${TAG}-C-B2`,
  b3: `${TAG}-C-B3`,
  keep: `${TAG}-C-KEEP`,
  newBlankPair: `${TAG}-C-NB-PAIR`,
};
const LEADN: Record<string, string> = {
  newSized: `${TAG}-L-NEW-SIZED`,
  newBlank: `${TAG}-L-NEW-BLANK`,
  newBlankPair: `${TAG}-L-NB-PAIR`,
  keep: `${TAG}-L-KEEP`,
  attachSized: `${TAG}-L-ATTACH-SIZED`,
  attachFill: `${TAG}-L-ATTACH-FILL`,
  attachBlank: `${TAG}-L-ATTACH-BLANK`,
  hand: `${TAG}-L-HAND`,
  old: `${TAG}-L-OLD`,
  b1: `${TAG}-L-B1`,
  b2: `${TAG}-L-B2`,
  b3: `${TAG}-L-B3`,
};
const ids: Record<string, string> = {};

function seedFixtures() {
  // Sweep this spec's own namespace first: a previous run's leftovers would otherwise
  // satisfy the preconditions and make a re-run measure nothing.
  for (const t of [
    ...soql(`SELECT Id FROM Account WHERE Name LIKE '${TAG}%'`).records,
  ]) cli(`sf data delete record -s Account -i ${t.Id} --target-org ${ORG} --json`);
  for (const t of [...soql(`SELECT Id FROM Lead WHERE LastName LIKE '${TAG}%'`).records]) cli(`sf data delete record -s Lead -i ${t.Id} --target-org ${ORG} --json`);

  const mkAcc = (name: string, band?: string) =>
    cli(`sf data create record -s Account -v "Name=${name}${band ? ` ${API}=${band}` : ''}" --target-org ${ORG} --json`);
  // mkLead takes the fixture KEY and resolves the namespaced name from LEADN — passing the
  // key into -v created leads called literally "newSized" (measured in the SEED log).
  const mkLead = (key: string, company: string | null, band?: string) =>
    cli(`sf data create record -s Lead -v "LastName=${LEADN[key]}${company ? ` Company=${company}` : ''}${band ? ` ${API}=${band}` : ''}" --target-org ${ORG} --json`);

  mkAcc(CUST.existSized, '51_to_250');   // AC4: conflicting pair (lead carries up_to_10)
  mkAcc(CUST.existBlank);                 // AC5
  mkAcc(CUST.existBlank2);                // AC6
  mkAcc(CUST.hand, '11_to_50');           // AC7/AC8/AC13
  mkLead('newSized', CUST.newSized, 'more_than_250');
  mkLead('newBlank', CUST.newBlank);
  mkLead('newBlankPair', CUST.newBlankPair);
  mkLead('keep', CUST.keep, '51_to_250');
  // Measured: Company is REQUIRED on Lead and is a TEXT field (string 255), not a lookup —
  // a lead never creates or references a customer by itself. The attach relationship is
  // ConvertedAccountId (created:false), established by the conversion. So the text only names
  // the company the colleague typed, and the picker below chooses the customer.
  mkLead('attachSized', CUST.existSized, 'up_to_10');   // AC4 conflicting pair
  mkLead('attachFill', CUST.existBlank, 'more_than_250'); // AC5 fills a blank customer
  mkLead('attachBlank', CUST.existBlank2);               // AC6 nothing to carry
  mkLead('hand', CUST.hand, '11_to_50');
  mkLead('old', CUST.existSized, '51_to_250');           // AC13: becomes "old" by attaching first
  mkLead('b1', CUST.b1, 'up_to_10');
  mkLead('b2', CUST.b2, 'more_than_250');
  mkLead('b3', CUST.b3, '11_to_50');

  // Two fixture shapes: customers that must already exist (the attach criteria), and
  // customers that must NOT exist yet — they are created by the conversion under test.
  const preExisting = ['existSized', 'existBlank', 'existBlank2', 'hand'];
  // Customers the conversion under test is expected to create (Company text creates nothing:
  // measured Account total 268 before and after a lead with an unseen Company name).
  const createdByTest = ['newSized', 'newBlank', 'newBlankPair', 'keep', 'b1', 'b2', 'b3'];
  for (const k of preExisting) {
    const rows = accRows(CUST[k]);
    if (rows.length !== 1) throw new Error(`fixture customer ${CUST[k]} has ${rows.length} rows (name must be unique among fixtures)`);
    ids[`c_${k}`] = rows[0].Id;
  }
  for (const k of createdByTest) {
    const rows = accRows(CUST[k]);
    if (rows.length !== 0) throw new Error(`fixture customer ${CUST[k]} already has ${rows.length} rows — the conversion would not create a NEW customer`);
  }
  for (const k of Object.keys(LEADN)) {
    const rows = leadRows(LEADN[k]);
    if (rows.length !== 1) {
      const all = soql(`SELECT Id, LastName FROM Lead WHERE LastName LIKE '${TAG}%'`).records;
      console.log(`SEED DIAG wanted ${LEADN[k]} got ${rows.length}; org holds ${all.length}: ${all.map((x: any) => x.LastName).join(' | ')}`);
      throw new Error(`fixture lead ${LEADN[k]} has ${rows.length} rows`);
    }
    ids[`l_${k}`] = rows[0].Id;
  }
}

test.beforeAll(() => {
  // AC11 baseline BEFORE any fixture: no REAL customer may carry a band yet.
  // 'TEST-*' names are other runs'/agents' fixture namespaces — they are org pollution
  // (measured 2026-11-24: 42 customers named TEST-476-Limit* carry a band), never the
  // criterion. They are named, not deleted: they are not this run's namespace.
  const sizedAny = soql(`SELECT Id, Name FROM Account WHERE ${API} != null`).records;
  const sizedForeign = sizedAny.filter((r: any) => !String(r.Name).startsWith(TAG));
  // 'TEST-*' and 'PROBE-*' are other runs' fixture/probe namespaces — probe leftovers of other
  // agents (measured 2026-11-24: PROBE-476M-CUST ×3 with bands, TEST-476-Limit* ×42). They are
  // named below, never deleted here (not this run's namespace), and never counted as REAL.
  const sizedReal = sizedForeign.filter((r: any) => !String(r.Name).startsWith('TEST-') && !String(r.Name).startsWith('PROBE-'));
  const sizedForeignFixtures = sizedForeign.length - sizedReal.length;
  if (sizedReal.length > 0) {
    throw new Error(`AC11 precondition broken at go-live: ${sizedReal.length} real customers already carry a band (${sizedReal.slice(0, 3).map((r: any) => r.Name).join(', ')})`);
  }
  if (sizedForeignFixtures > 0) {
    console.log(`ORG POLLUTION: ${sizedForeignFixtures} customers outside this run's namespace already carry a band, all named TEST-* (fixture leftovers of other agents' runs; left untouched)`);
  }
  seedFixtures();
  requireData([
    { ac: 'AC11', what: 'existing customers in the org (268 measured 2026-11-24)', soql: 'SELECT Id FROM Account', min: 1 },
    { ac: 'fixtures', what: 'this run\'s pre-existing fixture customers (attach criteria need them)', soql: `SELECT Id FROM Account WHERE Name LIKE '${TAG}%'`, min: 4 },
    { ac: 'fixtures', what: 'this run\'s fixture leads', soql: `SELECT Id FROM Lead WHERE LastName LIKE '${TAG}%'`, min: 12 },
    { ac: 'AC4', what: 'a fixture customer that already carries a band', soql: `SELECT Id FROM Account WHERE ${API} != null`, min: 1 },
    { ac: 'AC5/AC6', what: 'fixture customers without a band', soql: `SELECT Id FROM Account WHERE ${API} = null AND Name LIKE '${TAG}%'`, min: 2 },
    { ac: 'AC12', what: 'chatter posts in the org (900 measured: makes the no-side-effect guard falsifiable)', soql: 'SELECT Id FROM FeedItem', min: 1 },
    { ac: 'AC12', what: 'contacts in the org (680 measured: delta must stay 0 on a hand edit)', soql: 'SELECT Id FROM Contact', min: 1 },
    { ac: 'AC12', what: 'cases in the org (681 measured)', soql: 'SELECT Id FROM Case', min: 1 },
  ]);
});

test.afterAll(() => {
  for (const t of [...soql(`SELECT Id FROM Account WHERE Name LIKE '${TAG}%'`).records]) cli(`sf data delete record -s Account -i ${t.Id} --target-org ${ORG} --json`);
  for (const t of [...soql(`SELECT Id FROM Lead WHERE LastName LIKE '${TAG}%'`).records]) cli(`sf data delete record -s Lead -i ${t.Id} --target-org ${ORG} --json`);
});

// ── helpers (all probed 2026-11-24 against this org) ───────────────────

async function dismissGuidance(page: import('@playwright/test').Page) {
  const dlg = page.getByRole('dialog', { name: /Try the new Salesforce Setup/i });
  if ((await dlg.count()) > 0) {
    await dlg.getByRole('button').first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

async function openCustomer(page: import('@playwright/test').Page, key: string) {
  await openRecordDetails(page, `/lightning/r/Account/${ids[`c_${key}`]}/view`);
  await dismissGuidance(page);
}

async function openLead(page: import('@playwright/test').Page, key: string) {
  await openRecordDetails(page, `/lightning/r/Lead/${ids[`l_${key}`]}/view`);
  await dismissGuidance(page);
}

/** Rendered band on the Details tab: the aria row `- text: Company Size <label>`. */
async function renderedBand(page: import('@playwright/test').Page): Promise<string | null> {
  const snap = await page.ariaSnapshot();
  const line = snap.split('\n').find((l) => /text: Company Size/.test(l));
  if (!line) return null;
  const m = /text: Company Size (.+)$/.exec(line.replace(/\s+/g, ' ').trim());
  if (!m) return null;
  const label = m[1].trim();
  if (label === '') return null;
  expect(BAND_LABELS, `AC9/AC10: a rendered band must be one of the four ranges, got "${label}"`).toContain(label);
  return label;
}

/** Field rows between `- text: Account Name …` and `- text: Company Size …` (AC10 adjacency). */
async function rowsBetweenNameAndSize(page: import('@playwright/test').Page): Promise<number> {
  const lines = (await page.ariaSnapshot()).split('\n').map((l) => l.trim());
  const name = lines.findIndex((l) => /^- text: Account Name/.test(l));
  const size = lines.findIndex((l) => /^- text: Company Size/.test(l));
  expect(name, 'no `- text: Account Name …` row rendered').toBeGreaterThan(-1);
  expect(size, 'no `- text: Company Size …` row rendered').toBeGreaterThan(-1);
  expect(size).toBeGreaterThan(name);
  const between = lines.slice(name + 1, size);
  expect(between.filter((l) => /^- heading/.test(l)), 'Company Size renders in a different Details section than Account Name').toHaveLength(0);
  return between.filter((l) => /^- text: /.test(l)).length;
}

/** The picker for the band on the customer (verified: combobox exists only in edit mode). */
async function openBandPicker(page: import('@playwright/test').Page) {
  // Measured (probe 476n + runs g6/g8 error contexts, 2026-11-24/25) on /lightning/r/Account/<id>/view:
  //  - fresh Details tab: exactly one `button "Edit Company Size"`, no combobox, no listbox
  //  - tab an earlier step already put in edit mode: `combobox "Company Size" [expanded]` +
  //    `listbox "Company Size"` and NO button
  //  - tab left in SELECTION mode after a previous picker (run g8, AC13): `combobox "Company Size":
  //    51 to 250 employees` — a value already chosen, NO listbox and NO button
  // So the helper has three entry routes and always ends at one open listbox.
  const lb = page.getByRole('listbox', { name: LABEL, exact: true });
  const combo = page.getByRole('combobox', { name: LABEL, exact: true });
  const btn = page.getByRole('button', { name: `Edit ${LABEL}`, exact: true });
  for (let i = 0; i < 10; i++) { if ((await lb.count()) === 1) break; await page.waitForTimeout(2000); }
  if ((await lb.count()) === 1) return lb.first();
  for (let i = 0; i < 10; i++) { if ((await btn.count()) === 1 || (await combo.count()) === 1) break; await page.waitForTimeout(2000); }
  const seen = (await page.ariaSnapshot()).split('\n').filter((l) => /Company Size/.test(l)).slice(0, 8);
  const route = (await btn.count()) === 1 ? 'edit-button' : (await combo.count()) === 1 ? 'selection' : 'none';
  expect(route, `neither "Edit ${LABEL}" nor an already-selected combobox on the customer; aria lines seen: ${JSON.stringify(seen)}`).isNotEqualTo('none');
  if (route === 'edit-button') {
    await btn.first().click({ timeout: 15000 });
    for (let i = 0; i < 8; i++) { if ((await combo.count()) === 1) break; await page.waitForTimeout(2000); }
    await expect(await combo.count(), `combobox "${LABEL}" not in edit mode after the Edit button`).toBe(1);
  }
  for (let attempt = 0; attempt < 3; attempt++) {
    if ((await lb.count()) === 1) break;
    await combo.first().click({ timeout: 15000 });
    await page.waitForTimeout(2500);
  }
  await expect(await lb.count(), `picker listbox "${LABEL}" never opened`).toBe(1);
  return lb.first();
}

async function pickBand(page: import('@playwright/test').Page, dataValue: string) {
  const lb = await openBandPicker(page);
  const opt = lb.locator(`[role=option][data-value="${dataValue}"]`);
  await expect(await opt.count(), `picker slot data-value="${dataValue}" not unique/absent`).toBe(1);
  await opt.first().click({ timeout: 15000 });
  await page.waitForTimeout(1200);
}

/**
 * Run the Convert-Lead form to the end. `existingCustomerKey` = null presses the
 * "Create New Account" path (the name textbox is prefilled from the lead's Company);
 * a key selects the existing customer in the "Account Search" lookup picker.
 */
async function convertLeadForm(page: import('@playwright/test').Page, leadKey: string, existingCustomerKey: string | null) {
  await openLead(page, leadKey);
  const openBtn = page.getByRole('button', { name: 'Convert', exact: true });
  await expect(await openBtn.count(), '"Convert" action button not on the lead page').toBe(1);
  await openBtn.first().click({ timeout: 15000 });
  await page.waitForTimeout(5000);
  const head = page.getByText('Convert Lead', { exact: true });
  await expect(head, 'the Convert Lead form did not open').toBeVisible({ timeout: 20000 });

  if (existingCustomerKey) {
    const search = page.getByRole('combobox', { name: 'Account Search', exact: true });
    await expect(await search.count(), 'the "Account Search" picker is not on the form').toBe(1);
    // Measured (probe, 2026-11-24): fill the query first, ONE click opens the picker, which
    // renders the record as an option in a nested listbox. A second click CLOSES it, so the
    // retry loop must not click again — it polls the rendered option and fails with the
    // picker's own aria lines.
    await search.first().fill(CUST[existingCustomerKey]);
    await page.waitForTimeout(1500);
    // Measured (probe 2026-11-24): the picker offers the SEARCH prompt; clicking it opens an
    // "Account Results" panel, and clicking the record's LINK there selects that record in
    // the form ('Account Search - Current Selection: <name>'). Clicking the nested record
    // OPTION instead navigates away and closes the form — measured, that path converts nothing.
    const prompt = page.getByRole('option', { name: /Search for matching accounts/ });
    for (let i = 0; i < 10; i++) { if ((await prompt.count()) > 0) break; await page.waitForTimeout(2000); }
    await expect(await prompt.count(), '"Account Search" never offered its search prompt').toBeGreaterThan(0);
    await prompt.first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);
    const row = page.getByRole('link', { name: CUST[existingCustomerKey], exact: true });
    for (let i = 0; i < 10; i++) { if ((await row.count()) > 0) break; await page.waitForTimeout(2000); }
    await expect(await row.count(), `the results panel lists no row link for ${CUST[existingCustomerKey]}`).toBe(1);
    await row.first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);
    const sel = await page.ariaSnapshot();
    expect(sel, `"Account Search" did not select the existing customer`).toContain(`Current Selection: ${CUST[existingCustomerKey]}`);
  }

  // Converted Status must end up 'Converted' — the picklist the conversion keys on.
  // Measured (run g8, AC1/AC3): the heading paints BEFORE the form's pickers, so both are polled.
  const statusCombo = page.getByRole('combobox', { name: 'Converted Status', exact: true });
  for (let i = 0; i < 10; i++) { if ((await statusCombo.count()) === 1) break; await page.waitForTimeout(2000); }
  await expect(await statusCombo.count(), 'the "Converted Status" picker is not on the form (polled 20 s after the heading)').toBe(1);
  const convOpt = page.getByRole('option', { name: 'Converted', exact: true });
  for (let i = 0; i < 4; i++) {
    if ((await convOpt.count()) === 1) break;
    await statusCombo.first().click({ timeout: 15000 });
    await page.waitForTimeout(2000);
  }
  await expect(await convOpt.count(), 'the Converted Status picker never offers "Converted"').toBe(1);
  await convOpt.first().click({ timeout: 15000 });
  await page.waitForTimeout(1200);
  // Measured: once the form is open the page carries TWO buttons named "Convert" (the record-page
  // action and the form's submit). The submit is the one under the "Convert Lead" heading.
  const headBox = await head.boundingBox();
  if (!headBox) throw new Error('the "Convert Lead" heading has no box — cannot locate the submit button');
  const cands = await page.getByRole('button', { name: 'Convert', exact: true }).all();
  let submit = null;
  let best = Number.MAX_SAFE_INTEGER;
  for (const c of cands) {
    const b = await c.boundingBox();
    if (!b) continue;
    if (b.y > headBox.y + 10 && b.y - headBox.y < best) { best = b.y - headBox.y; submit = c; }
  }
  if (!submit) throw new Error('the Convert Lead form\'s own submit button was not found below the heading');
  await submit.click({ timeout: 15000 });
  await page.waitForTimeout(6000);
}

function observed(ac: string, text: string) {
  console.log(`OBSERVED ${ac}: ${text}`);
  test.info().annotations.push({ type: 'observed', description: `${ac}: ${text}` });
}

// Record what exists NOW, and the delta of an action. AC12 is an EQUALITY test: OWD itself
// posts chatter on a conversion (measured 2026-11-24: a conversion adds 3 FeedItems), so "the
// size changes nothing else" is only falsifiable against the same conversion WITHOUT a size.
function snap() {
  return { feed: chatter(), email: emails(), task: tasks(), contact: contacts(), opp: opps(), case: cases(), account: accounts(), chatterAll: chatterAll() };
}
function diff(a: Record<string, number>, b: Record<string, number>) {
  const out: Record<string, number> = {};
  for (const k of Object.keys(a)) out[k] = b[k] - a[k];
  return out;
}

// ── AC1 + AC3: new customer from a sized lead, the lead keeps its own band ──
test.describe('[SCRUM-476] AC1/AC3 — a sized lead converted into a new customer', () => {
  test('the new customer carries exactly the lead\'s band, the lead is unchanged', async ({ page }) => {
    test.setTimeout(300000);
    const before = leadRows(LEADN.newSized)[0];
    expect(before[API], 'fixture lead must carry a band').toBe('more_than_250');
    expect(before.IsConverted, 'fixture lead must be unconverted').toBe(false);
    const beforeSized = snap();

    await convertLeadForm(page, 'newSized', null);

    const rows = accRows(CUST.newSized);
    expect(rows.length, 'AC1: exactly one customer with the lead\'s name exists after the conversion').toBe(1);
    ids['c_newSized'] = rows[0].Id;
    expect(rows[0][API], 'AC1: the new customer carries exactly the lead\'s band').toBe('more_than_250');

    // Same conversion WITHOUT a size, measured right after: the pair is what makes AC12
    // falsifiable. A band-less lead is a legal conversion in the same org state.
    const blankFixture = leadRows(LEADN.newBlankPair)[0];
    expect(blankFixture[API], 'the comparison lead must carry no band').toBeNull();
    // The sized window must END before the band-less conversion starts: one conversion already
    // adds its own record chatter, so measuring both inside one window compared 6 vs 3 (run g3,
    // line 425) — a spec bug, not a product one. Two windows, each around ONE conversion.
    const dSized = diff(beforeSized, snap());
    const beforeBlank = snap();
    await convertLeadForm(page, 'newBlankPair', null);
    const blankRows = accRows(CUST.newBlankPair);
    expect(blankRows.length, 'the band-less conversion created its customer too').toBe(1);
    expect(blankRows[0][API], 'the band-less customer stays empty').toBeNull();
    const dBlank = diff(beforeBlank, snap());
    for (const k of ['feed', 'email', 'task', 'contact', 'opp', 'case']) {
      expect(dSized[k], `AC12: the sized conversion touches no more ${k} than the band-less one`).toBe(dBlank[k]);
    }
    expect(dSized.account, 'AC1: each conversion created exactly its own one customer').toBe(1);
    expect(dBlank.account, 'AC12: ditto for the band-less conversion').toBe(1);

    const leadAfter = leadRows(LEADN.newSized)[0];
    // The house rule: assert the save NAMED the record before asserting anything about it.
    expect(leadAfter.ConvertedAccountId, 'AC1: the conversion names the customer it created').toBe(rows[0].Id);
    expect(leadAfter[API], 'AC3: the converted lead still shows its own band').toBe('more_than_250');
    expect(leadAfter.IsConverted, 'AC3: the lead is converted now').toBe(true);

    // Post-reload persistence: a fresh visit renders the carried band, near the name.
    await openCustomer(page, 'newSized');
    const rendered = await renderedBand(page);
    expect(rendered, 'AC1: the band renders on the opened customer').toBe('more than 250 employees');
    const gap = await rowsBetweenNameAndSize(page);
    expect(gap, 'AC10: the band sits close under Account Name (max 2 field rows)').toBeLessThanOrEqual(2);
    observed('AC1/AC3/AC12', `lead ${ids.l_newSized} ${API}=more_than_250 -> customer ${rows[0].Id} ${API}=more_than_250; sized conversion deltas ${JSON.stringify(dSized)} vs band-less conversion deltas ${JSON.stringify(dBlank)} (equal on feed/email/task/contact/opp/case); lead still ${API}=more_than_250, IsConverted=true; page renders "${rendered}" ${gap} rows under Account Name`);
  });
});

// ── AC2: a band-less lead converts cleanly, the customer stays empty ──────
test.describe('[SCRUM-476] AC2 — a lead without a band', () => {
  test('conversion saves cleanly, the new customer has no band', async ({ page }) => {
    test.setTimeout(300000);
    const before = leadRows(LEADN.newBlank)[0];
    expect(before[API], 'AC2 fixture starts without a band').toBeNull();
    const accBefore = accounts();

    await convertLeadForm(page, 'newBlank', null);

    const rows = accRows(CUST.newBlank);
    expect(rows.length, 'AC2: the customer was created — the conversion saved cleanly, no error').toBe(1);
    ids['c_newBlank'] = rows[0].Id;
    expect(rows[0][API], 'AC2: the new customer starts without a band').toBeNull();
    expect(accounts() - accBefore, 'AC2: exactly one customer created').toBe(1);
    await openCustomer(page, 'newBlank');
    const rendered = await renderedBand(page);
    expect(rendered, 'AC2: the opened customer renders no band').toBeNull();
    observed('AC2', `blank lead ${ids.l_newBlank} -> customer ${rows[0].Id} ${API}=null, created=${accounts() - accBefore === 1}, page renders no band`);
  });
});

// ── AC4: attach onto a customer that already has a band — never overwritten ─
test.describe('[SCRUM-476] AC4 — attach onto a sized customer (conflicting band)', () => {
  test('the customer keeps its own 51_to_250 although the lead says up_to_10', async ({ page }) => {
    test.setTimeout(300000);
    const custBefore = accRows(CUST.existSized)[0];
    const leadBefore = leadRows(LEADN.attachSized)[0];
    expect(custBefore[API], 'AC4 fixture customer carries 51_to_250').toBe('51_to_250');
    expect(leadBefore[API], 'AC4 fixture lead carries the DIFFERENT band up_to_10').toBe('up_to_10');
    const accBefore = accounts();

    await convertLeadForm(page, 'attachSized', 'existSized');

    const custAfter = accRows(CUST.existSized)[0];
    expect(custAfter[API], 'AC4: the existing band was NOT overwritten by the lead\'s different band').toBe('51_to_250');
    expect(leadBefore.IsConverted, 'AC4 precondition: lead unconverted').toBe(false);
    const leadAfter = leadRows(LEADN.attachSized)[0];
    expect(leadAfter.ConvertedAccountId, 'AC4: the attach names the EXISTING customer, not a new one').toBe(custAfter.Id);
    expect(leadAfter.IsConverted, 'AC4: the attach converted the lead').toBe(true);
    expect(leadAfter[API], 'AC4: the lead keeps its own band').toBe('up_to_10');
    expect(accounts() - accBefore, 'AC4: attaching created NO new customer').toBe(0);
    await openCustomer(page, 'existSized');
    const rendered = await renderedBand(page);
    expect(rendered, 'AC4: the opened customer still renders its own band').toBe('51 to 250 employees');
    observed('AC4', `lead ${ids.l_attachSized} up_to_10 attached to customer ${custAfter.Id} holding 51_to_250 -> still 51_to_250 (no overwrite), Account delta ${accounts() - accBefore}, page renders "${rendered}"`);
  });
});

// ── AC5: attach onto a customer without a band — it takes the lead's ──────
test.describe('[SCRUM-476] AC5 — attach onto a blank customer', () => {
  test('the blank customer takes the lead\'s more-than-250 band', async ({ page }) => {
    test.setTimeout(300000);
    const custBefore = accRows(CUST.existBlank)[0];
    const leadBefore = leadRows(LEADN.attachFill)[0];
    expect(custBefore[API], 'AC5 fixture customer has no band').toBeNull();
    expect(leadBefore[API], 'AC5 fixture lead carries more_than_250').toBe('more_than_250');
    const accBefore = accounts();

    await convertLeadForm(page, 'attachFill', 'existBlank');

    const custAfter = accRows(CUST.existBlank)[0];
    const leadAttach = leadRows(LEADN.attachFill)[0];
    expect(leadAttach.ConvertedAccountId, 'AC5: the attach names the existing customer before anything else').toBe(custBefore.Id);
    expect(custAfter.Id, 'AC5: still the SAME customer record').toBe(custBefore.Id);
    expect(custAfter[API], 'AC5: the blank customer took the lead\'s band').toBe('more_than_250');
    expect(accounts() - accBefore, 'AC5: no second customer created').toBe(0);
    await openCustomer(page, 'existBlank');
    const rendered = await renderedBand(page);
    expect(rendered, 'AC5: the opened customer renders the new band').toBe('more than 250 employees');
    observed('AC5', `lead ${ids.l_attachFill} more_than_250 -> existing customer ${custAfter.Id} null -> ${custAfter[API]}, same record, Account delta ${accounts() - accBefore}, page renders "${rendered}"`);
  });
});

// ── AC6: band-less lead onto band-less customer — stays empty ─────────────
test.describe('[SCRUM-476] AC6 — a band-less attach', () => {
  test('the blank customer stays blank and saves cleanly', async ({ page }) => {
    test.setTimeout(300000);
    const custBefore = accRows(CUST.existBlank2)[0];
    const leadBefore = leadRows(LEADN.attachBlank)[0];
    expect(custBefore[API], 'AC6 fixture customer blank').toBeNull();
    expect(leadBefore[API], 'AC6 fixture lead blank').toBeNull();

    await convertLeadForm(page, 'attachBlank', 'existBlank2');

    const custAfter = accRows(CUST.existBlank2)[0];
    const leadAttach = leadRows(LEADN.attachBlank)[0];
    expect(leadAttach.ConvertedAccountId, 'AC6: the band-less attach names the existing customer').toBe(custBefore.Id);
    expect(leadAttach[API], 'AC6: the lead still carries no band').toBeNull();
    expect(custAfter.Id, 'AC6: same record, the attach saved cleanly').toBe(custBefore.Id);
    expect(custAfter[API], 'AC6: the customer stays empty').toBeNull();
    await openCustomer(page, 'existBlank2');
    expect(await renderedBand(page), 'AC6: the opened customer renders no band').toBeNull();
    observed('AC6', `blank lead ${ids.l_attachBlank} -> customer ${custAfter.Id} ${API}=null, same record, page renders nothing`);
  });
});

// ── AC7/AC8: hand-maintained on the customer — change, then clear ─────────
test.describe('[SCRUM-476] AC7/AC8 — set / change / clear on the customer', () => {
  test('the band changes to another range, nothing else moves', async ({ page }) => {
    test.setTimeout(300000);
    const before = accRows(CUST.hand)[0];
    expect(before[API], 'AC7 fixture customer starts at 11_to_50').toBe('11_to_50');
    const countsBefore = { feed: chatter(), email: emails(), task: tasks(), contact: contacts(), opp: opps(), case: cases(), acc: accounts() };

    await openCustomer(page, 'hand');
    await pickBand(page, 'up_to_10');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = accRows(CUST.hand)[0];
    expect(after[API], 'AC7: the customer shows the chosen range').toBe('up_to_10');
    expect(after.Id, 'AC7: same record').toBe(before.Id);
    expect(chatter() - countsBefore.feed, 'AC7: no chatter post').toBe(0);
    expect(contacts() - countsBefore.contact, 'AC7: no contact created').toBe(0);
    expect(opps() - countsBefore.opp, 'AC7: no opportunity created').toBe(0);
    expect(cases() - countsBefore.case, 'AC7: no case created').toBe(0);
    expect(accounts() - countsBefore.acc, 'AC7: no extra customer').toBe(0);
    // No lead changed: every fixture lead keeps its own band.
    for (const k of Object.keys(LEADN)) {
      const l = leadRows(LEADN[k])[0];
      const orig = { attachSized: 'up_to_10', attachFill: 'more_than_250', keep: '51_to_250', hand: '11_to_50', old: '51_to_250', b1: 'up_to_10', b2: 'more_than_250', b3: '11_to_50', newSized: 'more_than_250' }[k];
      if (orig) expect(l[API], `AC7: lead ${LEADN[k]} must still carry ${orig}`).toBe(orig);
    }
    await openCustomer(page, 'hand');
    expect(await renderedBand(page), 'AC7: after reload the page renders the new band').toBe('up to 10 employees');
    observed('AC7', `customer ${ids.c_hand} 11_to_50 -> up_to_10 via picker+Save; deltas Feed ${chatter() - countsBefore.feed}, Contact ${contacts() - countsBefore.contact}, Opp ${opps() - countsBefore.opp}, Case ${cases() - countsBefore.case}, Account ${accounts() - countsBefore.acc}; all 9 sized fixture leads unchanged`);
  });

  test('clearing the band saves empty and does not delete the customer', async ({ page }) => {
    test.setTimeout(300000);
    const before = accRows(CUST.hand)[0];
    const countsBefore = { feed: chatter(), email: emails(), task: tasks(), acc: accounts() };

    await openCustomer(page, 'hand');
    const lb = await openBandPicker(page);
    const offered = await lb.locator('[role=option]').evaluateAll((es) => es.map((e) => e.getAttribute('data-value')));
    expect(offered, 'AC9: the picker offers exactly the blank slot plus the four ranges').toEqual(['', ...BANDS]);
    await pickBand(page, '');
    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const rows = accRows(CUST.hand);
    expect(rows.length, 'AC8: clearing must NOT delete the customer').toBe(1);
    expect(rows[0][API], 'AC8: the band is empty again').toBeNull();
    expect(rows[0].Name, 'AC8: the customer is still there under its name').toBe(CUST.hand);
    expect(chatter() - countsBefore.feed, 'AC8: no chatter post').toBe(0);
    expect(emails() - countsBefore.email, 'AC8: no email (measured empty table — cannot falsify, see notes)').toBe(0);
    expect(tasks() - countsBefore.task, 'AC8: no task (measured empty table — cannot falsify, see notes)').toBe(0);
    expect(accounts() - countsBefore.acc, 'AC8: no extra record').toBe(0);
    observed('AC8/AC9', `picker offered ${JSON.stringify(offered)} (blank + 4 ranges, no free text); customer ${rows[0].Id} up_to_10 -> null, survives, deltas 0`);
  });
});

// ── AC10/AC11: visible near the name for everyone who opens the customer ──
test.describe('[SCRUM-476] AC10/AC11 — visibility next to Account Name, nothing backfilled', () => {
  test('a foreign customer renders no band; the fixture renders it right under the name', async ({ page }) => {
    test.setTimeout(300000);
    const foreignSizedAll = soql(`SELECT Id, Name FROM Account WHERE ${API} != null`).records
      .filter((r: any) => !String(r.Name).startsWith(TAG));
    const foreignSized = foreignSizedAll.filter((r: any) => !String(r.Name).startsWith('TEST-') && !String(r.Name).startsWith('PROBE-'));
    expect(foreignSized.length, 'AC11: no REAL customer outside this run\'s fixtures may carry a band').toBe(0);
    const foreignFixtureSized = foreignSizedAll.length - foreignSized.length;
    const foreignTotal = accounts();
    const fixtureTotal = soql(`SELECT Id FROM Account WHERE Name LIKE '${TAG}%'`).totalSize;
    expect(fixtureTotal, 'AC11: this run seeded fixture customers to measure on').toBeGreaterThan(0);

    // An earlier block may have changed this customer's band; the criterion is that the page
    // shows the band the ORG holds, next to the name — so compare against the org read-back.
    // AC8 (an earlier block, same seed) CLEARS C-HAND, so measure the visibility criterion on
    // C-EXIST-SIZED, whose band no block ever clears.
    const orgBand = accRows(CUST.existSized)[0][API];
    expect(BANDS, 'AC10 precondition: the org band of the fixture customer is one of the four ranges').toContain(orgBand);
    await openCustomer(page, 'existSized');
    const rendered = await renderedBand(page);
    const gap = await rowsBetweenNameAndSize(page);
    expect(rendered, `AC10: the opened page renders the band the org holds (${orgBand} -> "${labelOf(orgBand)}")`).toBe(labelOf(orgBand));
    expect(gap, 'AC10: the band is close to Account Name, not in some other section').toBeLessThanOrEqual(2);
    observed('AC10/AC11', `${foreignTotal} customers in the org, ${foreignSized.length} real customers outside this run carry a band (expected 0 — nothing backfilled), ${foreignFixtureSized} TEST-* fixture leftovers carry one (other agents' runs, untouched), ${fixtureTotal} fixture customers, page renders "${rendered}" ${gap} rows under Account Name`);
  });
});

// ── AC12: no side effects around a conversion ────────────────────────────
test.describe('[SCRUM-476] AC12 — a conversion touches nothing else', () => {
  test('the sized conversion creates its customer plus the usual lead records, and no chatter', async ({ page }) => {
    test.setTimeout(300000);
    const beforeSized = snap();
    await convertLeadForm(page, 'keep', null);
    const dSized = diff(beforeSized, snap());
    // comparison: the same kind of conversion for a lead WITHOUT a size (an attach here,
    // so the Account delta is allowed to differ — only the side-effect tables must match)
    const blankFixture = leadRows(LEADN.attachBlank)[0];
    expect(blankFixture[API], 'the comparison lead carries no band').toBeNull();
    const beforeBlank = snap();
    await convertLeadForm(page, 'attachBlank', 'existBlank2');
    const dBlank = diff(beforeBlank, snap());
    for (const k of ['feed', 'email', 'task', 'contact', 'opp', 'case']) {
      expect(dSized[k], `AC12: the sized conversion causes no ${k} side effect beyond a band-less conversion`).toBe(dBlank[k]);
    }
    expect(dSized.account, 'AC12: the create-new conversion created exactly one customer').toBe(1);
    expect(dBlank.account, 'AC12: the attach created no customer').toBe(0);
    const cust = accRows(CUST.keep);
    expect(cust.length, 'AC12: exactly one customer named after the lead exists').toBe(1);
    expect(cust[0][API], 'AC12: the new customer carries its own lead\'s band').toBe('51_to_250');
    const leadAfter = leadRows(LEADN.keep)[0];
    expect(leadAfter.IsConverted, 'AC12: the conversion ran').toBe(true);
    expect(leadAfter[API], 'AC12: the lead still carries its own band').toBe('51_to_250');
    observed('AC12', `sized create-new conversion deltas ${JSON.stringify(dSized)} vs band-less attach deltas ${JSON.stringify(dBlank)} — equal on feed/email/task/contact/opp/case, Account 1 vs 0 as the paths differ`);
  });
});

// ── AC13: an old lead's band never moves the customer ────────────────────
test.describe('[SCRUM-476] AC13 — changing an old lead after the customer has a band', () => {
  test('the customer keeps its band, whatever the UI did to the converted lead', async ({ page }) => {
    test.setTimeout(300000);
    const custBefore = accRows(CUST.existSized)[0];
    const leadBefore = leadRows(LEADN.old)[0];
    expect(custBefore[API], 'AC13: the customer already carries a band').toBe('51_to_250');
    const bandBefore = custBefore[API];
    // "an old lead" = a lead that was already converted onto that customer. The attach is
    // the event, the later edit is the criterion — so the attach runs here first.
    await convertLeadForm(page, 'old', 'existSized');
    const leadMid = leadRows(LEADN.old)[0];
    expect(leadMid.ConvertedAccountId, 'AC13: the attach names the existing customer before anything else').toBe(custBefore.Id);
    expect(leadMid.IsConverted, 'AC13: the lead is now converted onto the customer').toBe(true);

    await openLead(page, 'old');
    // Measured: the Apex path refuses to update a converted lead (CANNOT_UPDATE_CONVERTED_LEAD).
    // On the UI path the Edit control may or may not be offered — BOTH outcomes are asserted,
    // and the criterion (the customer's band never moves) is checked after either.
    const btn = page.getByRole('button', { name: `Edit ${LABEL}`, exact: true });
    const offered = await btn.count();
    // Playwright BDD has no toBeOneOf (run g3: TypeError "not a function"). The guard that
    // matters is "at most one control", and OBSERVED says which of the two outcomes happened.
    expect(offered, 'the lead page offers at most one Edit Company Size control').toBeLessThanOrEqual(1);
    if (offered === 1) {
      await btn.first().click({ timeout: 15000 });
      await page.waitForTimeout(2500);
      await pickBand(page, 'more_than_250');
      await saveInlineEdit(page);
      await page.waitForTimeout(4000);
    }

    const leadAfter = leadRows(LEADN.old)[0];
    const custAfter = accRows(CUST.existSized)[0];
    expect(custAfter[API], `AC13: the customer's band must not move (was ${bandBefore})`).toBe(bandBefore);
    expect(custAfter.Id, 'AC13: still the same customer record').toBe(custBefore.Id);
    observed('AC13', `old lead ${ids.l_old} ${API} ${leadBefore[API]} -> ${leadAfter[API]}, ConvertedAccountId=${leadAfter.ConvertedAccountId}; UI offered ${offered} Edit controls on the converted lead (1 = the edit ran, 0 = platform refused); customer ${custAfter.Id} stayed ${bandBefore}`);
  });
});

// ── batch: every new customer takes the size of ITS OWN lead ─────────────
test.describe('[SCRUM-476] batch — three conversions, each customer its own band', () => {
  test('three leads, three customers, three different bands, no cross-wiring', async ({ page }) => {
    test.setTimeout(300000);
    const want: Record<string, string> = { b1: 'up_to_10', b2: 'more_than_250', b3: '11_to_50' };
    for (const k of Object.keys(want)) expect(leadRows(LEADN[k])[0][API], `batch fixture ${k} carries ${want[k]}`).toBe(want[k]);
    const accBefore = accounts();

    await convertLeadForm(page, 'b1', null);
    await convertLeadForm(page, 'b2', null);
    await convertLeadForm(page, 'b3', null);

    for (const k of Object.keys(want)) {
      const rows = accRows(CUST[k]);
      expect(rows.length, `batch: exactly one customer per lead (${CUST[k]})`).toBe(1);
      expect(rows[0][API], `batch: customer ${CUST[k]} carries ITS OWN lead's band, not a sibling's`).toBe(want[k]);
    }
    expect(accounts() - accBefore, 'batch: exactly three customers created').toBe(3);
    const got = { b1: accRows(CUST.b1)[0].Id, b2: accRows(CUST.b2)[0].Id, b3: accRows(CUST.b3)[0].Id };
    observed('batch', `3 conversions -> ${got.b1}=up_to_10, ${got.b2}=more_than_250, ${got.b3}=11_to_50 (each customer named by its own lead), Account delta ${accounts() - accBefore}`);
  });
});

// ── AC9: a value that is not one of the four ranges must be refused ───────
test.describe('[SCRUM-476] AC9 — a value outside the four ranges is refused', () => {
  test('typing a bogus range offers nothing and never reaches the field', async ({ page }) => {
    test.setTimeout(300000);
    const bogus = '26 to 50 employees';
    const before = accRows(CUST.hand)[0];
    expect(before[API], 'AC9 fixture customer starts at 11_to_50').toBe('11_to_50');

    await openCustomer(page, 'hand');
    const lb = await openBandPicker(page);
    const offered = await lb.locator('[role=option]').evaluateAll((es) => es.map((e) => e.getAttribute('data-value')));
    expect(offered, 'AC9: the picker offers exactly the blank slot plus the four ranges').toEqual(['', ...BANDS]);

    const combo = page.getByRole('combobox', { name: LABEL, exact: true });
    await expect(await combo.count(), 'the Company Size combobox is not on the page').toBe(1);
    await combo.first().fill(bogus);
    await combo.first().click({ timeout: 15000 });
    await page.waitForTimeout(2500);

    const offered2 = await lb.locator('[role=option]').evaluateAll((es) => es.map((e) => e.getAttribute('data-value')));
    const accepted = offered2.filter((v) => v && BANDS.indexOf(v) < 0);
    expect(accepted, `AC9: typing "${bogus}" offered no bogus option (accepted slots: ${JSON.stringify(accepted)})`).toEqual([]);

    await saveInlineEdit(page);
    await page.waitForTimeout(4000);

    const after = accRows(CUST.hand)[0];
    expect(after.Id, 'AC9: same customer record').toBe(before.Id);
    expect(after[API], 'AC9: the bogus value never reached Company_Size__c').toBe('11_to_50');

    await openCustomer(page, 'hand');
    expect(await renderedBand(page), 'AC9: after reload the page still renders the old range').toBe('11 to 50 employees');
    observed('AC9', `typed "${bogus}" into the picker -> offered options ${JSON.stringify(offered2)}; saved Company_Size__c stayed 11_to_50 on ${ids.c_hand}; page still renders "11 to 50 employees"`);
  });
});
