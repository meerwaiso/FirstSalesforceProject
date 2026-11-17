import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-461] „Verloren Chancen je Wettbewerber“ — UI-E2E against Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/setup.ts → storage-state.json), baseURL
 * from org.ts — never a hardcoded host, never networkidle on Lightning.
 *
 * LOCATORS PROBED against this org on 2026-11-17 (scripts/tmp-probe461*.js, results
 * in docs/SCRUM-461-notizen-tester.md) — not guessed:
 *   - New-Form /lightning/o/Opportunity/new: textbox "Opportunity Name",
 *     combobox "Stage", combobox "Verlustgrund", combobox "Lost to competitor"
 *     (the Lookup picker, an <input> that accepts fill()), combobox
 *     "Competitor price (approx.)", button "Save".
 *   - Picklist options live in a shadow root: `[role=option]` elements exist, but
 *     their accessible name is EMPTY for getByRole — only ariaSnapshot() sees it
 *     (same trap as SCRUM-417). Every option lookup below reads ariaSnapshot().
 *   - Refused save: dialog "We hit a snag." → "Review the following fields" →
 *     listitem naming the field (errorDisplayField of the validation rule).
 *   - /lightning/o/Competitor__c/new: textbox "Competitor Name" (the Name field).
 *   - Report view: iframe url contains "lightningReportApp"; rows are <tr> whose
 *     first cell is "<name>, unchecked, Select row for Drill Down.<name>".
 *     Numbers render in the user's locale: 490.000,00 € (dot = thousands).
 *
 * Test data is SEEDED here — Test-Org had 0 Competitor records and 0 Closed-Lost
 * deals with Loss_Reason__c = Wettbewerber, so AC2/AC5/AC7/AC8 matched nothing.
 * Seeding is idempotent (lookup by Name before create). Counts are asserted
 * against SOQL read back from the org, never against numbers kept in this file.
 */

const ORG = 'Test-Org';
const P = 'TEST-SCRUM-461-';
const COMPETITOR_NAMES = ['Nordwind Solutions', 'Alpha Ventures', 'Beta Build'];
const NOT_ON_LIST = 'Mueller';
const LOOKUP_COMBO = 'Lost to competitor';
const PICKER_HELPERS = ['Add New Competitor', 'Search Show more results'];

// ── sf CLI helpers (house pattern of SCRUM-381 / SCRUM-396) ───────────────

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 300)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function sfRun(args: string): any {
  return shellJson(
    execSync(`sf ${args} --target-org ${ORG} --json`, {
      encoding: 'utf-8',
      timeout: 180000,
      stdio: ['pipe', 'pipe', 'pipe'],
    }),
  );
}

function soql(query: string): any[] {
  const doc = sfRun(`data query -q "${query}"`);
  const result = doc?.result ?? doc;
  return result?.records ?? [];
}

function createRecord(sobject: string, values: string): string {
  const doc = sfRun(`data create record -s ${sobject} -v "${values}"`);
  const id = doc?.result?.id ?? doc?.id;
  if (!id) throw new Error(`Create ${sobject} lieferte keine Id`);
  return String(id);
}

function updateRecord(sobject: string, id: string, values: string): void {
  sfRun(`data update record -s ${sobject} -i ${id} -v "${values}"`);
}

function ensureCompetitor(name: string): string {
  const found = soql(`SELECT Id FROM Competitor__c WHERE Name = '${name}' LIMIT 1`);
  if (found.length > 0) return String(found[0].Id);
  return createRecord('Competitor__c', `Name='${name}'`);
}

function ensureLostDeal(tag: string, competitorId: string, amount: number, price: number | null, closeDate: string): string {
  const name = `${P}${tag}`;
  const found = soql(`SELECT Id FROM Opportunity WHERE Name = '${name}' LIMIT 1`);
  if (found.length > 0) return String(found[0].Id);
  const pricePart = price === null ? '' : ` Competitor_Price__c=${price}`;
  return createRecord(
    'Opportunity',
    `Name='${name}' StageName='Closed Lost' Loss_Reason__c=Wettbewerber ` +
      `Competitor_Lost_To__c=${competitorId} Amount=${amount} CloseDate=${closeDate}${pricePart}`,
  );
}

/**
 * AC8 needs a competitor-lost deal the report viewer does NOT own. OwnerId cannot
 * be set on create, so a sample Opportunity owned by another user of this org is
 * flipped and renamed to <P>FOREIGN (which makes the step idempotent). Checked
 * against every existing spec before choosing it: no suite asserts an org-wide
 * Closed Lost Opportunity count (SCRUM-449 filters IsClosed = false).
 */
function ensureForeignLostDeal(competitorId: string): void {
  const already = soql(`SELECT Id FROM Opportunity WHERE Name = '${P}FOREIGN' LIMIT 1`);
  if (already.length > 0) return;
  const mine = soql(`SELECT OwnerId FROM Opportunity WHERE Name = '${P}N1' LIMIT 1`);
  expect(mine.length, 'precondition: own fixture N1 exists before the foreign deal is picked').toBeGreaterThan(0);
  const sessionOwner = String(mine[0].OwnerId);
  const candidate = soql(
    `SELECT Id FROM Opportunity WHERE StageName = 'Closed Won' AND OwnerId != '${sessionOwner}' LIMIT 1`,
  );
  expect(candidate.length, 'precondition: a Closed Won deal owned by another user exists').toBeGreaterThan(0);
  updateRecord(
    'Opportunity',
    String(candidate[0].Id),
    `Name='${P}FOREIGN' StageName='Closed Lost' Loss_Reason__c=Wettbewerber ` +
      `Competitor_Lost_To__c=${competitorId} Amount=80000 Competitor_Price__c=60000 CloseDate=2026-06-01`,
  );
}

/** What the reports must show, computed from the org — not from this file. */
function expectedRows(ownOnly: boolean, sessionOwner: string): Record<string, { count: number; sum: number; avgGap: number | null }> {
  const deals = soql(
    `SELECT Id, Amount, Competitor_Price__c, Competitor_Gap__c, Lost_Last_12M__c, OwnerId, ` +
    `Competitor_Lost_To__c FROM Opportunity WHERE StageName = 'Closed Lost' AND Loss_Reason__c = 'Wettbewerber'`,
  );
  const names: Record<string, string> = {};
  for (const c of soql('SELECT Id, Name FROM Competitor__c')) names[String(c.Id)] = String(c.Name);

  const acc: Record<string, { count: number; sum: number; gaps: number[] }> = {};
  for (const d of deals) {
    if (d.Lost_Last_12M__c !== true) continue; // outside the rolling window
    if (!d.Competitor_Lost_To__c) continue; // no competitor -> no row
    if (ownOnly && String(d.OwnerId) !== sessionOwner) continue; // scope: user
    const name = names[String(d.Competitor_Lost_To__c)];
    if (!name) continue;
    const row: { count: number; sum: number; gaps: number[] } =
      acc[name] ?? { count: 0, sum: 0, gaps: [] as number[] };
    row.count += 1;
    row.sum += Number(d.Amount ?? 0);
    if (d.Competitor_Gap__c !== null && d.Competitor_Gap__c !== undefined) row.gaps.push(Number(d.Competitor_Gap__c));
    acc[name] = row;
  }
  const out: Record<string, { count: number; sum: number; avgGap: number | null }> = {};
  for (const key of Object.keys(acc)) {
    const a = acc[key];
    out[key] = {
      count: a.count,
      sum: a.sum,
      // PO decision: the average is over the deals where the price is KNOWN.
      avgGap: a.gaps.length === 0 ? null : a.gaps.reduce((x, y) => x + y, 0) / a.gaps.length,
    };
  }
  return out;
}

/** German and US number rendering both parse: 490.000,00 € / 490,000.00 / -20.000 */
function toNumbers(texts: string[]): number[] {
  const out: number[] = [];
  for (const t of texts) {
    for (const raw of t.match(/-?\d[\d.,]*/g) ?? []) {
      let s = raw;
      const lastComma = s.lastIndexOf(',');
      const lastDot = s.lastIndexOf('.');
      if (lastComma > lastDot) {
        s = s.replace(/\./g, '').replace(/,/g, '.'); // German: 1.234,56
      } else if (lastDot > lastComma) {
        if (/\.\d{3}(\D|$)/.test(s) && !/\.\d{1,2}(\D|$)/.test(s)) s = s.replace(/\./g, ''); // -20.000
        else s = s.replace(/,/g, ''); // US: 1,234.56
      }
      const n = Number(s);
      if (!Number.isNaN(n)) out.push(n);
    }
  }
  return out;
}

function hasNumber(list: number[], wanted: number): boolean {
  return list.some((n) => Math.abs(n - wanted) < 0.51);
}

// ── Lightning helpers (all probed, see header) ─────────────────────────────

async function dismissGuidance(page: Page) {
  const dlg = page.getByRole('dialog', { name: /Try the new Salesforce Setup/i });
  if ((await dlg.count()) > 0) {
    await dlg.getByRole('button').first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

/**
 * Open a picklist combobox and click one of its options. The option's accessible
 * name is only visible through ariaSnapshot (shadow root), so the element is
 * chosen by its snapshot text — and the helper THROWS when the option never
 * appears, it never silently skips a step.
 */
async function pickOption(page: Page, comboName: string, optionName: string) {
  const combo = page.getByRole('combobox', { name: comboName, exact: false }).first();
  await expect(await combo.count(), `combobox "${comboName}" is not on the page`).toBeGreaterThan(0);
  for (let attempt = 0; attempt < 6; attempt++) {
    const els = await page.locator('[role=option]').all();
    for (const el of els) {
      const snap = await el.ariaSnapshot().catch(() => '');
      if (snap.includes(`option "${optionName}"`)) {
        await el.click({ force: true });
        await page.waitForTimeout(700);
        return;
      }
    }
    await combo.click({ timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(900);
  }
  throw new Error(`Picker "${comboName}" never offered "${optionName}"`);
}

/** Names the Lookup picker currently offers (helper entries excluded). */
async function offeredLookups(page: Page): Promise<string[]> {
  const els = await page.locator('[role=option]').all();
  const names: string[] = [];
  for (const el of els) {
    const snap = await el.ariaSnapshot().catch(() => '');
    const m = snap.match(/option "([^"]+)"/);
    if (m && !PICKER_HELPERS.some((h) => m[1].startsWith(h))) names.push(m[1]);
  }
  return names;
}

async function fillLookup(page: Page, query: string) {
  const combo = page.getByRole('combobox', { name: LOOKUP_COMBO, exact: false }).first();
  await expect(await combo.count(), `the Lookup picker "${LOOKUP_COMBO}" is not on the form`).toBeGreaterThan(0);
  await combo.waitFor({ state: 'visible', timeout: 20000 });
  await combo.fill(query);
  await page.waitForTimeout(1500);
}

async function openNewOpportunityForm(page: Page) {
  await page.goto('/lightning/o/Opportunity/new', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
  await page.getByLabel('Opportunity Name', { exact: false }).first().waitFor({ state: 'visible', timeout: 30000 });
  await dismissGuidance(page);
}

async function openRecordDetails(page: Page, path: string) {
  await page.goto(path, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
  await dismissGuidance(page);
  const tab = page.getByRole('tab', { name: 'Details' }).first();
  await tab.waitFor({ state: 'visible', timeout: 30000 });
  if ((await tab.getAttribute('aria-selected')) !== 'true') await tab.click();
  await page.locator('div.slds-form-element').first().waitFor({ state: 'visible', timeout: 30000 });
}

async function reportFrame(page: Page, reportId: string): Promise<Frame> {
  await page.goto(`/lightning/r/Report/${reportId}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
  await dismissGuidance(page);
  const deadline = Date.now() + 90000;
  for (;;) {
    const f = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (f) {
      await f.locator('td').first().waitFor({ timeout: 60000 });
      return f;
    }
    if (Date.now() > deadline) throw new Error('report iframe never appeared');
    await page.waitForTimeout(1000);
  }
}

/** Group rows of a matrix report: first cell is "<name>, unchecked, …<name>". */
async function groupRows(frame: Frame, knownNames: string[]): Promise<Array<{ label: string; cells: string[] }>> {
  const trs = await frame.locator('tr').all();
  const rows: Array<{ label: string; cells: string[] }> = [];
  for (const tr of trs) {
    const cells = await tr.locator('td, th').allTextContents();
    if (cells.length === 0) continue;
    const label = cells[0].replace(/\s+/g, ' ').trim();
    const hit = knownNames.find((n) => label === `${n}, unchecked, Select row for Drill Down.${n}`);
    if (hit) rows.push({ label: hit, cells });
  }
  return rows;
}

function resolveReportId(name: string): string {
  const found = soql(`SELECT Id FROM Report WHERE Name = '${name}' LIMIT 1`);
  expect(found.length, `Report '${name}' is not deployed in Test-Org`).toBeGreaterThan(0);
  return String(found[0].Id);
}

function sessionOwner(): string {
  const mine = soql(`SELECT OwnerId FROM Opportunity WHERE Name = '${P}N1' LIMIT 1`);
  expect(mine.length, 'precondition: fixture N1 exists').toBeGreaterThan(0);
  return String(mine[0].OwnerId);
}

// ── The suite ──────────────────────────────────────────────────────────────

test.describe('[SCRUM-461] Verloren Chancen je Wettbewerber (UI)', () => {
  test.describe.configure({ timeout: 240000 });

  const competitorIds: Record<string, string> = {};
  const createdIds: string[] = [];

  test.beforeAll(() => {
    for (const name of COMPETITOR_NAMES) competitorIds[name] = ensureCompetitor(name);
    // Nordwind: two deals we were too expensive on, one where we were cheaper
    // (negative gap, still counted), one with no price at all (AC5/TAC1/TAC2).
    ensureLostDeal('N1', competitorIds['Nordwind Solutions'], 100000, 80000, '2026-05-05');
    ensureLostDeal('N2', competitorIds['Nordwind Solutions'], 120000, 90000, '2026-06-05');
    ensureLostDeal('N3', competitorIds['Nordwind Solutions'], 50000, 70000, '2026-07-05');
    ensureLostDeal('N4', competitorIds['Nordwind Solutions'], 60000, null, '2026-08-05');
    ensureLostDeal('A1', competitorIds['Alpha Ventures'], 90000, 85000, '2026-09-05');
    ensureLostDeal('A2', competitorIds['Alpha Ventures'], 40000, null, '2026-09-10');
    ensureLostDeal('B1', competitorIds['Beta Build'], 70000, 60000, '2026-10-05');
    // Outside the rolling twelve months — must not appear in either report.
    ensureLostDeal('OUT', competitorIds['Nordwind Solutions'], 99000, 50000, '2025-06-01');
    ensureForeignLostDeal(competitorIds['Nordwind Solutions']);
  });

  // ── AC3: the picker offers list entries only ─────────────────────────────
  test('AC3: the competitor picker offers exactly the list entries, free text is not offered', async ({ page }) => {
    await openNewOpportunityForm(page);
    await fillLookup(page, 'Nord');
    const offered = await offeredLookups(page);
    expect(offered.filter((o) => o === 'Nordwind Solutions').length,
      'AC3: the list entry "Nordwind Solutions" is not offered by the picker').toBeGreaterThan(0);

    await fillLookup(page, NOT_ON_LIST);
    const second = await offeredLookups(page);
    for (const near of [NOT_ON_LIST, 'Müller GmbH', 'Müller Group']) {
      expect(second.filter((o) => o === near).length,
        `AC3: "${near}" is not on the list and must not be offered`).toBe(0);
    }
    // Everything the picker offers has to be a real list entry.
    const list = soql('SELECT Name FROM Competitor__c').map((r) => String(r.Name));
    for (const o of second) {
      expect(list.includes(o), `AC3: the picker offers "${o}", which is not a list entry`).toBe(true);
    }
  });

  // ── AC2: a competitor loss without a competitor is refused ──────────────
  test('AC2: Closed Lost + Wettbewerber without a competitor is refused, the message names it', async ({ page }) => {
    await openNewOpportunityForm(page);
    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(`${P}AC2-UI`);
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await pickOption(page, 'Stage', 'Closed Lost');
    await pickOption(page, 'Verlustgrund', 'An einen Wettbewerber verloren');

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    await expect(page.url(), 'AC2: the save went through despite the missing competitor').toContain('Opportunity/new');
    const dialog = page.getByRole('dialog').first();
    await expect(dialog, 'AC2: the refusal shows no error dialog').toBeVisible({ timeout: 20000 });
    const aria = await dialog.ariaSnapshot();
    expect(aria, 'AC2: the error dialog does not name the competitor field').toContain('Lost to competitor');
    const created = soql(`SELECT Id FROM Opportunity WHERE Name = '${P}AC2-UI' LIMIT 1`);
    expect(created.length, 'AC2: a record was created despite the refusal').toBe(0);
  });

  // ── AC1: another loss reason stays free of a competitor ─────────────────
  test('AC1: Closed Lost with a non-competitor reason saves without a competitor', async ({ page }) => {
    await openNewOpportunityForm(page);
    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(`${P}AC1-UI`);
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await pickOption(page, 'Stage', 'Closed Lost');
    await pickOption(page, 'Verlustgrund', 'Kontakt abgebrochen');

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const created = soql(`SELECT Id, Loss_Reason__c, Competitor_Lost_To__c FROM Opportunity WHERE Name = '${P}AC1-UI' LIMIT 1`);
    expect(created.length, 'AC1: the deal did not save').toBeGreaterThan(0);
    expect(created[0].Competitor_Lost_To__c, 'AC1: a competitor was demanded').toBeNull();
    createdIds.push(String(created[0].Id));
  });

  // ── AC5 + AC9: a competitor without a price saves, counts, stays silent ──
  test('AC5+AC9: competitor without a price saves, gap stays blank, nothing automatic', async ({ page }) => {
    await openNewOpportunityForm(page);
    await page.getByLabel('Opportunity Name', { exact: false }).first().fill(`${P}AC5-UI`);
    await page.getByLabel('Close Date', { exact: false }).first().fill('01.08.2026');
    await pickOption(page, 'Stage', 'Closed Lost');
    await pickOption(page, 'Verlustgrund', 'An einen Wettbewerber verloren');
    await fillLookup(page, 'Alpha Ventures');

    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const created = soql(
      `SELECT Id, Amount, Competitor_Price__c, Competitor_Gap__c, Lost_Last_12M__c, ` +
      `Competitor_Lost_To__c FROM Opportunity WHERE Name = '${P}AC5-UI' LIMIT 1`,
    );
    expect(created.length, 'AC5: the deal did not save').toBeGreaterThan(0);
    const deal = created[0];
    expect(deal.Competitor_Price__c, 'AC5: no price was entered').toBeNull();
    expect(deal.Competitor_Gap__c, 'AC5/TAC1: the gap must be blank, not 0').toBeNull();
    expect(deal.Lost_Last_12M__c, 'AC5: the deal is inside the window and gets counted').toBe(true);
    expect(String(deal.Competitor_Lost_To__c), 'AC5: the competitor is on the deal').toBeTruthy();
    createdIds.push(String(deal.Id));

    const oppId = String(deal.Id);
    const feed = soql(`SELECT Id FROM FeedItem WHERE ParentId = '${oppId}'`).length;
    const tasks = soql(`SELECT Id FROM Task WHERE WhatId = '${oppId}'`).length;
    const emails = soql(`SELECT Id FROM EmailMessage WHERE ParentId = '${oppId}'`).length;
    expect(feed, 'AC9: the save posted to the record feed').toBe(0);
    expect(tasks, 'AC9: the save created a task on the record').toBe(0);
    expect(emails, 'AC9: the save sent an email logged on the record').toBe(0);
  });

  // ── AC4 (UI half): the session user holds the team-lead PS and may add ───
  test('AC4: a team lead adds a competitor and it is immediately selectable', async ({ page }) => {
    const freshName = `${P}ADDED ${Date.now()}`;
    await page.goto('/lightning/o/Competitor__c/new', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
    const nameField = page.getByLabel('Competitor Name', { exact: false }).first();
    await expect(nameField, 'the Competitor form has no Name field').toBeVisible({ timeout: 30000 });
    await dismissGuidance(page);
    await nameField.fill(freshName);
    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const created = soql(`SELECT Id, Name FROM Competitor__c WHERE Name = '${freshName}' LIMIT 1`);
    expect(created.length, 'AC4: the team lead did not end up with a new list entry').toBeGreaterThan(0);

    // Immediately selectable by everyone who can read the list.
    await openNewOpportunityForm(page);
    await fillLookup(page, freshName.slice(0, 30));
    const offered = await offeredLookups(page);
    expect(offered.filter((o) => o === freshName).length,
      'AC4: the entry just added is not selectable on the deal form').toBeGreaterThan(0);
  });

  // ── AC6: a deal that predates the feature stays usable ──────────────────
  test('AC6: a Closed Lost deal without a competitor opens, lists and saves unchanged', async ({ page }) => {
    const historical = soql(
      `SELECT Id, Name, Amount, Competitor_Lost_To__c FROM Opportunity ` +
      `WHERE StageName = 'Closed Lost' AND Loss_Reason__c != 'Wettbewerber' AND Competitor_Lost_To__c = null`,
    );
    expect(historical.length, 'AC6 precondition: no historical Closed Lost deal exists').toBeGreaterThan(0);
    const target = historical[0];
    const before = Number(target.Amount ?? 0);

    await openRecordDetails(page, `/lightning/r/Opportunity/${target.Id}/view`);
    const body = await page.locator('body').first().ariaSnapshot();
    expect(body.includes('We hit a snag'), 'AC6: opening the historical record demanded something').toBe(false);

    const edit = page.getByRole('button', { name: 'Edit Amount', exact: true }).first();
    await expect(edit, 'AC6: the record offers no way to edit it').toBeVisible({ timeout: 20000 });
    await edit.click();
    const input = page.getByLabel('Amount', { exact: true }).first();
    await expect(input, 'AC6: the Amount editor has no input').toBeVisible({ timeout: 20000 });
    await input.fill(String(before + 1));
    await page.getByRole('button', { name: 'Save', exact: true }).first().click({ timeout: 15000 });
    await page.waitForTimeout(4000);

    const after = soql(`SELECT Id, Amount, StageName FROM Opportunity WHERE Id = '${target.Id}' LIMIT 1`);
    expect(Number(after[0].Amount), `AC6: the save of ${target.Name} did not persist`).toBe(before + 1);
    expect(after[0].StageName, 'AC6: the stage survived the save').toBe('Closed Lost');
  });

  // ── AC7: the org-wide overview ───────────────────────────────────────────
  test('AC7: org overview shows per competitor count, total value and average gap, biggest first', async ({ page }) => {
    const owner = sessionOwner();
    const expected = expectedRows(false, owner);
    const names = Object.keys(expected);
    expect(names.length, 'AC7 precondition: no competitor has a lost deal in the window').toBeGreaterThan(0);

    const frame = await reportFrame(page, resolveReportId('Verloren_Chancen_je_Wettbewerber'));
    const rows = await groupRows(frame, COMPETITOR_NAMES);
    expect(rows.length, `AC7: the report shows ${rows.length} rows for ${names.length} competitors`).toBe(names.length);

    const seen: string[] = [];
    for (const r of rows) {
      const want = expected[r.label];
      const nums = toNumbers(r.cells);
      seen.push(r.label);
      expect(hasNumber(nums, want.count), `AC7: row "${r.label}" does not show its deal count ${want.count}`).toBe(true);
      expect(hasNumber(nums, want.sum), `AC7: row "${r.label}" does not show the total value ${want.sum}`).toBe(true);
      if (want.avgGap !== null) {
        expect(hasNumber(nums, want.avgGap),
          `AC7/AC5: row "${r.label}" shows no average over the deals with a known price (expected ${want.avgGap})`).toBe(true);
      }
    }
    const order = seen.map((n) => expected[n].count);
    for (let i = 1; i < order.length; i++) {
      expect(order[i] <= order[i - 1], `AC7: rows are not sorted by deal count at row ${i}`).toBe(true);
    }
    const top = names.slice().sort((a, b) => expected[b].count - expected[a].count || expected[b].sum - expected[a].sum)[0];
    expect(rows[0].label, `AC7: the competitor that took the most business (${top}) is not on top`).toBe(top);
  });

  // ── AC8: own deals for the account manager, all deals for the director ───
  test('AC8: the own-deals overview counts only the viewer’s deals, the org one counts all', async ({ page }) => {
    const owner = sessionOwner();
    const all = expectedRows(false, owner);
    const own = expectedRows(true, owner);
    const foreign = Object.keys(all).filter((n) => all[n].count > own[n].count);
    expect(foreign.length, 'AC8 precondition: no competitor has a deal owned by another user').toBeGreaterThan(0);

    const orgFrame = await reportFrame(page, resolveReportId('Verloren_Chancen_je_Wettbewerber'));
    const orgRows = await groupRows(orgFrame, COMPETITOR_NAMES);
    const myFrame = await reportFrame(page, resolveReportId('Verloren_Chancen_je_Wettbewerber_Meine'));
    const myRows = await groupRows(myFrame, COMPETITOR_NAMES);

    for (const name of foreign) {
      const orgRow = orgRows.find((r) => r.label === name);
      const myRow = myRows.find((r) => r.label === name);
      expect(orgRow, `AC8: ${name} missing from the org overview`).toBeTruthy();
      expect(myRow, `AC8: ${name} missing from the own overview`).toBeTruthy();
      expect(hasNumber(toNumbers(orgRow!.cells), all[name].count),
        `AC8: org row for ${name} does not show ${all[name].count}`).toBe(true);
      expect(hasNumber(toNumbers(myRow!.cells), own[name].count),
        `AC8: own row for ${name} does not show ${own[name].count}`).toBe(true);
      expect(all[name].count > own[name].count, `AC8: both reports show the same count for ${name}`).toBe(true);
    }
  });

  test.afterEach(() => {
    for (const id of createdIds.splice(0)) {
      try {
        sfRun(`data delete record -s Opportunity -i ${id}`);
      } catch {
        /* best effort — the fixtures are named TEST-SCRUM-461-* either way */
      }
    }
  });
});
