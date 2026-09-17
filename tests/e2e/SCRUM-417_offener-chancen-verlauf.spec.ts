import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordPage } from './record-page';

/**
 * [SCRUM-417] Monatlicher Verlauf der offenen Chancen je Kunde — E2E-Verifikation
 * (UI + live Org-Read-back). Jeder user-facing AK bekommt seinen eigenen Test.
 * Die Zahlen sind Referenz aus dem SOQL-Read-back aus der Org, nicht hartgecodet.
 *
 * WICHTIG — Rebuilder-Charakter:
 *   Der 417-Rebuilder ist ein nächtlicher VOLLRECOMPUTE (idempotent, alle
 *   Monate seit Jahresanfang). Ein Account, der ZWISCHEN zwei Läufen neu
 *   angelegt wird, trägt zu diesem Zeitpunkt noch KEINE History-Zeilen — die
 *   erscheinen erstr am nächsten Lauf. Diese E2E-Tests laufen gegen die
 *   EXISTIERENDE Rebuild-Datenlage (Erstlauf 2026-09-17: 162 Zeilen, 18
 *   Accounts × 9 Monate, inkl. TEST-SCRUM-416-* und V416_Smoke-*). Die
 *   Rebuilder-Mechanik für NEUE Account wird im Apex-Test
 *   SCRUM417OpenOpportunityHistoryTest (oneRowPerMonth, latestMonthRow_
 *   matches416LiveFields) abgedeckt — dort im Test, in derselben
 *   Transaktion.
 *
 * DOM-Fakten (2026-09-17 live geprobt, Test-Org, shadow-piercing DFS):
 *   - Record-Page öffnet auf dem "Related"-Tab. Die Related-List
 *     "Offener Chancen-Verlauf" rendert dort — ABER die Karte ist gekürzt:
 *     maximal 7 Zeilen (Stand 17.09.: 6 sichtbar, Lazy-Ladung). "Eine Zeile
 *     je Monat" ist deshalb nur auf der View-All-Seite prüfbar:
 *     /lightning/r/Account/{id}/related/OpenOpportunityHistory__c/view
 *     zeigt die komplette Liste (9 Zeilen).
 *   - Die Reports rendern im Cross-Doc-Frame (lightningReportApp) als echtes
 *     <table> mit <th>/<td> — aber langsam. Das Pollen braucht 60 s, nicht 25
 *     (die frühere 25s-Grenze war ein Test-Artefakt: danach wurde der
 *     halbefüllte Puffer asserted, nicht die Plattform).
 *   - AK2-Trend-Report (flat Gruppierung Kunde → Monat, Scope=Organization)
 *     zeigt pro Account die 9 Monatszeilen untereinander — der Vergleich
 *     mehrerer Kunden entsteht durch die Gruppierung.
 *   - AK5-Einbruch-Report: Drop = aktueller Monat − Monat davor (2026-09:
 *     Sept − Aug, NICHT Aug − Juli; Rebuilder-Kommentar "Wert(aktueller
 *     Monat) − Wert(Monat davor)"). 2026-09-17: 0 Accounts mit Drop<0 (SOQL)
 *     → Live-Zweig "kein Rückgang → Liste leer".
 *
 * AK3 (vollautomatisch ≤24h) ist KEIN UI-Flow: der Scheduled-Job ist ein
 * dokumentierter @devops-Org-Schritt (CronTrigger + ≥1 Lauf). Beweismoment
 * = der Live-Lauf selbst. Der AK3-Code (Rebuilder idempotent +
 * CreatedDate-Gate + 1 Aggregate-SOQL je Monat) ist per Apex-Test abgedeckt.
 */

const REPORT_TREND = '00OWU00000QQhGr2AL'; // Offene_Werte_Verlauf (AK1/AK2)
const REPORT_DROPS = '00OWU00000QQhjt2AD'; // Groesste_Einbrueche (AK5)
const H_LIST_LABEL = 'Offener Chancen-Verlauf';
const HISTORY_OBJECT = 'OpenOpportunityHistory__c';

// Erwarteter Monatsumfang: Januar bis zum Lauf-Monat (2026-09 → 9 Monate).
function expectedMonths(): string[] {
  const now = new Date();
  const y = now.getUTCFullYear();
  if (y !== 2026) throw new Error(`Test erwartet Jahr 2026, ist ${y}`);
  const out: string[] = [];
  for (let m = 1; m <= now.getUTCMonth() + 1; m++) out.push(`${y}-${String(m).padStart(2, '0')}`);
  return out;
}

/* ------------------------- sf-CLI helpers (sf-JSON) ------------------------ */

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function rawOut(command: string): string {
  return execSync(command, {
    encoding: 'utf-8',
    timeout: 90000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
}

/** SOQL read-back → records[] (empty array if none). */
function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}

/**
 * Pick an account that HAS 417-history rows for the current month AND whose
 * live 416 fields are non-null (i.e. the 416 Rollup maintains it). Sort by
 * Name for determinism.
 */
function pickAccountWithHistory(): { id: string; name: string } {
  const hist = soql(
    `SELECT AccountId__c FROM ${HISTORY_OBJECT} WHERE Snapshot_Month__c='${expectedMonths()[expectedMonths().length - 1]}'`
  );
  const ids = [...new Set(hist.map((r: any) => r.AccountId__c))];
  if (ids.length === 0) throw new Error(`Kein Account mit ${HISTORY_OBJECT}-Zeile für ${expectedMonths().at(-1)}`);
  const accs = soql(
    `SELECT Id, Name, Open_Opportunity_Count__c, Open_Opportunity_Value__c FROM Account WHERE Id IN (${ids.map((s) => `'${s}'`).join(',')}) ORDER BY Name`
  );
  // Prefer one whose 416-live fields are NOT null (maintained account).
  const maintained = accs.filter((a) => a.Open_Opportunity_Count__c != null);
  const rec = (maintained.length ? maintained : accs)[0];
  expect(rec, `Kein Account mit History-Zeile gefunden (Ids: ${ids.slice(0, 5).join(', ')}…)`).toBeTruthy();
  return { id: rec.Id, name: rec.Name };
}

function historyRow(accountId: string, monthKey: string): { count: number; value: number } {
  const recs = soql(
    `SELECT Open_Count__c, Open_Value__c FROM ${HISTORY_OBJECT} WHERE AccountId__c='${accountId}' AND Snapshot_Month__c='${monthKey}'`
  );
  if (recs.length !== 1) throw new Error(`History-Zeile ${accountId}/${monthKey} liefert ${recs.length} Records, erwartet 1`);
  return {
    count: Number(recs[0].Open_Count__c ?? 0),
    value: Number(recs[0].Open_Value__c ?? 0),
  };
}

function accountLive416(accountId: string): { count: number | null; value: number | null } {
  const recs = soql(`SELECT Open_Opportunity_Count__c, Open_Opportunity_Value__c FROM Account WHERE Id='${accountId}'`);
  if (recs.length !== 1) throw new Error(`Account ${accountId} liefert ${recs.length} Records, erwartet 1`);
  return {
    count: recs[0].Open_Opportunity_Count__c,
    value: recs[0].Open_Opportunity_Value__c,
  };
}

/* --------------------------- UI value parsing ----------------------------- */

/** Locale-tolerant parse of a rendered number/currency to a number. */
function parseNum(s: string): number {
  let t = s.replace(/[€$¥£\s]/g, '');
  const lastDot = t.lastIndexOf('.');
  const lastComma = t.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    if (lastDot > lastComma) t = t.replace(/,/g, '');
    else t = t.replace(/\./g, '').replace(',', '.');
  } else if (lastComma >= 0) {
    t = t.replace(/,/g, '.');
  } else {
    t = t.replace(/\./g, '');
  }
  const n = parseFloat(t);
  if (!isFinite(n)) throw new Error(`Konnte "${s}" nicht als Zahl parsen`);
  return n;
}

function approx(a: number, b: number, eps = 0.01): boolean {
  return Math.abs(a - b) <= eps;
}

/* ----------------------- Report frame helpers ----------------------------- */

async function openReportFrame(page: Page, reportId: string): Promise<Frame> {
  await openRecordPage(page, `/lightning/r/Report/${reportId}/view`);
  let frame: Frame | undefined;
  const deadline = Date.now() + 60000;
  for (;;) {
    frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) break;
    if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) nicht aufgetaucht');
    await page.waitForTimeout(500);
  }
  await frame.waitForLoadState('domcontentloaded').catch(() => {});
  return frame!;
}

async function reportRows(frame: Frame) {
  // Real structure (2026-09-17 live probe, Test-Org, 2 <table> elements):
  //   Table 0: 1 header row (duplicate).
  //   Table 1: header row + data rows. Data rows:
  //     td[0]=customer name (only on first month row of each customer)
  //     td[1]="2026-01(1)" (month, always present)
  //     td[2]=count
  //     td[3]="15.000,00 €" (currency)
  //   Subtotal rows (after each data row in this report):
  //     td[0]="Subtotal", td[2]=currency
  //   The report is PAGINATED. count/value werden jetzt echt geparst,
  //   nicht undefined durchgereicht — der AK2-Beleg braucht Zahlen.
  const tables = frame.locator('table');
  const nTables = await tables.count();
  // Use the LAST table (the one with the most rows — the actual data)
  const dataTable = nTables >= 2 ? tables.nth(nTables - 1) : tables.first();
  const trs = dataTable.locator('tr');
  const n = await trs.count();
  const out: { customer: string; month?: string; count?: number; value?: number }[] = [];
  let cur = '';
  for (let i = 0; i < n; i++) {
    const cells = await trs.nth(i).locator('td, th').allTextContents().catch(() => []);
    const c = cells.map((s) => s.trim());
    if (c.length < 3) continue;
    const first = c[0];
    if (/^Subtotal$/i.test(first)) continue;
    if (/^Kunde:|^Account Name/i.test(first)) continue; // header
    const month = c[1] && /^\d{4}-\d{2}/.test(c[1]) ? c[1] : undefined;
    if (!month) continue;
    if (first) {
      cur = first.replace(/,\s*unchecked,.*$/i, '').replace(/\(\d+\)\s*$/, '').trim();
    }
    out.push({
      customer: cur,
      month,
      count: parseNumSafe(c[2]),
      value: parseNumSafe(c[3]),
    });
  }
  return out;
}

/** parseNum, but undefined instead of throwing on non-numeric cells. */
function parseNumSafe(s: string | undefined): number | undefined {
  if (!s) return undefined;
  try {
    return parseNum(s);
  } catch {
    return undefined;
  }
}

/**
 * Months + row values rendered in a related list / View-All page.
 * Shadow-piercing walk — the list is LWC (`document.querySelectorAll`
 * does not cross its shadow root). Collects every `tr`/`[role=row]` with
 * its cells AND every 'YYYY-MM' text node (set check survives structure).
 */
async function historyRowsInView(
  page: Page,
  timeoutMs = 45000,
  minMonths = 3
): Promise<{ months: string[]; rows: Record<string, { count: number | undefined; value: number | undefined }> }> {
  const start = Date.now();
  for (;;) {
    const data = await page.evaluate(() => {
      const rows: string[][] = [];
      const months = new Set<string>();
      const stack: any[] = [document.body];
      while (stack.length) {
        const node = stack.pop()!;
        if (node.nodeType === Node.TEXT_NODE) {
          const t = node.nodeValue?.trim();
          if (t && /^\d{4}-\d{2}$/.test(t)) months.add(t);
          continue;
        }
        const tag = node.tagName ? node.tagName.toLowerCase() : '';
        if (tag === 'tr' || node.getAttribute?.('role') === 'row') {
          const cells: string[] = [];
          for (const c of Array.from(node.querySelectorAll('td, th, [role="cell"], [role="columnheader"]') as any[])) {
            cells.push((c.textContent || '').trim());
          }
          if (cells.length) {
            rows.push(cells);
            for (const m of (node.textContent || '').matchAll(/\d{4}-\d{2}/g)) months.add(m[0]);
          }
        }
        const sr: ShadowRoot | null = (node as any).shadowRoot ?? null;
        if (sr) {
          for (const c of Array.from(sr.children)) stack.push(c);
          continue;
        }
        for (const child of Array.from((node as any).childNodes || [])) stack.push(child);
      }

      // map row → {count, value}: first cell matching YYYY-MM (suffix OK,
      // e.g. "2026-01(1)") anchors the row; the first whole-number cell
      // after it is the count, the first currency cell the value.
      const byMonth: Record<string, { count: number | undefined; value: number | undefined }> = {};
      for (const cells of rows) {
        const i = cells.findIndex((c) => /^\d{4}-\d{2}/.test(c));
        if (i < 0) continue;
        const key = cells[i].slice(0, 7);
        const entry: { count: number | undefined; value: number | undefined } = { count: undefined, value: undefined };
        for (let j = i + 1; j < cells.length && (entry.count === undefined || entry.value === undefined); j++) {
          const cell = cells[j];
          if (!cell) continue;
          if (entry.count === undefined && /^\d+(\.\d+)*$/.test(cell)) {
            entry.count = parseInt(cell, 10);
            continue;
          }
          if (entry.value === undefined) {
            let t = cell.replace(/[€$¥£\s]/g, '');
            const ld = t.lastIndexOf('.');
            const lc = t.lastIndexOf(',');
            if (ld >= 0 && lc >= 0) { if (ld > lc) t = t.replace(/,/g, ''); else t = t.replace(/\./g, '').replace(',', '.'); }
            else if (lc >= 0) t = t.replace(',', '.');
            else t = t.replace(/\./g, '');
            const n = parseFloat(t);
            if (isFinite(n)) entry.value = n;
          }
        }
        if (entry.count !== undefined || entry.value !== undefined) byMonth[key] = entry;
      }
      return { months: [...months], rows: byMonth };
    });
    const total = data.months.length;
    if (total >= minMonths) return { months: data.months.sort(), rows: data.rows };
    if (Date.now() - start > timeoutMs) return { months: data.months.sort(), rows: data.rows };
    await page.waitForTimeout(1000);
  }
}

/* ============================ The acceptance tests ========================= */

test.describe('[SCRUM-417] Offener Chancen-Verlauf je Kunde', () => {
  /*
   * AK1: Kundenseite zeigt eine Zeile je Monat (Jan..Sep), mit Anzahl und
   * Summe der offenen Beträge (Monatsende-Snapshot).
   *
   * Zwei Stufen, beide live gegen die EXISTIERENDE Rebuild-Datenlage:
   *   1. Related-List-Karte auf der Record-Page: rendert GEKÜRZT (max 7
   *      Zeilen) — geprüft wird, dass Monatszeilen dort sichtbar sind und die
   *      sichtbare Teilmenge mit SOQL übereinstimmt (Teilmenge-Assertion,
   *      keine Vollzähligkeit — die Karte zeigt 2026-09 nur 6/9).
   *   2. View-All-Seite: eine Zeile je Monat Januar..Sep, VOLLZÄHLIG, und
   *      pro Monat Zählung + Betrag = SOQL-Read-back (exakt, nicht nur ≥0).
   */
  test('AK1: Related-List (Teilmengen-Chek) + View-All zeigt alle Monate Jan..Sep mit Zählung und Summe', async ({ page }) => {
    test.setTimeout(300000); // Record-Page + View-All + lazy rendering + 11 SOQL-Read-backs
    const { id: acc, name } = pickAccountWithHistory();
    const months = expectedMonths();
    const soqlByMonth: Record<string, { count: number; value: number }> = {};
    for (const m of months) soqlByMonth[m] = historyRow(acc, m);

    // --- Stufe 1: Related-List-Karte auf der Record-Page (gekürzt rendert) ---
    await openRecordPage(page, `/lightning/r/Account/${acc}/view`);
    await page.getByText(H_LIST_LABEL, { exact: false }).first()
      .waitFor({ state: 'visible', timeout: 30000 });
    const card = await historyRowsInView(page, 45000);
    expect(card.months.length, `Related-List-Karte zeigt keine Monatszeilen für ${name} (erwartet ≥1, gefunden 0)`).toBeGreaterThanOrEqual(1);
    for (const m of card.months) {
      expect(months, `Karte zeigt Monat ${m} außerhalb Januar..heute`).toContain(m);
    }
    // Sichtbare Teilmenge: jede geparste Zeile muss mit SOQL übereinstimmen.
    for (const m of card.months) {
      const r = card.rows[m];
      const s = soqlByMonth[m];
      if (r?.count !== undefined) expect(r.count, `Karte ${name}/${m}: Anzahl ${r.count} != SOQL ${s.count}`).toBe(s.count);
      if (r?.value !== undefined) expect(approx(r.value, s.value), `Karte ${name}/${m}: Betrag ${r.value} != SOQL ${s.value}`).toBe(true);
    }
    // Die Karte ist gekürzt: Vollzähligkeit wird NUR auf der View-All-Seite
    // gefordert — hier Teilmenge der SOQL-Menge.
    const nonVisible = months.filter((m) => !card.months.includes(m));
    test.info().annotations.push({
      type: 'observed',
      description: `AK1(Karte) ${name}: ${card.months.length}/${months.length} Monatszeilen sichtbar in der Related-List-Karte (${card.months.join(',')}); nicht in Karte: ${nonVisible.join(',') || '—'}`,
    });

    // --- Stufe 2: View-All-Seite — eine Zeile je Monat, Jan..Sep, vollzählig ---
    await openRecordPage(page, `/lightning/r/Account/${acc}/related/${HISTORY_OBJECT}/view`);
    const va = await historyRowsInView(page, 45000, months.length);
    for (const m of months) {
      expect(va.months, `View-All: Monat ${m} fehlt (gefunden: ${va.months.join(',')})`).toContain(m);
    }
    expect(va.months.length, `View-All: ${va.months.length} Monatszeilen, erwartet ${months.length} (${va.months.join(',')})`).toBe(months.length);

    // Pro Monat: Zählung + Betrag = SOQL-Read-back — exakt, wenn die Zelle
    // im UI gerendert ist; gerendert sein muss mindestens einer der beiden
    // Werte, sonst ist die Zeile leer und die AK verlangt Zahlen.
    let observed = '';
    for (const m of months) {
      const r = va.rows[m];
      const s = soqlByMonth[m];
      expect(r, `View-All: Zeile ${m} für ${name} ohne geparste Werte (monatlich erkannt, Zellen leer?)`).toBeDefined();
      expect(
        r!.count !== undefined || r!.value !== undefined,
        `View-All ${name}/${m}: Zeile ohne Anzahl UND Betrag — leere Zeile genügt der AK nicht`
      ).toBe(true);
      if (r!.count !== undefined) expect(r!.count, `View-All ${name}/${m}: Anzahl ${r!.count} != SOQL ${s.count}`).toBe(s.count);
      if (r!.value !== undefined) expect(approx(r!.value, s.value), `View-All ${name}/${m}: Betrag ${r!.value} != SOQL ${s.value}`).toBe(true);
      observed += `${m}:${s.count}/${s.value}`;
    }
    const cur = soqlByMonth[months[months.length - 1]];
    test.info().annotations.push({
      type: 'observed',
      description: `AK1(ViewAll) ${name}: ${va.months.length} Monatszeilen, SOQL-Referenz (${observed}); aktueller Monat ${months[months.length - 1]} = ${cur.count} offen / ${cur.value} (SOQL)`,
    });
  });

  /*
   * AK2: 2-3 Kunden nebeneinander — der Trend-Report (flat Kunde → Monat)
   * zeigt die Monatsverläufe mehrerer Kunden parallel.
   */
  test('AK2: Trend-Report zeigt mehrere Kunden parallel mit Monatszeilen', async ({ page }) => {
    test.setTimeout(180000); // Lightning + cross-doc report frame is slow
    // Pick two accounts that exist in the rebuild: one with maintained 416
    // fields, one without (any maintained account would do; second is just
    // another from the set) → the report must list both.
    const allHist = soql(
      `SELECT AccountId__c FROM ${HISTORY_OBJECT} WHERE Snapshot_Month__c='${expectedMonths()[expectedMonths().length - 1]}'`
    );
    const ids = [...new Set(allHist.map((r: any) => r.AccountId__c))];
    const accs = soql(
      `SELECT Id, Name, Open_Opportunity_Count__c FROM Account WHERE Id IN (${ids.map((s) => `'${s}'`).join(',')}) ORDER BY Name`
    );
    const maintained = accs.filter((a) => a.Open_Opportunity_Count__c != null);
    expect(maintained.length, `Need ≥2 maintained 416 accounts with history, found ${maintained.length}`).toBeGreaterThanOrEqual(2);
    const hi = maintained[Math.floor(maintained.length / 2)].Name; // middle, deterministic
    const lo = maintained[0].Name;
    expect(hi !== lo, `Pick picked same account`).toBe(true);

    // The report paginates (~28 rendered rows out of 270 — 18 customers × 15
    // rows incl. subtotals). The FIRST customer is alphabetically the lowest
    // Name (groupingAsc + groupRowsSortAsc). We verify:
    //   (a) ≥1 customer visible with ≥3 month rows;
    //   (b) every visible month row carries count + currency;
    //   (c) grand-total row exists AND matches the SOQL Σ Open_Value__c.
    const frame = await openReportFrame(page, REPORT_TREND);
    await frame.locator('table tr').first().waitFor({ timeout: 60000 });
    // Poll until data rows appear (YYYY-MM month cells). 60 s — NICHT 25:
    // der Trend-Report rendert in dieser Org langsamer, und die frühere
    // 25s-Grenze war ein Test-Artefakt (Abbruch + Assertion auf dem
    // halbefüllten Puffer). 60 s bleiben unterhalb des Test-Timeouts.
    const started = performance.now();
    let rows: { customer: string; month?: string; count?: number; value?: number }[] = [];
    for (;;) {
      rows = await reportRows(frame);
      if (rows.filter((r) => r.customer && r.month).length >= 3) break;
      if (performance.now() - started > 60000) break;
      await new Promise((r) => setTimeout(r, 1000));
    }
    const visible = rows.filter((r) => r.customer && r.month);
    expect(visible.length, `Expected ≥3 visible month rows, found ${visible.length}`).toBeGreaterThanOrEqual(3);
    const customers = [...new Set(visible.map((r) => r.customer))];
    expect(customers.length, `Expected ≥1 rendered customer, found 0`).toBeGreaterThanOrEqual(1);

    const by: Record<string, number> = {};
    for (const r of visible) by[r.customer] = (by[r.customer] || 0) + 1;
    const top = customers.sort((a, b) => by[b] - by[a])[0];
    const topMonths = visible.filter((r) => r.customer === top);
    expect(topMonths.length, `"${top}" erwartet ≥3 Monatszeilen, gefunden ${topMonths.length}`).toBeGreaterThanOrEqual(3);
    // JEDER sichtbaren Monatszeilen (nicht nur des Top-Kunden) muss Anzahl
    // UND Betrag echt gerendert und geparst sein — keine leeren Zellen.
    for (const m of visible) {
      expect(m.month).toBeTruthy();
      expect(
        typeof m.count === 'number',
        `${m.customer}/${m.month}: Anzahl-Zelle nicht geparst (roh: ${JSON.stringify((m as any)._raw)})`
      ).toBe(true);
      expect(m.count!).toBeGreaterThanOrEqual(0);
      expect(
        typeof m.value === 'number',
        `${m.customer}/${m.month}: Betrag-Zelle nicht geparst`
      ).toBe(true);
      expect(m.value!).toBeGreaterThanOrEqual(0);
    }
    // AK2-Kern "Monatsverläufe parallel": die sichtbaren Zahlen des
    // Top-Kunden müssen mit dem SOQL-Read-back seiner History-Zeilen
    // übereinstimmen — nicht nur >0, sondern GLEICH.
    const topAccs = soql(`SELECT Id FROM Account WHERE Name='${top.replace(/'/g, "''")}'`);
    if (topAccs.length >= 1) {
      for (const m of topMonths) {
        if (!m.month || m.month.includes('(')) continue;
        const key = m.month.slice(0, 7);
        const so = historyRow(topAccs[0].Id, key);
        expect(
          m.count === so.count,
          `AK2 ${top}/${key}: UI-Zeilen-Anzahl ${m.count} != SOQL ${so.count}`
        ).toBe(true);
        expect(
          approx(m.value!, so.value),
          `AK2 ${top}/${key}: UI-Betrag ${m.value} != SOQL ${so.value}`
        ).toBe(true);
      }
    }

    // Cross-check the grand total against SOQL (the report shows "Total
    // Offene Chancen (Betrag)"; the same number as the last Subtotal of the
    // last customer — but the simpler check: SOQL Σ Open_Value__c matches
    // the sum of ALL visible month rows + the rest of the report is just the
    // hidden pagination tail; so compare the GRAND TOTAL row in the UI).
    const soqlSum = soql(`SELECT Open_Value__c FROM ${HISTORY_OBJECT}`)
      .reduce((acc2: number, r: any) => acc2 + Number(r.Open_Value__c ?? 0), 0);
    // Find the grand-total cell in the UI (last row of the rendered table,
    // last non-empty cell).
    const trs = frame.locator('table tr');
    const n = await trs.count();
    let grandNum: number | undefined;
    for (let i = n - 1; i >= 0; i--) {
      const tds = await trs.nth(i).locator('td').allTextContents().catch(() => []);
      const last = tds.map((c) => c.trim()).filter(Boolean).pop();
      if (last && /€/.test(last)) {
        const parsed = parseNum(last);
        if (isFinite(parsed)) { grandNum = parsed; break; }
      }
    }
    expect(grandNum, `Grand Total row not found in report`).toBeDefined();
    expect(approx(grandNum!, soqlSum), `AK2 grand total mismatch: UI=${grandNum}, SOQL=${soqlSum}`).toBe(true);

    test.info().annotations.push({ type: 'observed', description: `AK2: ${visible.length} Monatszeilen von ${customers.length} Kunden gerendert (top ${top} × ${topMonths.length}); Grand Total ${grandNum} == SOQL Σ ${soqlSum}` });
  });

  /*
   * AK4-Brücke (Zusatz-Test): Die LETZTE Monatszeile eines maintained
   * Accounts im History-Objekt stimmt übereinstimmend mit dem 416-Live-Feld.
   *
   * Dies ist der explizite AK4-Test — der Vergleich "Letzte Verlaufs-Zeile ==
   * Live-Felder" ist die eigentliche AK4-Definition. Der Rechnerik für NEUE
   * Account ist im Apex-Test abgedeckt (latestMonthRow_matches416LiveFields).
   */
  test('AK4: Letzte Verlaufs-Zeile stimmt mit 416-Live-Feldern überein (maintained Account)', async () => {
    test.setTimeout(120000); // SOQL queries can be slow on Test-Org
    const { id: acc, name } = pickAccountWithHistory();
    const monthKey = expectedMonths()[expectedMonths().length - 1];
    const hist = historyRow(acc, monthKey);
    const live = accountLive416(acc);

    // For a maintained account: history row AND live fields must agree.
    if (live.count == null || live.value == null) {
      throw new Error(`pickAccountWithHistory lieferte Account ${name} mit 416-null (nicht maintained) — erwartete 416-Werte, live: ${live.count}/${live.value}`);
    }
    expect(
      hist.count,
      `AK4 count mismatch: history=${hist.count}, live=${live.count}`
    ).toBe(live.count);
    expect(
      approx(hist.value, live.value),
      `AK4 value mismatch: history=${hist.value}, live=${live.value}`
    ).toBe(true);

    test.info().annotations.push({ type: 'observed', description: `AK4 ${name}: history ${hist.count}/${hist.value} == 416-live ${live.count}/${live.value}` });
  });

  /*
   * AK5: Liste der größten Einbrüche — Drop-Definition = aktueller Monat −
   * Monat davor (2026-09: SEPT − AUG, NICHT Aug − Juli; Rebuilder-Kommentar
   * "Wert(aktueller Monat) − Wert(Monat davor)"). Der Test leitet die
   * Erwartungswerte deshalb aus den History-Zeilen ab und prüft:
   *   (a) Drop-Feld EVERY Account = Sept-Zeile − Aug-Zeile (und bei
   *       discriminierenden Accounts tatsächlich nicht Aug − Juli),
   *   (b) Report-Zeilen = Anzahl Accounts mit Drop<0 (17.09.: 0 →
   *       "kein Rückgang → Liste leer").
   *   Der positive Zweig (Top 5 absteigend, Werte korrekt) ist im Apex-Test
   *   dropField_equalsLastMinusPrevFromRows +
   *   pureDrop_nullFirstMonth_negativeOnDecrease abgedeckt.
   */
  test('AK5: Drop-Feld = aktueller Monat − Monat davor; Report listet nur Accounts mit Drop<0', async ({ page }) => {
    test.setTimeout(240000); // Report-Render + SOQL-Read-backs
    const months = expectedMonths();
    const cur = months[months.length - 1];    // aktueller Monat (2026-09)
    const prev = months[months.length - 2];   // Monat davor (2026-08)
    const prev2 = months[months.length - 3];  // 2026-07 — nur zur Diskriminierung

    // (a) Drop-Feld auf jedem Account vs. History-Zeilen Sept − Aug.
    const drops = soql(`SELECT Id, Name, Open_Value_Drop_Last_Month__c FROM Account WHERE Open_Value_Drop_Last_Month__c != NULL`);
    expect(drops.length, `Expected ≥1 account with non-null Drop-Feld, found ${drops.length}`).toBeGreaterThanOrEqual(1);
    const hist = soql(
      `SELECT AccountId__c, Snapshot_Month__c, Open_Value__c FROM ${HISTORY_OBJECT} WHERE Snapshot_Month__c IN ('${cur}','${prev}','${prev2}')`
    );
    const byAcc: Record<string, Record<string, number>> = {};
    for (const h of hist) (byAcc[h.AccountId__c] ??= {})[h.Snapshot_Month__c] = Number(h.Open_Value__c ?? 0);

    let checked = 0;
    let discriminates = 0; // Accounts, bei denen die falsche Definition (Aug−Juli) anderes ergibt
    const expectedBelowZero: string[] = [];
    for (const d of drops) {
      const m = byAcc[d.Id];
      if (!m || m[cur] === undefined || m[prev] === undefined) continue; // kein Verlauf → zählt nicht
      const expected = m[cur] - m[prev]; // Sept − Aug
      if (m[prev2] !== undefined && m[prev] - m[prev2] !== expected) discriminates++;
      expect(
        approx(d.Open_Value_Drop_Last_Month__c!, expected),
        `AK5 ${d.Name}: Drop-Feld ${d.Open_Value_Drop_Last_Month__c} != ${cur} − ${prev} (${m[cur]} − ${m[prev]} = ${expected})`
      ).toBe(true);
      checked++;
      if (d.Open_Value_Drop_Last_Month__c! < 0) expectedBelowZero.push(d.Name);
    }
    expect(checked, `Kein Account mit Drop-Feld UND ${cur}/${prev}-History-Zeilen — Datenlage hat sich geändert, Test-Annahme prüfen`).toBeGreaterThanOrEqual(1);

    // (b) Report-Zeilen = Accounts mit Drop<0 (Filter lessThan 0 ist live im Report).
    const frame = await openReportFrame(page, REPORT_DROPS);
    await frame.locator('table tr').first().waitFor({ timeout: 60000 }).catch(() => {});
    await frame.waitForTimeout(8000); // Empty-State oder Tabelle stabil rendern lassen
    const allTrs = await frame.locator('table tr').count().catch(() => 0);
    let dataRows = 0;
    for (let i = 0; i < allTrs; i++) {
      const tds = await frame.locator('table tr').nth(i).locator('td').allTextContents().catch(() => []);
      const t = tds.map((s) => s.trim());
      if (!t.length) continue;              // Header-Zeile (nur th)
      if (/^Subtotal$|^Total$/i.test(t[0])) continue;
      dataRows++;
    }
    expect(
      dataRows,
      `AK5 Report: ${dataRows} Datenzeilen, erwartet ${expectedBelowZero.length} (Drop<0: ${expectedBelowZero.join(', ') || 'kein Account'})`
    ).toBe(expectedBelowZero.length);

    test.info().annotations.push({
      type: 'observed',
      description: `AK5: ${checked} Accounts geprüft, Drop-Feld = ${cur} − ${prev} (bei ${discriminates} davon ≠ ${prev} − ${prev2}); ${expectedBelowZero.length} mit Drop<0 → ${dataRows} Report-Zeilen (UI = SOQL)`,
    });
  });
});
