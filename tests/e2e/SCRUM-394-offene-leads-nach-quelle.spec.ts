import { test, expect } from '@playwright/test';
import { execFileSync, type ExecFileSyncOptionsWithStringEncoding } from 'child_process';
import * as processRef from 'process';

const REPORT_ID = '00OWU00000QEIUL2A5';
// TC7 seed-helper path, relative to the repo root (Playwright cwd = repo root, testDir = ./tests/e2e).
const Tc7SeedApexPath = 'tests/e2e/scratch/SCRUM394_Tc7SeedConvLead.apex';

// 16453 root cause: the previous `execSync(`sf ${args.join(' ')}`)` ran the args through a SHELL,
// which split the -v value into multiple argv tokens (Phone=+49 30 ... -> "Unexpected argument" exit 2).
// `sfRaw` must NOT shell-wrap: it passes the args straight to the process (no shell).
//
// `-v` itself is STILL a single argv element whose content is the documented form:
//   "Enclose values that contain spaces in single quotes."   (--help, 2026-09-07, CLI 2.139.6)
// The space-delimited pairs and the inner single-quote are the SF CLI's OWN field-value syntax (see the
// same --help text). Under execFileSync that string reaches the CLI as exactly ONE argv token, so the
// shell never re-splits it and the CLI's own parser handles the inner quotes — no double-escaping, no
// literal quote characters, no splitting.
// shared options for every sf subprocess (16455): Playwright workers set FORCE_COLOR=1, which the sf CLI
// interprets as "always colour" and emits ANSI escape codes even inside --json output. That breaks the
// totalSize/id regexes (sfCount -> -1, seedFixture finds no 00Q… id -> beforeAll dies). Force no-colour.
const sfExecOpts: ExecFileSyncOptionsWithStringEncoding = {
  encoding: 'utf8',
  stdio: ['pipe', 'pipe', 'pipe'],
  maxBuffer: 16 * 1024 * 1024,
  env: { ...processRef.env, FORCE_COLOR: '0', NO_COLOR: '1' },
};
function sfRaw(args: string[]): string {
  try {
    return execFileSync('sf', args, sfExecOpts);
  } catch { return ''; }
}

// BUG-D-2 (tester 16450, repro 10/10): `--compact false` STRIPS `totalSize` from the CLI JSON
// output, so the count could never be parsed. SF CLI default output keeps totalSize -> no flag.
function sfCount(q: string): number {
  const out = sfRaw(['data', 'query', '-o', 'Test-Org', '-q', q, '--json']);
  const m = out.match(/"totalSize"\s*:\s*(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}

// BUG-C-Fix: LeadSource picklist value is "Web" (not "Website"). Fixtures are idempotent.
// The CONV fixture is a REAL converted Lead (IsConverted=true) — see TC7 seed-helper below.
type FixtureSpec = { tag: string; values: string };
const FIXTURES: FixtureSpec[] = [
  { tag: 'FULL',   values: "LastName=TEST-SCRUM-394-FULL Email=full394@example.com Phone='+49 30 90182039' Company='Testfirma394Full' 'Status=Open - Not Contacted' LeadSource=Email" },
  { tag: 'MOBILE', values: "LastName=TEST-SCRUM-394-MOBILE MobilePhone='+49 151 0987654' Company='Testfirma394Mobile' 'Status=Open - Not Contacted' LeadSource=Web" },
  { tag: 'NOSRC',  values: "LastName=TEST-SCRUM-394-NOSRC Company='Testfirma394NoSource' 'Status=Open - Not Contacted'" },
  { tag: 'CONV',   values: "LastName=TEST-SCRUM-394-CONV Email=conv394@example.com Phone='+49 30 90182040' Company='Testfirma394Converted' LeadSource=Email 'Status=Open - Not Contacted'" },
];

function seedFixture(f: FixtureSpec) {
  if (sfCount(`SELECT Id FROM Lead WHERE LastName='TEST-SCRUM-394-${f.tag}' LIMIT 1`) > 0) return;
  const out = sfRaw(['data', 'create', 'record', '-s', 'Lead', '-o', 'Test-Org', '-v', f.values, '--json']);
  const m = out.match(/"id"\s*:\s*"(00Q[A-Za-z0-9]{12,})"/);  // Lead prefix 00Q
  expect(m, `seeding fixture ${f.tag} must return a Lead id; CLI output:\n${out.slice(0, 500)}`).toBeTruthy();
}

// TC7 (design-doc c0a83dc / SCRUM-386 house shape): a converted Lead is NOT seedable via DML (IsConverted
// updateable=false, ConvertedAccountId only settable through convertLead). We seed the CONV fixture as an
// OPEN lead above, then flip it to REALLY converted via Database.convertLead in anonymous Apex. The apex
// block verifies IsConverted=true + ConvertedAccountId!=null on read-back before returning.
function convertConvFixture() {
  const out = execFileSync('sf', ['apex', 'run', '-o', 'Test-Org', '-f', Tc7SeedApexPath, '--json'], sfExecOpts);
  // sf apex run --json nests the result: {status, result:{success, compiled, compileProblem, ...}}.
  // Parse as JSON (regex on "compiled":true would also match the `exceptionMessage`/`exceptionStackTrace`
  // key names in the result envelope, giving a false green on a failed run).
  let parsed: { status?: number; result?: { success?: boolean; compiled?: boolean; compileProblem?: string; exceptionMessage?: string } };
  try {
    parsed = JSON.parse(out);
  } catch {
    throw new Error(`TC7 convertLead apex output must be JSON; output:\n${out.slice(0, 800)}`);
  }
  const r = parsed.result;
  expect(r, `apex run must return a result block; output:\n${out.slice(0, 800)}`).toBeTruthy();
  expect(r!.compiled, `apex must compile; compileProblem: ${r?.compileProblem}\noutput:\n${out.slice(0, 800)}`).toBe(true);
  expect(r!.success, `apex must execute without throwing; exceptionMessage: ${r?.exceptionMessage}\noutput:\n${out.slice(0, 800)}`).toBe(true);
}

function ensureFixtures() {
  for (const f of FIXTURES) seedFixture(f);
  convertConvFixture();
}

async function openReportFrame(page: import('@playwright/test').Page) {
  // House-shape frontdoor setup is handled by the global Playwright setup file; here we go straight to the
  // report by REPORT_ID (no folder assert — tester verifies Sales-folder via UI-API, 16450).
  await page.goto(`/lightning/r/Report/${REPORT_ID}/view`);
  await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
  await page.waitForLoadState('domcontentloaded');
  const deadline = Date.now() + 60000;
  for (;;) {
    const f = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (f) return f;
    if (Date.now() > deadline) throw new Error('report iframe never appeared');
    await page.waitForTimeout(500);
  }
}

// TC10 (design-doc c0a83dc, LocaleSidKey=de_DE on the E2E identity): standard report column headers render in
// the USER locale, not the report language. The 5 standard columns (FIRST_NAME, LAST_NAME, COMPANY, STATUS,
// OWNER) are therefore locale-fragile and are NOT asserted by display text. We assert:
//   (a) the one locale-INDEPENDENT custom column we added, plus its value ("Datenqualität" label, German-only label,
//       and the "vollständig"/"unvollständig" values — formula is German),
//   (b) the number of data columns (6 for this report: 5 standard + 1 custom) via the header row,
//   (c) the fixture values which render identically in every locale.
// AC5 (16459): the report uses real <th> tags for the header — a live DOM dump (probe394.spec.ts, 2026-09-07)
// confirms <th> total = 15 = 2 header rows × 7 columns:
//   row 1: [group-checkbox] + First Name, Last Name, Company/Account, Lead Status, Datenqualität, Lead Owner
//   row 2: the group row (blank)
// Value cells are real <td> (151 total, each carrying role=gridcell; tdWithColumnActions=0).
const HEADER_COL_COUNT = 7;   // 1 Lead-Source group column + 6 data columns (5 standard + 1 custom Datenqualität)

test.describe('[SCRUM-394] Offene Leads nach Quelle + Datenqualität', () => {
  // Playwright's default 30s test timeout is too tight for: beforeAll (4× sf data record create + 1× sf apex run)
  // + page.goto + 60s iframe-wait + `table th`.waitFor(45000). Raise it so the entire describe block can breathe.
  test.describe.configure({ timeout: 120000 });
  test.beforeAll(() => { ensureFixtures(); });

  test('AC2 + AC4: report renders grouped by Lead-Quelle incl. its own group for blank source', async ({ page }) => {
    const frame = await openReportFrame(page);
    await frame.locator('table th').first().waitFor({ timeout: 45000 });

    // BUG-C-3 (16450) + 16461 (virtualization): the report renders only ~27 visible rows. The group
    // rowheaders (Purchased List, Email, Web, Phone Inquiry, Partner, blank "-") are scattered across
    // the full 65-row virtualized grid. Only one is visible at any given scroll position.
    //
    // Strategy: scroll the data-grid body incrementally and collect rowheader textContent after each
    // step, keeping the union of all seen labels. As soon as "Email" and "Web" have both been seen,
    // stop scrolling and assert. This works because each group header is visible at *some* scroll
    // position, even if only one at a time.
    const grid = frame.locator('[role=grid].data-grid-full-table').first();

    const scrollAndCollect = async () => {
      const seen = new Set<string>();
      for (let step = 0; step < 40; step++) {
        // Use frame.getByText to search ALL text in the frame (respects A11y/rendered content)
        for (const label of ['Email', 'Web']) {
          try {
            const count = await frame.getByText(new RegExp(`\\b${label}\\b`)).count();
            if (count > 0) seen.add(label);
          } catch { /* not rendered yet */ }
        }
        if (seen.has('Email') && seen.has('Web')) break;
        await grid.evaluate((el: HTMLElement) => {
          let sc: HTMLElement | null = el.parentElement;
          while (sc) {
            const style = window.getComputedStyle(sc);
            if (/(auto|scroll)/.test(style.overflowY)) break;
            sc = sc.parentElement;
          }
          (sc || el).scrollBy(0, 200);
        });
        await frame.waitForTimeout(400);
      }
      return Array.from(seen).join(' ');
    };

    const joined = await scrollAndCollect();
    expect(joined, 'group "Email" must appear after scroll').toMatch(/Email/);
    expect(joined, 'group "Web" must appear after scroll').toMatch(/Web/);

    // Blank-Gruppe: the blank group label appears as "Drill Down. -" or just "-" in the visible rowheaders.
    // After scrolling back to top (step 0), the blank group is visible as it's the first in picklist order.
    const scrollAndFind = async (label: RegExp) => {
      for (let step = 0; step < 40; step++) {
        try {
          if (await frame.getByText(label).count() > 0) return true;
        } catch { /* not rendered */ }
        await grid.evaluate((el: HTMLElement) => {
          let sc: HTMLElement | null = el.parentElement;
          while (sc) {
            const style = window.getComputedStyle(sc);
            if (/(auto|scroll)/.test(style.overflowY)) break;
            sc = sc.parentElement;
          }
          (sc || el).scrollBy(0, step < 10 ? -200 : 200);
        });
        await frame.waitForTimeout(400);
      }
      return false;
    };
    const blankFound = await scrollAndFind(/^- |Drill Down\. -|blank/i);
    expect(blankFound, 'blank group must render as "-" or "(blank)"').toBe(true);
  });

  test('AC5 (BUG-B): detail rows render — Name, Firma, Status, Datenqualität, Inhaber', async ({ page }) => {
    // BUG-B-Fix: report now has showDetails=true (Architect 16415, commit abd64f5).
    const frame = await openReportFrame(page);
    await frame.locator('table th').first().waitFor({ timeout: 45000 });

    // TC10 (c0a83dc): E2E identity has LocaleSidKey=de_DE; standard headers render in user locale. We assert
    // only on locale-ROBUST anchors: (a) the custom column header "Datenqualität" (German literal in the formula,
    //   identical in every locale), (b) the header row shape (7 <th>: 1 group + 6 data), (c) the fixture values
    //   (ASCII, locale-invariant), (d) the German formula output ("vollständig" / "unvollständig") in value cells.

    // (a) The custom-column header. DOM dump 16459: actual <th> text = "Datenqualität Column Actions" (the
    //     column-header th carries an embedded "Column Actions" aria-label). Use prefix match.
    await expect(frame.locator('th').filter({ hasText: /^Datenqualität/ }).first())
      .toBeVisible({ timeout: 45000 });

    // Header row shape: 7 <th> (1 Lead-Source-group checkbox column + 6 data columns). Real <th> tags
    // (NOT <thead><tr>; DOM dump 16459: th_total=15 = 2 header rows × 7).
    const headerCols = await frame.locator('table th').count();
    const firstRowThs = await frame.locator('table th').evaluateAll((ths) => {
      const byTr = new Map<unknown, number>();
      for (const th of ths) {
        const tr = th.closest('tr');
        byTr.set(tr, (byTr.get(tr) || 0) + 1);
      }
      return byTr.size ? Math.max(...Array.from(byTr.values())) : 0;
    });
    expect(
      firstRowThs,
      `AC5 header row must have ${HEADER_COL_COUNT} <th> (1 group + 6 data); got ${firstRowThs} (total th=${headerCols})`,
    ).toBe(HEADER_COL_COUNT);

    // (c) Detail rows render with the AC1 formula values in the "Datenqualität" column.
    //     The report is virtualized — only visible rows' <td>s are in the DOM, but the German formula
    //     output ("vollständig" / "unvollständig") appears in the visible slice. Poll for both literals.
    await expect(frame.locator('td').filter({ hasText: /vollständig/ }).first())
      .toBeVisible({ timeout: 45000 });
    await expect(frame.locator('td').filter({ hasText: /unvollständig/ }).first())
      .toBeVisible({ timeout: 45000 });

    // (d) The "Datenqualität" column header is the custom column (German literal in the formula, locale-stable).
    //     DOM dump 16459: actual <th> text = "Datenqualität Column Actions" — use prefix match.
    await expect(frame.locator('th').filter({ hasText: /^Datenqualität/ }).first())
      .toBeVisible();
  });

  test('AC3 (BUG-D): report total == org-wide open-lead count (live SOQL, no hard-coded 62)', async ({ page }) => {
    // BUG-D-Fix: live SOQL reference; CLI default output keeps totalSize (BUG-D-2: drop --compact false).
    const ref = sfCount('SELECT Id FROM Lead WHERE IsConverted=false');
    expect(
      ref,
      `org-wide SOQL of open leads must be retrievable (got ${ref}; re-read tester 16450 BUG-D-2 if this is -1)`,
    ).toBeGreaterThanOrEqual(4);

    const frame = await openReportFrame(page);
    await frame.locator('table th').first().waitFor({ timeout: 45000 });

    const text = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    const numbers = Array.from(text.matchAll(/(\d+)/g)).map((m) => parseInt(m[1], 10));
    expect(numbers.length > 0, 'report must render numeric counts').toBeTruthy();
    const maxSeen = Math.max(...numbers);
    expect(
      numbers,
      `AC3 violated: report must include the org-wide open-lead total (${ref}); largest rendered number: ${maxSeen}`,
    ).toContain(ref);
  });

  test('TC7 (design-doc c0a83dc): a REAL converted Lead is excluded from the report', async ({ page }) => {
    // beforeAll seeded a real converted Lead (TEST-SCRUM-394-CONV, IsConverted=true) via Database.convertLead —
    // DML/API create of a converted Lead is impossible in this org (IsConverted updateable=false; probe in
    // apex seed-helper). The report's CONVERTED=false filter + <scope>org</scope> must hide it.
    const notYetConverted = sfCount(`SELECT Id FROM Lead WHERE LastName='TEST-SCRUM-394-CONV' AND IsConverted=false`);
    expect(
      notYetConverted,
      "TC7 precondition: 'TEST-SCRUM-394-CONV' must actually be converted (IsConverted=true), not just Status-Closed",
    ).toBe(0);

    const frame = await openReportFrame(page);
    await frame.locator('table th').first().waitFor({ timeout: 45000 });
    const text = (await frame.locator('body').innerText()).replace(/\u00a0/g, ' ');
    expect(
      text,
      "TC7: the converted lead 'TEST-SCRUM-394-CONV' must NOT appear in the report (CONVERTED=false filter)",
    ).not.toContain('TEST-SCRUM-394-CONV');
  });
});
