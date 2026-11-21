import { execSync } from "child_process";

/**
 * Data preflight for E2E specs: check every acceptance criterion's data
 * precondition in ONE pass, before any UI test runs, and fail once with the
 * complete list of gaps.
 *
 * Why: in SCRUM-467 two missing preconditions surfaced one full run apart —
 * AC8's fixture was not open (run 3), and there was no open expired offer for
 * AC10 (run 6, "EXPIRED OPEN NOW: 0"). Each cost a whole 8-15 minute spec run.
 * Asked up front, both answers take seconds.
 *
 * A criterion measured against zero records does not pass, so a shortfall here
 * is a failure, never a skip.
 *
 * Usage, after the spec has seeded its fixtures:
 *
 *   import { requireData } from './preflight';
 *
 *   test.beforeAll(() => {
 *     seedFixtures();
 *     requireData([
 *       { ac: 'AC8',  what: 'an open fixture to close',
 *         soql: "SELECT Id FROM Opportunity WHERE Name = 'TEST-SCRUM-467-D1' AND IsClosed = false" },
 *       { ac: 'AC10', what: 'an open opportunity with an expired offer',
 *         soql: 'SELECT Id FROM Opportunity WHERE IsClosed = false AND Offer_Expires_On__c < TODAY' },
 *     ]);
 *   });
 */
export interface DataNeed {
  /** The criterion this precondition belongs to, e.g. 'AC10'. */
  ac: string;
  /** What must exist, in words — printed when it is missing. */
  what: string;
  /** A SOQL query whose rows are the records that satisfy it. */
  soql: string;
  /** How many rows are needed at least. Default 1. */
  min?: number;
}

/** Run a SOQL query through the sf CLI and return its row count (or the CLI's error text). */
function countRows(
  soql: string,
  targetOrg?: string
): { count: number } | { error: string } {
  const org = targetOrg ? ` --target-org ${targetOrg}` : "";
  try {
    // stderr piped separately: the sf CLI writes update warnings there (house pattern, tests/e2e/org.ts).
    const raw = execSync(
      `sf data query --query ${JSON.stringify(soql)}${org} --json`,
      {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"]
      }
    );
    const data = JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ""));
    return {
      count: data?.result?.totalSize ?? data?.result?.records?.length ?? 0
    };
  } catch (e: any) {
    // A failing query must not read as "0 rows" (house rule: an empty answer is not a finding).
    const out = String(e?.stdout || e?.message || e).replace(
      /\x1b\[[0-9;]*[a-zA-Z]/g,
      ""
    );
    let msg = out;
    try {
      msg = JSON.parse(out).message ?? out;
    } catch {
      /* keep the raw text */
    }
    return { error: msg.split("\n")[0].slice(0, 200) };
  }
}

/**
 * Check all needs, then throw ONE error naming every shortfall and every query
 * that could not run. Returns the measured counts when all needs are met, so a
 * spec can carry them into its coverage table.
 */
export function requireData(
  needs: DataNeed[],
  targetOrg = process.env.SF_TARGET_ORG
): Record<string, number> {
  const counts: Record<string, number> = {};
  const gaps: string[] = [];
  for (const need of needs) {
    const min = need.min ?? 1;
    const r = countRows(need.soql, targetOrg);
    const key = `${need.ac}: ${need.what}`;
    if ("error" in r) {
      gaps.push(`${key} — query failed: ${r.error}`);
    } else {
      counts[key] = r.count;
      if (r.count < min)
        gaps.push(`${key} — found ${r.count}, need at least ${min}`);
    }
  }
  if (gaps.length) {
    throw new Error(
      `Data preflight: ${gaps.length} of ${needs.length} precondition(s) not met — fix the fixtures, not the assertions:\n` +
        gaps.map((g) => `  - ${g}`).join("\n")
    );
  }
  return counts;
}
