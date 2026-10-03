/**
 * [SCRUM-437] Problemserie auf Case — Playwright E2E, Test-Org (Lightning).
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json),
 * baseURL from org.ts (never hardcoded, dev orgs are recreated).
 *
 * Session user is System Admin (devops-agent@cline.test):
 * admin holds Edit=Ja on ALL 5 new fields via its profile, so FLS "read-only
 * for Service-Mitarbeiter" CANNOT be proven via UI button absence here.
 * Per house rule §4c and SCRUM-437 notizen: FLS read-only + negative access
 * are covered by Apex (SCRUM437ProblemSerieFlsTest, System.runAs, no licence).
 *
 * AC1  (kein Serie):        test 1  — B-REC-1 (allein in (B,Rechnung))
 * AC2  (Serie bei 3. Fall): test 2  — A-REC-1/2/3 → gleiche Key, count=2
 * AC3  (andere Kategorie):  test 3  — A-DELIVER ≠ Rechnung-Serie
 * AC6  (Kategorie → Neubewertung): test 4 — UI-Edit A-REC-3 Rechnung→Lieferung
 * AC9  (gleiche Kennung):   test 2  — alle 3 tragen denselben String
 * DoD UI (andere Cases):    test 2  — Letzter aehnlicher Case als klickbarer Link
 *
 * Apex-only (E2E nicht konstruierbar — ClosedDate wird beim Schliessen
 * automatisch gestempelt, ist nicht zurücksetzbar):
 *   AC4  älter als 30 Tage  →  SCRUM437ProblemSerieTest.ac4_ge30Tage_geschlossen_zaeHtNicht
 *   AC5  offen+geschlossen  →  SCRUM437ProblemSerieTest.ac5_offen_und_frischGegschlossen_ImPool
 *   AC7  mehrere Accounts gleichzeitig →  SCRUM437ProblemSerieTest.ac7_zweiAccounts_gleichzeitig
 *   AC8  bulkified 1 SOQL/Batch →  SCRUM437ProblemSerieTest.ac8_bulkified_eineQueryProBatch
 *   FLS  read-only + negativer Access →  SCRUM437ProblemSerieFlsTest +
 *                                         SCRUM437ProblemSerieTest.flsStandardUserNuetztDasFeature
 *
 * Locators probed 2026-10-03 against Test-Org (see docs/SCRUM-437-notizen.md):
 *   - Section heading "Problemserie" (Details tab)
 *   - Problemkategorie combobox: [role=combobox][aria-label*="Problemkategorie"]
 *   - Picklist options: role=option, e.g. { name: 'Lieferung', exact: true }
 *   - Letzter aehnlicher Case: [role=link] name=<CaseNumber> → href=<record URL>
 *   - "Edit Problemkategorie" button: visible for admin; 4 compute fields also
 *     show "Edit" buttons on admin (profile-level Edit) — read-only assertion
 *     NOT testable via E2E in this session.
 */
import { expect, test, type Page } from '@playwright/test';
import { execSync } from 'child_process';
import { openRecordDetails, saveInlineEdit } from './record-page';

const TAG = 'TEST-SCRUM-437-';

// ─── sf helpers ─────────────────────────────────────────────────────────────────

function sfStripped(cmd: string): string {
  return execSync(cmd, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  }).replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');
}

function sfCreate(s: string, v: string): string {
  const raw = sfStripped(`sf data create record -s ${s} -o Test-Org -v "${v}" --json`);
  const m = raw.match(/"id"\s*:\s*"([0-9A-Za-z]{15,18})"/);
  if (!m) throw new Error(`sf create ${s} no id:\n${raw.slice(0, 400)}`);
  return m[1];
}

function sfDelete(s: string, id: string): void {
  try { sfStripped(`sf data delete record -s ${s} -o Test-Org -i ${id}`); } catch { /* teardown */ }
}

function sfQuery<T = any>(soql: string): T[] {
  const raw = sfStripped(`sf data query -o Test-Org -q "${soql}" --json`);
  return (JSON.parse(raw).result?.records ?? []) as T[];
}

interface CaseRow {
  Id: string;
  CaseNumber: string;
  Subject: string;
  Problemkategorie__c: string | null;
  Problemserie__c: string | null;
  Wiederkehrendes_Problem__c: boolean | null;
  Anzahl_aehnlicher_offener_Cases__c: number | null;
  Letzter_aehnlicher_Case__c: string | null;
}

const CASE_FIELDS =
  'Id, CaseNumber, Subject, Problemkategorie__c, Problemserie__c, ' +
  'Wiederkehrendes_Problem__c, Anzahl_aehnlicher_offener_Cases__c, Letzter_aehnlicher_Case__c';

function getCase(id: string): CaseRow {
  const rows = sfQuery<CaseRow>(`SELECT ${CASE_FIELDS} FROM Case WHERE Id = '${id}'`);
  if (rows.length !== 1) throw new Error(`Expected 1 Case row for ${id}, got ${rows.length}`);
  return rows[0];
}

function seriesKey(accountId: string, apiValue: string): string {
  return `${accountId}_${apiValue}`;
}

/**
 * Poll SOQL for up to `timeoutMs` until every id is readable AND two
 * consecutive reads agree. Each `sf` call is ~2s, so a full pass takes ~10s
 * for 5 ids — the hook must be given matching head-room (see beforeAll).
 * Returns true on stable, false on timeout (the test assertions then fail
 * with a readable SOQL message; this guard is not itself the check).
 */
async function waitForTriggerStable(ids: string[], timeoutMs = 60000): Promise<boolean> {
  const read = (id: string): string => {
    const rows = sfQuery<CaseRow>(`SELECT ${CASE_FIELDS} FROM Case WHERE Id = '${id}'`);
    if (rows.length !== 1) return 'MISSING';
    const r = rows[0];
    return `${r.Problemserie__c ?? 'null'}|${r.Wiederkehrendes_Problem__c ?? 0}|${r.Anzahl_aehnlicher_offener_Cases__c ?? 0}`;
  };
  const deadline = Date.now() + timeoutMs;
  let prev = '';
  while (Date.now() < deadline) {
    const sig = ids.map(read).join(';;');
    // Stable = this read matches the PREVIOUS read and nothing is missing.
    if (prev !== '' && sig === prev && !sig.includes('MISSING')) return true;
    prev = sig;
    await new Promise(r => setTimeout(r, 2500));
  }
  return false;
}

// ─── Fixtures ───────────────────────────────────────────────────────────────────

interface Fx {
  accA: string; accB: string;
  recA1: string; recA2: string; recA3: string;  // Account A, Rechnung, offen
  delA1: string;                                 // Account A, Lieferung, offen
  recB1: string;                                 // Account B, Rechnung, offen
}

let fx: Fx;

function seed(): Fx {
  for (const r of sfQuery(`SELECT Id FROM Case WHERE Subject LIKE '${TAG}%'`)) sfDelete('Case', r.Id);
  for (const r of sfQuery(`SELECT Id FROM Account WHERE Name  LIKE '${TAG}%'`)) sfDelete('Account', r.Id);

  const accA  = sfCreate('Account', `Name=${TAG}AccA`);
  const accB  = sfCreate('Account', `Name=${TAG}AccB`);
  const recA1 = sfCreate('Case',
    `Subject=${TAG}RECA1 Origin=Phone Status=New Problemkategorie__c=Rechnung AccountId=${accA}`);
  const recA2 = sfCreate('Case',
    `Subject=${TAG}RECA2 Origin=Phone Status=New Problemkategorie__c=Rechnung AccountId=${accA}`);
  const recA3 = sfCreate('Case',
    `Subject=${TAG}RECA3 Origin=Phone Status=New Problemkategorie__c=Rechnung AccountId=${accA}`);
  const delA1 = sfCreate('Case',
    `Subject=${TAG}DELA1 Origin=Phone Status=New Problemkategorie__c=Lieferung AccountId=${accA}`);
  const recB1 = sfCreate('Case',
    `Subject=${TAG}RECB1 Origin=Phone Status=New Problemkategorie__c=Rechnung AccountId=${accB}`);

  return { accA, accB, recA1, recA2, recA3, delA1, recB1 };
}

// ─── Test suite ─────────────────────────────────────────────────────────────────

test.describe('[SCRUM-437] Problemserie auf Case', () => {
  test.describe.configure({ mode: 'serial', timeout: 180000 });

  // 7 CLI calls + a 2-pass SOQL poll easily exceed the 30 s hook default;
  // test.setTimeout INSIDE the hook raises that hook's own timeout (not the
  // next test's — Playwright 1.61 docs, "Set timeout for this hook").
  test.beforeAll(async () => {
    test.setTimeout(180000);
    fx = seed();
    const stable = await waitForTriggerStable(
      [fx.recA1, fx.recA2, fx.recA3, fx.delA1, fx.recB1], 90000
    );
    expect(stable, 'Case fixtures did not reach a stable, trigger-applied state').toBe(true);
  });

  test.afterAll(() => {
    for (const id of [fx.recA1, fx.recA2, fx.recA3, fx.delA1, fx.recB1]) sfDelete('Case', id);
    sfDelete('Account', fx.accA);
    sfDelete('Account', fx.accB);
  });

  // ---------------------------------------------------------------------------

  test(
    '1. AC1: erster Case eines Kunden — keine Serie, count=0, wiederkehrend=false',
    async ({ page }) => {
      // SOQL: ground truth
      const b1 = getCase(fx.recB1);
      expect(b1.Problemserie__c,        'B-REC-1: no series key expected').toBeNull();
      expect(b1.Wiederkehrendes_Problem__c, 'B-REC-1: recurring=false').toBeFalsy();
      expect(b1.Anzahl_aehnlicher_offener_Cases__c, 'B-REC-1: count=0').toBe(0);
      expect(b1.Letzter_aehnlicher_Case__c,         'B-REC-1: no Letzter').toBeNull();

      // UI: section heading present (layout deployed), no key rendered, count=0
      await openRecordDetails(page, `/lightning/r/Case/${fx.recB1}/view`);
      const bodyText = (await page.locator('body').innerText()).replace(/\t/g, ' ');
      expect(bodyText, 'section heading "Problemserie" not found on B-REC-1').toContain('Problemserie');

      // The group key (accB_Rechnung) must NOT appear in the rendered section.
      // Scope to lines around the section heading to avoid false positives.
      const lines = bodyText.split('\n').map(l => l.trim());
      const headingIdx = lines.lastIndexOf('Problemserie'); // section heading is the LAST "Problemserie" string
      const section = lines.slice(Math.max(0, headingIdx), Math.min(lines.length, headingIdx + 20)).join('\n');
      expect(section, `${seriesKey(fx.accB, 'Rechnung')} must not appear in B-REC-1 section`)
        .not.toContain(seriesKey(fx.accB, 'Rechnung'));

      const countIdx = lines.indexOf('Anzahl aehnlicher offener Cases');
      expect(countIdx, 'label "Anzahl aehnlicher offener Cases" must be on the page').not.toBe(-1);
      expect(lines[countIdx + 1], `count line (got "${lines[countIdx+1]}")`).toBe('0');
    }
  );

  test(
    '2. AC2/AC9 + DoD-UI: Serie mit 3 Cases — gleiche Kennung, count=2, Letzter-Link',
    async ({ page }) => {
      // SOQL: all three carry the same deterministic key
      const expectedKey = seriesKey(fx.accA, 'Rechnung');
      for (const [label, id] of [
        ['A-REC-1', fx.recA1], ['A-REC-2', fx.recA2], ['A-REC-3', fx.recA3],
      ] as const) {
        const r = getCase(id);
        expect(r.Problemserie__c,                  `${label}: key should be ${expectedKey}`).toBe(expectedKey);
        expect(r.Wiederkehrendes_Problem__c,       `${label}: recurring=true`).toBe(true);
        expect(r.Anzahl_aehnlicher_offener_Cases__c, `${label}: count=2 (2 further open cases in pool)`).toBe(2);
        expect(r.Letzter_aehnlicher_Case__c,        `${label}: Letzter set`).toBeTruthy();
      }

      // UI: open A-REC-1, verify section renders the expected values
      await openRecordDetails(page, `/lightning/r/Case/${fx.recA1}/view`);
      const bodyText = (await page.locator('body').innerText()).replace(/\t/g, ' ');
      const lines = bodyText.split('\n').map(l => l.trim());
      const sIdx = lines.lastIndexOf('Problemserie');
      const section = lines.slice(Math.max(0, sIdx), Math.min(lines.length, sIdx + 20)).join('\n');

      expect(section, `series key "${expectedKey}" must appear in A-REC-1 section`)
        .toContain(expectedKey);

      const recurIdx = sectionLinesIndex(lines, 'Wiederkehrendes Problem');
      expect(recurIdx, 'label "Wiederkehrendes Problem" must be in section').not.toBe(-1);
      expect(lines[recurIdx + 1]?.toLowerCase(), 'Wiederkehrendes Problem should be "true"')
        .toBe('true');

      const cntIdx2 = lines.indexOf('Anzahl aehnlicher offener Cases');
      expect(lines[cntIdx2 + 1], `count should be "2" (got "${lines[cntIdx2+1]}")`).toBe('2');

      // DoD-UI: "Letzter aehnlicher Case" is a clickable link to the referenced record.
      // A-REC-1's Letzter = max CreatedDate in pool {A-REC-2, A-REC-3}.
      const a1 = getCase(fx.recA1);
      const letzterRow = getCase(a1.Letzter_aehnlicher_Case__c!);
      const link = page
        .getByRole('link', { name: letzterRow.CaseNumber })
        .first();
      await expect(
        link,
        `Letzter aehnlicher Case link for case ${letzterRow.CaseNumber} not found`
      ).toBeVisible({ timeout: 15000 });
    }
  );

  test(
    '3. AC3: unterschiedliche Kategorie am selben Account — NICHT verrechnet',
    async ({ page }) => {
      // SOQL: A-DELIVER alone in (A, Lieferung) → no series, count=0
      const d1 = getCase(fx.delA1);
      expect(d1.Problemserie__c,                 'DELIVER: no series key (alone in A/Lieferung)').toBeNull();
      expect(d1.Wiederkehrendes_Problem__c,       'DELIVER: recurring=false').toBeFalsy();
      expect(d1.Anzahl_aehnlicher_offener_Cases__c, 'DELIVER: count=0').toBe(0);
      expect(d1.Letzter_aehnlicher_Case__c,        'DELIVER: no Letzter').toBeNull();

      // Its pool is the (A, Lieferung) group excluding self → only A-REC-1/2/3 are Rechnung, not Lieferung
      // So count is 0 even though Account A has other open cases.

      // UI: the Rechnung key must not appear in DELIVER's section
      await openRecordDetails(page, `/lightning/r/Case/${fx.delA1}/view`);
      const bodyText = (await page.locator('body').innerText()).replace(/\t/g, ' ');
      const lines = bodyText.split('\n').map(l => l.trim());
      const sIdx = lines.lastIndexOf('Problemserie');
      const section = lines.slice(Math.max(0, sIdx), Math.min(lines.length, sIdx + 20)).join('\n');
      expect(
        section,
        `Rechnung key (${seriesKey(fx.accA, 'Rechnung')}) must not appear on the DELIVER record`
      ).not.toContain(seriesKey(fx.accA, 'Rechnung'));
    }
  );

  test(
    '4. AC6: Kategorie-Änderung Rechnung→Lieferung — Serie neu bewertet, ADR-2 Persistenz',
    async ({ page }) => {
      // Precondition: A-REC-3 currently carries the Rechnung series key
      const before = getCase(fx.recA3);
      const oldKey = before.Problemserie__c!;
      expect(oldKey, 'precondition: A-REC-3 must hold the Rechnung key').toBe(seriesKey(fx.accA, 'Rechnung'));

      // UI: inline-edit Problemkategorie from Rechnung → Lieferung
      const p = await (await page.context()).newPage();
      try {
        await p.goto(`/lightning/r/Case/${fx.recA3}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
        await p
          .locator('div.slds-global-header, one-appnav').first()
          .waitFor({ state: 'visible', timeout: 60000 });
        const details = p.getByRole('tab', { name: 'Details' });
        await details.waitFor({ state: 'visible', timeout: 30000 });
        for (let i = 0; i < 5; i++) {
          await details.click().catch(() => {});
          await p.waitForTimeout(1200);
          if ((await details.getAttribute('aria-selected').catch(() => null)) === 'true') break;
        }
        await p.getByRole('button', { name: 'Edit Problemkategorie' }).click();
        await p.waitForTimeout(1000);
        // Probed 2026-10-03: [role=combobox][aria-label*="Problemkategorie"] → unique match.
        const combo = p
          .locator('[role=combobox][aria-label*="Problemkategorie"]')
          .first();
        await combo.click();
        await p.waitForTimeout(800);
        await p.getByRole('option', { name: 'Lieferung', exact: true }).click();
        await p.waitForTimeout(800);
        await saveInlineEdit(p);
        await p
          .getByText('Problemkategorie', { exact: false })
          .first()
          .waitFor({ state: 'visible', timeout: 30000 });
      } finally {
        await p.close();
      }

      // Wait for the DML + trigger to complete (category written AND fields recomputed)
      await waitForTriggerStable(
        [fx.recA3, fx.recA1, fx.recA2, fx.delA1], 30000
      );

      // A-REC-3: now in (A, Lieferung) with only A-DELIVER in pool (size 1 < 2).
      // A/Lieferung windowCount = 2 < 3 → no series.
      const a3after  = getCase(fx.recA3);
      const delAfter = getCase(fx.delA1);
      const a1After  = getCase(fx.recA1);
      const a2After  = getCase(fx.recA2);

      expect(a3after.Problemkategorie__c,     'A-REC-3: category updated to Lieferung').toBe('Lieferung');
      expect(a3after.Problemserie__c,          'A-REC-3: loses old key (A/Lieferung has 2 < 3 threshold)').toBeNull();
      expect(a3after.Wiederkehrendes_Problem__c, 'A-REC-3: no longer recurring (pool size 1 < 2)').toBeFalsy();
      expect(a3after.Anzahl_aehnlicher_offener_Cases__c, 'A-REC-3: count=1 (A-DELIVER open in pool)').toBe(1);

      // A-DELIVER: A/Lieferung now has 2 cases (still < 3) → no series.
      // Its pool = {A-REC-3} (open) → count=1.
      expect(delAfter.Problemserie__c,        'DELIVER: still no series (A/Lieferung < threshold)').toBeNull();
      expect(delAfter.Anzahl_aehnlicher_offener_Cases__c, 'DELIVER: count=1 (A-REC-3 now in its pool)').toBe(1);

      // ADR-2 persistence: A-REC-1 & A-REC-2 keep the Rechnung key even though
      // (A, Rechnung) dropped to 2 (below the 3-case threshold).
      // hasEstablished=true because both still carry the exact seriesKey.
      expect(a1After.Problemserie__c, `ADR-2: A-REC-1 keeps "${oldKey}" (persisted)`).toBe(oldKey);
      expect(a2After.Problemserie__c, `ADR-2: A-REC-2 keeps "${oldKey}" (persisted)`).toBe(oldKey);
      // Their pool now has only one other open case (each other) → count=1
      expect(a1After.Anzahl_aehnlicher_offener_Cases__c, 'A-REC-1: count now 1 (only A-REC-2 in pool)').toBe(1);
      expect(a2After.Anzahl_aehnlicher_offener_Cases__c, 'A-REC-2: count now 1 (only A-REC-1 in pool)').toBe(1);
    }
  );
});

/** Index of the first line that equals `label` exactly. */
function sectionLinesIndex(lines: string[], label: string): number {
  const idx = lines.indexOf(label);
  return idx;
}
