# SCRUM-449 — Developer-Notizen

Verfahrt: own worktree `scr449-wt`, Branch `feature/SCRUM-449-risk-level`.
Shared checkout sits on feature/SCRUM-424-first-response with SCRUM-424/442/445
leftovers — not mine, neither commit noch delete.

## Org-Facts (gemessen, nicht assumed)

- `sf sobject describe -s Opportunity --target-org Test-Org` → StageName picklist
  in configured order: 1 Prospecting, 2 Qualification, 3 Needs Analysis,
  4 Value Proposition, 5 Id. Decision Makers, 6 Perception Analysis,
  7 Proposal/Price Quote, 8 Negotiation/Review, 9 Closed Won, 10 Closed Lost.
  `restrictedPicklist: False`, groupable/sortable true. Early = 1–5.
- Opportunity: NO `Status`, NO `Owner` (OwnerId exists). `IsClosed` = house SoT.
- 127 Opportunities, 73 open (`SELECT COUNT() FROM Opportunity WHERE IsClosed=false`).
- `ScheduledJob` (Tooling API): 0 jobs in Test-Org today → CRON 04:00 collides with nothing.
- FieldDefinition (Tooling API): none of the six risk fields exists yet.
- CLI target-org user = `devops-agent@cline.test` (alias Test-Org).

## Decisions / deviations from the design doc

- Picklist XML: house pattern `<valueSet><valueSetDefinition>` (verified in
  `Loss_Reason__c`, `Servicebereich__c`) — the design's `<picklist><picklistValues>`
  sketch is NOT the repo's shape. Same semantics (fixed value set, no default).
- Formula `Inactive_Days__c` falls back to `LastModifiedDate` while
  `Last_User_Change__c` is still blank → AC1 measurable on legacy records
  immediately, not only after the first nightly seed.
- Apex `inactiveDays` = `Math.round((now - anchor)/86400)` — same rounding the
  formula does at scale 0, so Apex C1 and the visible number never disagree.
