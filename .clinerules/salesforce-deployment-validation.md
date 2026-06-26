## Brief overview
Projekt-spezifische Regel für Salesforce-Deployments: Vor jeder Pull-Request-Erstellung muss ein erfolgreiches Dry-Run (Validierungs-)Deployment durchgeführt werden. Kein PR, kein grünes Licht, solange die Validierung fehlschlägt.

## Pre-PR Dry Run Validation
- Vor jeder PR-Erstellung im Salesforce-Kontext zuerst ein Dry-Run-Deployment ausführen
- Befehl: `sf project deploy validate --source-dir <path>` (oder `--manifest package.xml`)
- Der Dry Run darf die Org nicht verändern — er validiert nur die Metadata
- Erst wenn der Dry Run erfolgreich ist, darf der Pull Request auf GitHub erstellt werden
- Bei Dry-Run-Fehler: Probleme beheben, dann erneut validieren — kein PR mit fehlerhafter Metadata

## Deployment Workflow (Salesforce)
1. Lokale Metadata-Änderungen commiten
2. Branch nach GitHub pushen
3. **Dry Run**: `sf project deploy validate --source-dir force-app/main/default`
4. Auf Erfolg warten → dann PR erstellen
5. Auf Fehler → fixen, neu commiten, Dry Run wiederholen
6. Erst nach grünem Dry Run: `create_pull_request` aufrufen

## Fallback bei fehlendem Dry Run
- Falls `sf project deploy validate` nicht verfügbar ist: alternativer Validierungsschritt (z.B. `sf project deploy start` auf Scratch Org) vor PR-Erstellung durchführen
- Kein PR ohne irgendeine Form von Deployment-Validierung