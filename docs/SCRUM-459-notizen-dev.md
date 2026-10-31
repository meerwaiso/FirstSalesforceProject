# SCRUM-459 — Developer notizen (2026-10-31)

Hard-won findings for this ticket; the build spec is `docs/SCRUM-459-design.md`.

- Deploy order used: phase1 object+fields -> phase2 PSs -> phase2b list view -> phase3 handler ALONE -> phase3b triggers -> phase4 test classes. Helper-before-consumer rule (a trigger deployed with its handler in one batch compiles against the OLD live handler).
- `sf project deploy start --manifest <file>` only; `-m` misparses Field types (house).
- Validation: `sf project deploy validate` always runs tests — the org's 24 h Apex budget applies.
- Test-Org users for the PS assignment: see handoff comment (CLI user + human account).
