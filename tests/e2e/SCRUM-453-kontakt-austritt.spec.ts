import { test, expect } from '@playwright/test';
import { type Page, type Frame } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { openRecordPage, openRecordDetails, expectFieldVisible } from './record-page';

/**
 * [SCRUM-453] E2E — Contact „has left the company“ (mark + date)
 *
 * AC-1 mark + date visible, record still there
 * AC-3 history (Cases / Opportunities) of a marked contact still reachable
 * AC-4 the mark stands out on the record page AND in the Contact list views
 * AC-5 mark visible where recipients are picked; consent fields untouched
 * AC-7 the Case shows the mark without opening the Contact
 * AC-8 overview „customer without a contact person“ — exactly the right rows
 * AC-9 nothing automatic (no FeedItem / Task side effect)
 *
 * AC-2 (date default + correction) and AC-6 (undo refused for non-team-leads)
 * are Apex-only here: the undo restriction is a transition rule the guard
 * trigger enforces on save, and the UI session of this org holds
 * SCRUM453_ContactLeft_Undo, so a UI-negative undo cannot be set up
 * (2/2 licences taken — see skill salesforce-playwright-session §4c).
 * Those two run in SCRUM453ContactLeftTest / SCRUM453ContactLeftFlsTest.
 *
 * Fixtures are the persistent ones the Developer seeded (docs/SCRUM-453-notizen-dev.md)
 * plus the e2e history this spec's sibling seeding created (Case + Opportunity
 * for B2, 5 open Cases for B1 so B1 lands in the Kritische_Kontakte list view).
 * Every fixture is resolved by NAME at runtime — a missing fixture fails loudly
 * instead of silently testing zero records (the PO's zero-row trap).
 */

const ORG = 'Test-Org';

// Lightning pages plus a SOQL round-trip per assertion need far more than the 30 s default.
test.setTimeout(120000);

function soql(query: string): any[] {
  const raw = execFileSync(
    'sf',
    ['data', 'query', '--target-org', ORG, '--json', '-q', query],
    { encoding: 'utf-8', env: { ...process.env, FORCE_COLOR: '0' } },
  );
  const parsed = JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
  return parsed.result.records;
}

/**
 * One accessibility snapshot of the whole page — the ONLY fast way to read
 * Lightning field values here.
 *
 * Measured 2026-10-22 on Contact 003WU00001rHOmrYAG: the field VALUES live in
 * closed shadow roots, so `page.evaluate` + `querySelectorAll` sees the labels
 * but returns an empty value for every field, and reading each of the 35
 * `div.slds-form-element` blocks with Playwright locators costs ~9 s per block
 * (5 minutes for one page — the test times out and looks like an org problem).
 * One `ariaSnapshot()` call reads the whole page in ~1 s.
 */
async function snapshot(page: Page): Promise<string> {
  return await page.locator('body').first().ariaSnapshot();
}

/** Value of a labelled field in the snapshot; a missing label is a hard failure. */
function snapValue(snap: string, label: string, what: string): string {
  const esc = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  for (const line of snap.split('\n')) {
    const m = new RegExp(`(?:text:|listitem:|heading[^:]*:)\\s+${esc}\\s+(.+)$`).exec(line.trim());
    if (!m) continue;
    let v = m[1].trim();
    // Lightning repeats the label after the value on some fields ("True Austritt").
    if (v.endsWith(' ' + label)) v = v.slice(0, v.length - label.length - 1).trim();
    return v;
  }
  throw new Error(`Label "${label}" absent from the page snapshot — "${what}" is not rendered here`);
}

/** Parse a Lightning date cell (locale DD.MM.YYYY on this org) to ISO YYYY-MM-DD. */
function parseUiDate(raw: string, what: string): string {
  const de = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(raw);
  if (de) return `${de[3]}-${de[2]}-${de[1]}`;
  const us = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(raw);
  if (us) return `${us[3]}-${us[1]}-${us[2]}`;
  throw new Error(`${what}: "${raw}" is not a rendered date — assertion would be vacuous`);
}

/** Resolve one fixture record by exact name; a missing fixture is a hard failure. */
function fixtureId(entity: string, name: string): string {
  const rows = soql(`SELECT Id FROM ${entity} WHERE Name = '${name}' LIMIT 1`);
  expect(rows.length, `Fixture "${name}" (${entity}) is not in Test-Org — the criterion would match zero records`).toBe(1);
  return rows[0].Id;
}

async function openReportFrame(page: Page): Promise<Frame> {
  let frame: Frame | undefined;
  const deadline = Date.now() + 60000;
  for (;;) {
    frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) break;
    if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) never attached');
    await page.waitForTimeout(500);
  }
  await frame.waitForLoadState('domcontentloaded').catch(() => {});
  await frame.locator('table td').first().waitFor({ timeout: 45000 });
  return frame!;
}

/* ===================== AC-1 / AC-5 — the marked Contact page ===================== */

test.describe('[SCRUM-453] Contact Austritt — mark, date, consent, history', () => {
  test('AC-1: marked contact shows mark + leaving date, record still exists', async ({ page }) => {
    const id = fixtureId('Contact', 'V453 Fixture B2');
    const org = soql(
      `SELECT Id, Has_Left_Company__c, Left_Company_Date__c FROM Contact WHERE Name = 'V453 Fixture B2'`
    )[0];
    expect(org.Has_Left_Company__c, 'Org: mark must be set').toBe(true);
    expect(org.Left_Company_Date__c, 'Org: leaving date must be 2026-10-01').toBe('2026-10-01');

    await openRecordDetails(page, `/lightning/r/Contact/${id}/view`);
    await expectFieldVisible(page, 'Austritt');
    await expectFieldVisible(page, 'Austritt am');
    await expectFieldVisible(page, 'Austritt-Anzeige');

    const snap = await snapshot(page);
    const status = snapValue(snap, 'Austritt-Anzeige', 'Contact_Status_Anzeige__c');
    expect(status, `Contact_Status_Anzeige__c renders "${status}" — must say no longer there`).toContain('not there any more');
    const date = snapValue(snap, 'Austritt am', 'Left_Company_Date__c');
    expect(parseUiDate(date, 'Austritt am'), `rendered "${date}" ≠ org 2026-10-01`).toBe(org.Left_Company_Date__c);
    expect(snapValue(snap, 'Austritt', 'Has_Left_Company__c'), `mark renders "${snapValue(snap, "Austritt", "x")}" ≠ org true`).toBe('True');
    test.info().annotations.push({ type: 'observed', description: `AC-1 B2: UI "${status}" / ${date}, org mark=true date=${org.Left_Company_Date__c}` });
  });

  test('AC-5: newsletter consent and consent date survive the mark', async ({ page }) => {
    const marked = soql(
      `SELECT Id, NewsletterConsent__c, ConsentDate__c FROM Contact WHERE Has_Left_Company__c = true`
    );
    expect(marked.length, 'zero marked contacts → criterion untested').toBeGreaterThanOrEqual(1);
    for (const m of marked) {
      expect(m.NewsletterConsent__c, `consent flag must stay true on ${m.Id}`).toBe(true);
      expect(m.ConsentDate__c, `consent date must stay 2026-06-30 on ${m.Id}`).toBe('2026-06-30');
    }

    const id = fixtureId('Contact', 'V453 Fixture B2');
    await openRecordDetails(page, `/lightning/r/Contact/${id}/view`);
    await expectFieldVisible(page, 'Newsletter-Einwilligung');
    await expectFieldVisible(page, 'Einwilligung am');
    const snap = await snapshot(page);
    const consent = snapValue(snap, 'Newsletter-Einwilligung', 'NewsletterConsent__c');
    expect(consent, `UI consent flag renders "${consent}" — must stay True after marking`).toBe('True');
    const consentDate = snapValue(snap, 'Einwilligung am', 'ConsentDate__c');
    expect(parseUiDate(consentDate, 'Einwilligung am'), 'consent date must be unchanged after marking').toBe('2026-06-30');
    test.info().annotations.push({ type: 'observed', description: `AC-5: ${marked.length} marked contacts keep consent=true @2026-06-30; UI consent date ${consentDate}` });
  });

  test('AC-3: cases and opportunities of a marked contact stay reachable', async ({ page }) => {
    const id = fixtureId('Contact', 'V453 Fixture B2');
    const cases = soql(`SELECT Id, Subject FROM Case WHERE ContactId = '${id}'`);
    const opps = soql(`SELECT Id, Opportunity.Name FROM OpportunityContactRole WHERE ContactId = '${id}'`);
    expect(cases.length, 'B2 needs at least one Case (fixture)').toBeGreaterThanOrEqual(1);
    expect(opps.length, 'B2 needs at least one Opportunity via OpportunityContactRole').toBeGreaterThanOrEqual(1);

    // The Contact record in this org has NO related lists: its Related tab renders
    // "No related lists to display" (measured 2026-10-22 via ariaSnapshot). Reachability
    // is therefore proven by opening the linked records themselves — a related list
    // would be a layout change for the Developer, not something to test around.
    await openRecordPage(page, `/lightning/r/Contact/${id}/view`);
    const contactSnap = await snapshot(page);
    expect(contactSnap, 'marked contact must still open as a record after marking').toContain('V453 Fixture B2');
    test.info().annotations.push({
      type: 'observed',
      description: `AC-3 Related tab of the marked contact: ${contactSnap.includes('No related lists to display') ? 'renders "No related lists to display" — no Contact related list is deployed in Test-Org' : 'related lists present'}`,
    });

    // Details tab, not the raw page: the record body renders AFTER the global
    // header, and a snapshot taken too early sees only the navigation bar
    // (measured 2026-10-22: the Case snapshot held no record content at all).
    await openRecordDetails(page, `/lightning/r/Case/${cases[0].Id}/view`);
    const caseSnap = await snapshot(page);
    expect(caseSnap, `Case "${cases[0].Subject}" must still be openable after the contact was marked`).toContain(cases[0].Subject);
    expect(caseSnap, `Case page must still name its contact "V453 Fixture B2" (link survived the mark)`).toContain('V453 Fixture B2');

    await openRecordDetails(page, `/lightning/r/Opportunity/${opps[0].Id}/view`);
    const oppSnap = await snapshot(page);
    const oppName = (opps[0].Opportunity?.Name ?? 'SCRUM-453-e2e-Opp-B2') as string;
    expect(oppSnap, `Opportunity "${oppName}" must still be openable after the contact was marked`).toContain(oppName);
    test.info().annotations.push({ type: 'observed', description: `AC-3 B2: ${cases.length} Case + ${opps.length} Opportunity records still open, Case page names the marked contact` });
  });
});

/* ============================ AC-4 — list views ============================== */

test.describe('[SCRUM-453] Austritt-Anzeige in every Contact list', () => {
  const views = ['Kritische_Kontakte', 'Letzter_Real_Kontakt', 'Letztes_Anliegen'];

  for (const devName of views) {
    test(`AC-4: list view ${devName} carries the Austritt-Anzeige column`, async ({ page }) => {
      // Verified path (house SCRUM-370): filterName is the DEVELOPER NAME of the list view.
      await page.goto(`/lightning/o/Contact/list?filterName=${devName}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
      await page.getByText('Austritt-Anzeige', { exact: true }).first()
        .waitFor({ state: 'visible', timeout: 30000 });

      // Scope proof from the header row's own selection count (a list view renders only 14 rows).
      // Measured: the header row (data-row-key-value="HEADER") reads "… Select N items Sort by: …".
      const headerRow = await page.locator('tr[data-row-key-value="HEADER"]').first().innerText().catch(() => '');
      const stated = Number((headerRow.match(/Select (\d+) items/) ?? [, '0'])[1]);
      const orgCount = devName === 'Kritische_Kontakte'
        ? soql(`SELECT Id FROM Contact WHERE Open_Cases_Rating__c = 'Kritisch'`).length
        : soql(`SELECT Id FROM Contact`).length;
      // The header row caps the selection count at 50 ("Select 50 items" for 653
      // records, measured 2026-10-22). A user-scoped view would show a small exact
      // number, so reaching the cap still proves the org-wide scope.
      if (orgCount > 50) {
        expect(stated, `${devName}: header offers only ${stated} of ${orgCount} org records — view is not org-wide`).toBe(50);
      } else {
        expect(stated, `${devName}: header offers ${stated} ≠ org scope ${orgCount} records`).toBe(orgCount);
      }

      if (devName === 'Kritische_Kontakte') {
        // B1 is marked AND Kritisch → its row must carry the mark, not just the column.
        const b1 = fixtureId('Contact', 'V453 Fixture B1');
        const rows = page.locator('tr[data-row-key-value]');
        const n = await rows.count();
        const texts: Record<string, string> = {};
        for (let i = 0; i < n; i++) {
          const key = (await rows.nth(i).getAttribute('data-row-key-value').catch(() => '')) ?? '';
          if (!key || key === 'HEADER') continue;
          // The td/th cells of a row hold only the row actions; the visible values are in innerText.
          texts[key] = (await rows.nth(i).innerText().catch(() => '')).replace(/\s+/g, ' ').trim();
        }
        expect(Object.keys(texts), `${devName}: B1 not in the rendered rows (${Object.keys(texts).join(', ')})`).toContain(b1);
        const row = texts[b1];
        expect(row, `B1 row in ${devName}: ${row}`).toContain('not there any more');
        expect(row, `B1 row in ${devName}: ${row}`).toContain('Kritisch');
        test.info().annotations.push({ type: 'observed', description: `AC-4 ${devName}: ${stated} items, B1 row "${row}"` });
      } else {
        test.info().annotations.push({ type: 'observed', description: `AC-4 ${devName}: column visible, ${stated} items` });
      }
    });
  }
});

/* ============================== AC-7 — the Case ============================== */

test.describe('[SCRUM-453] Case shows the mark without opening the Contact', () => {
  test('AC-7: Case of a marked contact carries the indicator on its own page', async ({ page }) => {
    const contactId = fixtureId('Contact', 'V453 Fixture B2');
    const caseRows = soql(`SELECT Id, Subject, Contact_Left_Anzeige__c FROM Case WHERE ContactId = '${contactId}'`);
    expect(caseRows.length, 'no Case linked to a marked contact → AC-7 untested').toBeGreaterThanOrEqual(1);
    expect(caseRows[0].Contact_Left_Anzeige__c, 'Case formula field must be populated').toContain('not there any more');

    await openRecordDetails(page, `/lightning/r/Case/${caseRows[0].Id}/view`);
    await expectFieldVisible(page, 'Contact person left');
    const ui = snapValue(await snapshot(page), 'Contact person left', 'Contact_Left_Anzeige__c');
    expect(ui, `Case indicator renders "${ui}"`).toContain('not there any more');
    expect(ui, `Case indicator must carry the leaving date`).toContain('2026');
    test.info().annotations.push({ type: 'observed', description: `AC-7 ${caseRows[0].Subject}: UI "${ui}", org "${caseRows[0].Contact_Left_Anzeige__c}"` });
  });
});

/* ========================= AC-8 — the Account overview ======================= */

test.describe('[SCRUM-453] Overview: customer without a contact person', () => {
  test('AC-8: exactly the customers whose every contact has left, oldest first', async ({ page }) => {
    const reportRows = soql(`SELECT Id FROM Report WHERE Name = 'Kunde_ohne_Kontaktperson'`);
    expect(reportRows.length, 'Report Kunde_ohne_Kontaktperson not deployed in Test-Org').toBe(1);

    // Ground truth from the org — the report must reproduce this set exactly.
    const truth = soql(
      `SELECT Id, Name, OwnerId, Contacts_Without_Mark__c, Contacts_Left_Count__c, Last_Contact_Left_Date__c ` +
      `FROM Account WHERE Contacts_Without_Mark__c = 0 AND Contacts_Left_Count__c > 0`
    );
    expect(truth.length, 'zero matching Accounts → AC-8 would be untested, not passed').toBeGreaterThanOrEqual(1);
    const beta = truth.find((r) => r.Name === 'V453 Fixture Beta');
    expect(beta, 'fixture Beta must be in the result set').toBeTruthy();
    expect(truth.length, 'fixture Alpha (one unmarked contact) must NOT be listed').toBe(1);

    await openRecordPage(page, `/lightning/r/Report/${reportRows[0].Id}/view`);
    const frame = await openReportFrame(page);

    const rows = frame.locator('table tbody tr');
    const n = await rows.count();
    const all: string[][] = [];
    for (let i = 0; i < n; i++) {
      const cells = await rows.nth(i).locator('td,th').allTextContents().catch(() => []);
      all.push(cells.map((c) => c.trim()));
    }
    // Measured 2026-10-22 via the [PROBE] dump: the header row lives in the SAME
    // tbody, group rows carry "Name, unchecked, …", and the report's own count
    // renders as "Total (1)" / "Total Records 1" — never as a numeric cell.
    const isHeader = (r: string[]) => r.some((c) => c.includes('Column Actions'));
    const isSummary = (r: string[]) => r[0].startsWith('Subtotal') || r[0].startsWith('Total');
    const groupRows = all.filter((r) => r[0] && !isHeader(r) && !isSummary(r));
    const flat = all.map((r) => r.join(' | '));

    expect(groupRows.length, `report lists ${groupRows.length} customers ≠ org ${truth.length}`).toBe(truth.length);
    const names = groupRows.map((r) => r[0].split(',')[0]);
    expect(names).toContain('V453 Fixture Beta');
    expect(names.some((x) => x.includes('V453 Fixture Alpha')), 'Alpha (one unmarked contact) must NOT be listed').toBe(false);

    const bodyText = (await frame.locator('body').innerText().catch(() => '')).replace(/\s+/g, ' ');
    const totalMatch = /Total Records\s+(\d+)/.exec(bodyText);
    expect(totalMatch, 'report renders no "Total Records N" — count not readable').toBeTruthy();
    expect(Number(totalMatch![1]), `report Total Records ${totalMatch![1]} ≠ org ${truth.length}`).toBe(truth.length);

    const betaRow = groupRows.find((r) => r[0].includes('V453 Fixture Beta'))!;
    expect(betaRow[1].length, 'Beta row must name the account owner').toBeGreaterThan(0);
    expect(parseUiDate(betaRow[2], 'Beta last-leaving date'), `rendered "${betaRow[2]}" ≠ org ${beta!.Last_Contact_Left_Date__c}`).toBe(beta!.Last_Contact_Left_Date__c);
    test.info().annotations.push({ type: 'observed', description: `AC-8: org ${truth.length} Account, report Total Records ${totalMatch![1]}, ${groupRows.length} group rows, Beta row "${betaRow.join(' | ')}"` });
  });
});

/* ============================ AC-9 — nothing automatic ======================= */

test.describe('[SCRUM-453] Marking sends nothing and creates nothing', () => {
  test('AC-9: no FeedItem, no Task for a marked contact', async () => {
    const marked = soql(`SELECT Id FROM Contact WHERE Has_Left_Company__c = true`);
    expect(marked.length).toBeGreaterThanOrEqual(1);
    const ids = marked.map((m) => `'${m.Id}'`).join(',');
    // FeedItem.ParentId is the record the post is attached to (measured: 500… Case ids).
    // RelatedRecordId exists on FeedItem but cannot be filtered in a query call.
    const feeds = soql(`SELECT Id, ParentId FROM FeedItem WHERE ParentId IN (${ids})`);
    expect(feeds.length, `AC-9: ${feeds.length} FeedItem attached to marked contacts — marking must post nothing`).toBe(0);
    const tasks = soql(`SELECT Id, WhoId FROM Task WHERE WhoId IN (${ids})`);
    expect(tasks.length, `AC-9: ${tasks.length} Task assigned to marked contacts`).toBe(0);
    test.info().annotations.push({ type: 'observed', description: `AC-9: ${marked.length} marked contacts, 0 FeedItem, 0 Task` });
  });
});
