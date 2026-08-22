# CI-Einrichtung

Die Pipeline in `ci.yml` bildet die Merge-Gates aus `AGENTS.md` ab. Ohne das
Repository-Secret `SFDX_AUTH_URL` überspringt sie alle Org-Prüfungen und meldet
das als Warnung — sie schlägt nicht fehl, prüft dann aber auch nichts Relevantes.

## Secret einrichten (einmalig)

Die Auth-URL enthält einen Refresh-Token für die Test-Org. Sie ist ein
vollwertiges Zugangsmittel: nie committen, nie in ein Ticket, nie in einen
Chat-Verlauf.

**1. Auth-URL der Test-Org auslesen** — lokal, in einer Shell, deren Verlauf
nicht geteilt wird:

```bash
sf org display --target-org Test-Org --verbose --json
```

Im Ergebnis steht das Feld `sfdxAuthUrl`. Es beginnt mit `force://`.

**2. Als Secret hinterlegen:** GitHub → Repository → Settings → Secrets and
variables → Actions → *New repository secret*

- Name: `SFDX_AUTH_URL`
- Wert: der vollständige `force://…`-String

Danach laufen die Org-Prüfungen bei jedem Pull Request gegen `master`.

## Was die Pipeline prüft

| Job | Prüfung | Blockierend |
|---|---|---|
| `static` | ESLint, Prettier | nein — siehe unten |
| `org` | Apex-Tests (`RunLocalTests`) mit Coverage | **ja** |
| `org` | Playwright-Session-Smoke | **ja** |
| `org` | `sf project deploy validate` gegen die Test-Org | nein — siehe unten |

Berichte werden als Artefakte hochgeladen (`playwright-report`,
`apex-test-results`), nie ins Repository committet — so verlangt es AGENTS.md.

## Bewusst ausgelassen

**Die vollständige E2E-Suite läuft nicht in CI.** Sie scheitert derzeit an
Metadaten, die in der Test-Org nicht deployt sind (etwa die App „Smartphone
Management"). Eine dauerhaft rote Pipeline ist schlechter als keine, weil sie
das Gate wertlos macht. Sobald `npm run test:e2e` lokal grün ist, kann sie in
den `org`-Job aufgenommen werden.

**Die Metadaten-Validierung blockiert nicht.** Salesforce verlangt bei einem
Deployment mindestens 75 % Testabdeckung. Die Org liegt bei 37 %, und
`CasePriorityTrigger` hat gar keine Testklasse — die Arbeit an SCRUM-333 wurde
nie fertig. Sobald die Abdeckung über 75 % liegt, in `ci.yml` auf
`continue-on-error: false` stellen: Dann ist dieser Schritt das ehrliche
Pre-Deploy-Gate, weil ein Produktivdeployment genau diese Schwelle erzwingt.

**ESLint und Prettier blockieren nicht.** Beide melden Altlasten: 11
Lint-Fehler und rund 194 nicht formatierte Dateien, überwiegend unter
`force-app/`. Sie laufen mit `continue-on-error: true`, damit die Schuld
sichtbar ist, ohne jeden PR zu blockieren. Nach dem Aufräumen in `ci.yml` auf
`false` stellen.

## Branch Protection

Damit die Gates tatsächlich greifen, muss `master` geschützt werden — die
Pipeline allein blockiert nichts. GitHub → Settings → Branches → *Add rule* für
`master`:

- *Require status checks to pass before merging* → `Metadata, Apex & Session Smoke`
- *Require a pull request before merging*

Damit ist auch die Regel aus AGENTS.md erfüllt, dass niemand direkt auf
`master` merged.
