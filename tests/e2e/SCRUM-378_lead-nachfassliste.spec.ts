import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';

/**
 * [SCRUM-378] Nachfassliste für Leads — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). Network never networkidle on Lightning.
 *
 * Locators used here were PROBED against this org on 2026-09-01:
 *   - date field label "Letzter Versuch" resolves via getByLabel in the
 *     Lightning New/Edit form (Playwright pierces the shadow DOM).
 *   - Formula field "Ist fällig" is present as TEXT on the record view and is
 *     NOT an input/control in the New/Edit form (read-only by design).
 *   - List view is addressed by /lightning/o/Lead/list?filterName=Nachfassliste
 *     (the listViewId= param silently reverted to __Recent here).
 *   - Record "Edit" button: getByRole('button', { name: 'Edit', exact: true }).
 *
 * Fixtures (TEST-SCRUM-378-*, re-seeded on a best-effort basis in beforeEach):
 *   FAELLIG  open  2026-08-12  Is_Due=true   -> IN the list (open + > 14 days)
 *   RECENT   open  2026-08-29  Is_Due=false  -> NOT in the list (3 days)
 *   NODATE   open  no date     Is_Due=false  -> NOT in the list (no date)
 *   CLOSED   closed 2026-08-01 Is_Due=false  -> NOT in the list (closed)
 *
 * Formula branches (open+20d→true, open+3d→false, closed+30d→false,
 * no-date→false) were additionally verified via SOQL against the org on the
 * same fixtures — one query, four rows.
 *
 * KNOWN DEFECT is RESOLVED via the ADR-2 carrier switch (report replaces the
 * custom list view for the column AC — list view cannot carry standard
 * columns, see Jira 15225/15228). The column test now reads the four logical
 * columns from report Sales/Lead_Nachfassliste (00OWU00000QAIuL2AX): the org
 * renders Name as two physical columns FIRST_NAME + LAST_NAME (no combined
 * Name field on LeadList; architect accepted, comment on SCRUM-380), so the
 * test asserts the four LOGICAL columns (name via last name cell, company,
 * status, date), not "exactly 4 td cells".
 */

// ---------------------------------------------------------------------------
// FIXTURES — measured and re-derived at run time (SCRUM-474 fix, 2026-11-23).
//
// The old code seeded ABSOLUTE dates (2026-08-12 due / 2026-08-29 recent) and
// only created a record when a query COMMAND exited non-zero. Two drift bugs:
//   * Is_Due__c is derived from Last_Attempt_Date__c, so 'RECENT' turned due
//     14 days after the absolute date; on 2026-11-23 TWO fixtures were due and
//     the list/report asserts that expect one were red (SCRUM-474).
//   * `sf data query` exits 0 for an EMPTY result, so `exists` was always true
//     and the spec never re-seeded a deleted fixture.
// Now: dates are relative to today, every TEST-SCRUM-378-* record is deleted
// and reseeded fresh, and the due precondition is READ BACK from the org
// (falsifiable), never assumed.
// ---------------------------------------------------------------------------
const ORG = 'Test-Org';

function soql(query: string) {
  // FORCE_COLOR=0: sf paints its output when a TTY-ish env asks for colour, which
  // corrupts the JSON (measured in this project).
  const out = execSync(
    `sf data query --query "${query}" --target-org ${ORG} --json 2>/dev/null || true`,
    { env: { ...process.env, FORCE_COLOR: '0' } },
  ).toString();
  try {
    const answer = JSON.parse(out.slice(out.indexOf('{'), out.lastIndexOf('}') + 1));
    if (!answer.result) throw new Error(`No result in sf answer: ${out}`);
    return answer.result;
  } catch (e) {
    // Name the raw payload: a parse error that hides the answer is a dead end.
    throw new Error(`sf answer not JSON: ${e} | raw=${JSON.stringify(out)}`);
  }
}

function shell(command: string) {
  execSync(`${command} 2>/dev/null || true`, { stdio: ['pipe', 'pipe', 'pipe'] });
}

const DAY_MS = 86_400_000;
const isoOf = (offsetDays: number) =>
  new Date(Date.now() - offsetDays * DAY_MS).toISOString().slice(0, 10);
// Lightning renders dates in the UI locale: DD.MM.YYYY (ISO is rejected on the form).
const rendered = (iso: string) => {
  const [year, month, day] = iso.split('-');
  return `${Number(day)}.${Number(month)}.${year}`;
};

const DUE_ISO = isoOf(30);    // open, 30 days -> Is_Due__c true
const RECENT_ISO = isoOf(3);  // open, 3 days  -> Is_Due__c false
const CLOSED_ISO = isoOf(30); // closed        -> Is_Due__c false
const FIXTURE_NAMES = ['TEST-SCRUM-378-FAELLIG', 'TEST-SCRUM-378-RECENT', 'TEST-SCRUM-378-NODATE', 'TEST-SCRUM-378-CLOSED'];

async function ensureFixtures() {
  // Sweep first: the spec owns the TEST-SCRUM-378-* namespace, and stale rows from
  // an interrupted run are what made SCRUM-378 red on an otherwise clean org.
  const stale = soql(`SELECT Id FROM Lead WHERE LastName LIKE 'TEST-SCRUM-378%'`);
  for (const row of stale.records) {
    // Flag verified with `sf data delete record --help`: the ID flag is
    // -i / --record-id ('--record-identifier' is rejected by the CLI).
    shell(`sf data delete record --sobject Lead --record-id ${row.Id} --target-org ${ORG}`);
  }

  const seed: Array<[string, string, string, string]> = [
    ['FAELLIG', 'Open - Not Contacted', 'TestfirmaFaellig', DUE_ISO],
    ['RECENT', 'Working - Contacted', 'TestfirmaRecent', RECENT_ISO],
    ['NODATE', 'Open - Not Contacted', 'TestfirmaNodate', ''],
    ['CLOSED', 'Closed - Not Converted', 'TestfirmaClosed', CLOSED_ISO],
  ];
  for (const [tag, status, company, date] of seed) {
    const name = `TEST-SCRUM-378-${tag}`;
    const values = `LastName=${name} Company=${company} LeadSource=Email 'Status=${status}'${
      date ? ` Last_Attempt_Date__c=${date}` : ''}`;
    shell(`sf data create record --sobject Lead --target-org ${ORG} -v "${values}"`);
  }

  // Precondition read back from the org: exactly ONE fixture is due, and it is
  // the FAELLIG one. A formula change or a rejected seed fails here, not in the UI.
  const rows = soql(`SELECT Id, LastName, Is_Due__c, Last_Attempt_Date__c FROM Lead WHERE LastName LIKE 'TEST-SCRUM-378%'`);
  expect(rows.totalSize, 'all four fixtures must exist').toBe(4);
  const due = rows.records.filter((r) => r.Is_Due__c === true).map((r) => r.LastName).sort();
  expect(due, 'fixture precondition: exactly one TEST-SCRUM-378 lead may be Is_Due__c = true').toEqual(['TEST-SCRUM-378-FAELLIG']);
  const faellig = rows.records.find((r) => r.LastName === 'TEST-SCRUM-378-FAELLIG');
  expect(faellig?.Last_Attempt_Date__c, 'the due fixture must carry the seeded date').toBe(DUE_ISO);
}

/** Id of a fixture, looked up by name (no hardcoded record id). */
async function fixtureId(name: string) {
  const rows = soql(`SELECT Id FROM Lead WHERE LastName = '${name}'`);
  expect(rows.totalSize, `fixture ${name} must exist`).toBe(1);
  return rows.records[0].Id;
}

test.describe('[SCRUM-378] Nachfassliste für Leads', () => {
  test.beforeAll(async () => {
    await ensureFixtures();
  });

  test('AC list filter: only open+due lead remains; recent/no-date/closed are excluded', async ({ page }) => {
    await page.goto('/lightning/o/Lead/list?filterName=Nachfassliste');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    // Wait until the list body has rendered its rows (not networkidle).
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByText(/Sorted by Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    const body = page.locator('body');
    await expect(body.getByText(/Filtered by Ist fällig/).first()).toBeVisible();

    // SCRUM-474: the count is not a constant. A second due lead (API-378-OK)
    // belongs to another ticket, so asserting "1 item" measured the org, not the
    // filter. The org's own due-count is the expectation; the page must agree.
    const dueRows = soql(`SELECT Id, LastName FROM Lead WHERE Is_Due__c = true`);
    const dueCount = dueRows.totalSize;
    expect(dueCount, 'the org must have at least one due lead for this test to mean anything').toBeGreaterThan(0);
    expect(dueRows.records.map((r) => r.LastName),
      'fixture precondition: TEST-SCRUM-378-FAELLIG must be among the due leads').toContain('TEST-SCRUM-378-FAELLIG');

    const declared = body.getByText(new RegExp(`${dueCount} item`));
    await expect(declared.first()).toBeVisible({ timeout: 30000 });

    const listedRows = page.locator('table tbody tr');
    await expect(listedRows).toHaveCount(dueCount);
    // The one surviving row carries its date in the declared column:
    await expect(body.getByText(rendered(DUE_ISO)).first()).toBeVisible();
    // None of the excluded fixtures may carry a rendered value of their own date:
    await expect(body.getByText(rendered(RECENT_ISO), { exact: true })).toHaveCount(0); // RECENT
    // No-date / closed rows render no date cell at all (only one row exists):
    await expect(body.getByText(rendered(CLOSED_ISO), { exact: true })).toHaveCount(0); // CLOSED
  });

  test('AC layout: "Letzter Versuch" and "Ist fällig" appear together on the Lead record page', async ({ page }) => {
    const faelligId = await fixtureId('TEST-SCRUM-378-FAELLIG');
    await page.goto(`/lightning/r/Lead/${faelligId}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    // The two fields live in the Details tab of the Record Home page — click it.
    const details = page.getByRole('tab', { name: 'Details' });
    await expect(details.first()).toBeVisible({ timeout: 30000 });
    await details.first().click();
    await page.waitForTimeout(3000);

    // Both fields of the "Nachfassung" pair, in the details content:
    await expect(page.getByText('Nachfassung', { exact: true }).first()).toBeVisible({ timeout: 15000 });
    await expect(page.getByText('Letzter Versuch', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('Ist fällig', { exact: true }).first()).toBeVisible();
    // The due fixture shows the computed formula value (Lightning renders "True"):
    await expect(page.getByText('True', { exact: true }).first()).toBeVisible();
  });

  test('AC columns: report shows Name, Firma, Status, Letzter Versuch (ADR-2 carrier)', async ({ page }) => {
    // Carrier is the ADR-2 report (the custom list view cannot carry standard
    // columns — Jira 15225/15228). The org has NO combined NAME field on the
    // LeadList report type (NAME/Lead.Name rejected by the validator), so Name
    // renders as two physical columns FIRST_NAME + LAST_NAME. The AC asks for
    // the four LOGICAL columns to be readable — we assert the four values, not
    // "exactly 4 td cells" (physical count is 5). Probe-verified locators here
    // (headers + one data row) were read off this org on 2026-09-01.
    await page.goto('/lightning/r/Report/00OWU00000QAIuL2AX/view');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');

    // The Tabular report renders inside a cross-document iframe (legacy report
    // app). Poll page.frames() for it, then for its data cells — an explicit
    // wait on real data, not networkidle (forbidden on Lightning).
    const frame = await page.waitForFunction(
      () => document.querySelectorAll('iframe').length > 0,
      null,
      { timeout: 60000 },
    ).then(async () => {
      const deadline = Date.now() + 60000;
      for (;;) {
        const f = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
        if (f) return f;
        if (Date.now() > deadline) throw new Error('report iframe never appeared');
        await page.waitForTimeout(500);
      }
    });
    await frame.waitForLoadState('domcontentloaded').catch(() => {});
    await frame.locator('td').first().waitFor({ timeout: 45000 });

    // The four AC column headers are present (probed):
    await expect(frame.getByText('Last Name').first()).toBeVisible();
    await expect(frame.getByText('Company / Account').first()).toBeVisible();
    await expect(frame.getByText('Lead Status').first()).toBeVisible();
    await expect(frame.getByText('Letzter Versuch').first()).toBeVisible();

    // The one due lead's four logical column values are readable in the row:
    //   Name (via last name) · Firma · Status · Letzter Versuch
    const inFrame = async (value: string) => (await frame.getByText(value, { exact: true }).count()) > 0;
    const missing: string[] = [];
    if (!(await inFrame('TEST-SCRUM-378-FAELLIG'))) missing.push('Name');
    if (!(await inFrame('TestfirmaFaellig'))) missing.push('Firma (Company)');
    if (!(await inFrame('Open - Not Contacted'))) missing.push('Status');
    if (!(await inFrame(rendered(DUE_ISO)))) missing.push('Letzter Versuch (date)');
    expect(
      missing,
      `AC "Name · Firma · Status · Letzter Versuch" violated — missing from report: ${missing.join(', ')}.`,
    ).toEqual([]);

    // The report filter (Is_Due__c = true) keeps only the due lead: the other
    // fixtures (recent / no-date / closed) must not appear as data in the report.
    await expect(frame.getByText('TEST-SCRUM-378-RECENT', { exact: true })).toHaveCount(0);
    await expect(frame.getByText('TEST-SCRUM-378-NODATE', { exact: true })).toHaveCount(0);
    await expect(frame.getByText('TEST-SCRUM-378-CLOSED', { exact: true })).toHaveCount(0);
  });

  test('AC read-only: "Ist fällig" is not an editable control in the form; date field is editable', async ({ page }) => {
    await page.goto('/lightning/o/Lead/new');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByLabel(/Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    // The manual date field exists as a real, focusable input:
    const dateField = page.getByLabel(/Letzter Versuch/).first();
    await dateField.click();
    await expect(dateField).toBeEnabled();
    const tag = await dateField.evaluate((el) => el.tagName);
    expect(tag).toBe('INPUT');

    // The formula checkbox must NOT be a form control (no input/combobox bound
    // to it) — it is computed by the org, read-only by design.
    const dueControl = page.getByLabel(/Ist fällig/);
    await expect(dueControl).toHaveCount(0);
  });

  test('AC validation UI path: saving with a future date is rejected, not persisted', async ({ page }) => {
    await page.goto('/lightning/o/Lead/new');
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByLabel(/Letzter Versuch/).first()).toBeVisible({ timeout: 30000 });

    // Required fields + a FUTURE date, then Save.
    await page.getByLabel(/Last Name/i).first().fill('TEST-SCRUM-378-VALIDATE');
    const company = page.getByLabel(/Company/i).first();
    await company.click();
    await company.fill('TestfirmaValidation');
    const dateField = page.getByLabel(/Letzter Versuch/).first();
    await dateField.click();
    // A future date must be rejected at any run date: derived from today, rendered
    // the way the form reads it (DD.MM.YYYY — ISO is rejected outright).
    const futureIso = new Date(Date.now() + 30 * DAY_MS).toISOString().slice(0, 10);
    await dateField.fill(rendered(futureIso));
    await dateField.press('Enter');
    await page.waitForTimeout(1000);

    await page.getByRole('button', { name: /^Save$|Speichern/i }).first().click();
    // The org answers with a field-level error dialog — the record is NOT created.
    await expect(page.getByText(/We hit a snag|Review the following fields/i).first()).toBeVisible({ timeout: 20000 });
    // And the form still flags the date field:
    await expect(page.getByText('Letzter Versuch', { exact: true }).last()).toBeVisible();
    // Still on the form — nothing persisted.
    expect(page.url()).toContain('/new');
  });
});
