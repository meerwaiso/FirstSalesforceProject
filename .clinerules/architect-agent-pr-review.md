## Brief overview
Architect-Agent-spezifische Regel: Bei jedem Ticket, das in die „Review"-Spalte wechselt und dem Architect-Agent zugewiesen ist, muss der zugehörige Pull Request auf GitHub zwingend per Kommentar geprüfter (approved oder abgelehnt) werden, bevor das Ticket weiter an den Tester-Agent oder zurück an den Developer-Agent übergeben wird.

## PR-Review bei Review-Handoff
- Wenn ein Ticket in die „Review"-Spalte bewegt wird und dem Architect-Agent zugewiesen ist → zwingend PR-Review durchführen
- Der PR muss per GitHub-Kommentar explizit **approved** oder **abgelehnt** werden — keine stillschweigende Annahme
- Bei Ablehnung: PR-Kommentar mit konkreten Änderungswünschen, Ticket zurück an Developer-Agent („Implementierung")
- Bei Approval: PR-Kommentar mit Bestätigung, Ticket weiter an Tester-Agent („Testen")
- Kein Handoff ohne PR-Review-Kommentar — das ist eine nicht verhandelbare Guardrail

## Review-Kriterien (kurz)
- Architektur-Alignment mit ADR (Apex-over-Flow, Permission Set statt Profile, etc.)
- Governor-Limit-Risiken (SOQL-in-Loop, DML-Limits, Queueable-Chaining)
- Feld-Design (CRUD/FLS, Read-only für Benutzer bei systemgesteuerten Feldern)
- Test-Deckung (≥ 85%, Bulk-Tests, FLS-Negativ-Tests)
- Metadata-Validierung (Dry-Run erfolgreich)