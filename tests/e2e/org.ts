import { execSync } from 'child_process';

/**
 * Single source of truth for the org under test.
 *
 * Dev orgs get recreated regularly, so hardcoding host names in specs makes
 * the whole suite fail with confusing "session" errors the moment a new org
 * is spun up. Resolve it from the active SFDX org instead; override with
 * SALESFORCE_URL when pointing the suite at a different org.
 */

/** Run an `sf` command and parse its JSON, stripping ANSI escape codes. */
function sfJson(command: string): any {
  // stderr is piped separately — the sf CLI writes update/deprecation
  // warnings there, which would otherwise corrupt the JSON payload.
  const raw = execSync(command, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, ''));
}

let cached: { instanceUrl: string; lightningUrl: string } | null = null;

export function resolveOrg(): { instanceUrl: string; lightningUrl: string } {
  if (cached) return cached;

  let instanceUrl = process.env.SALESFORCE_URL;

  if (!instanceUrl) {
    try {
      instanceUrl = sfJson('sf org display --json').result.instanceUrl;
    } catch (error: any) {
      throw new Error(
        `[org] Could not resolve the Salesforce org. ` +
          `Authenticate with "sf org login web", or set SALESFORCE_URL. ` +
          `Error: ${error.message || error}`
      );
    }
  }

  if (!instanceUrl) {
    throw new Error('[org] Resolved an empty instanceUrl for the default org.');
  }

  // The Lightning UI is served from a separate domain than the API/instance host.
  const lightningUrl = instanceUrl.replace('.my.salesforce.com', '.lightning.force.com');

  cached = { instanceUrl, lightningUrl };
  return cached;
}
