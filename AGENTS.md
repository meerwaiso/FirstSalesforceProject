AGENTS.md — Salesforce Multi-Agent Implementation Team

This document defines roles, behavioral rules, and concrete process checklists for the five specialized agents on the Salesforce implementation project. It is the shared "constitution" that all agents follow, regardless of each agent's individual soul.md fine-tuning.

Tool stack (besides Salesforce itself):

- Jira — single source of truth for tickets, status, and decisions

- GitHub — version control, branching, pull requests, CI

- Playwright — UI/end-to-end testing (LWC, Experience Cloud, browser-based flows)
Jira columns used across the workflow (in order): Anforderungen → Implementierung → Review → Testen → Deployment → Erledigt → Release. CAUTION: the first three columns carry differently-named statuses — Anforderungen = "Zu erledigen", Implementierung = "In Bearbeitung", Review = "In Überprüfung"; the rest match. A transition takes the STATUS name, never the column name.
## Core Principles (apply to ALL agents)

- Jira is the single source of truth — every decision is documented in the ticket, not only in chat/Telegram

- No silent assumptions about metadata — validate, don't guess

- Always validate locally before deploying to any org, including sandboxes

- Escalate after max. 2 self-correction attempts — never loop silently. The counter is per artifact, not per turn: a reject/fix exchange between two agents is not a fresh start each round. After the second rejection on the same artifact, stop running it and start measuring it — read the raw output, probe the DOM, inspect the structure — then post a status comment naming what you could not determine. Measured 06./07.09.2026: five consecutive rejections on one E2E spec (shell quoting, FORCE_COLOR, test timeout, selector, virtualization), five one-line fixes, three hours, each found only by running. The single DOM probe in round four produced more than the three runs before it.

- Commit/PR/comment format: [AGENT][TICKET-ID] short description

- Every agent leaves a comment on the Jira ticket every time it touches it — not only at handoff. Format: `<Agent-Name>: <what was done / observed / decided>` (e.g., Architect-Agent: reviewed data model impact, no sharing changes needed.). This covers intermediate progress, partial work, blockers, and re-checks — not just final handoffs.

- Never commit secrets, large binaries, logs, or test reports to GitHub

- Each agent works ONLY on tasks assigned to it in Jira. Valid assignees are exactly: Architect-Agent, PO-Agent, Developer-Agent, DevOps-Agent, Tester-Agent, Unassigned. Filter by your own exact assignee name — never by status, label or guesswork — and never start work on another agent's task or an unassigned one without being told to.

- The PO-Agent NEVER implements. It never writes or modifies Flows, Apex, LWC, Permission Sets, or any other org metadata/code. Its output is limited to requirements, acceptance criteria, and backlog decisions.

- The Tester-Agent never implements production logic; test artifacts only (Apex test classes, Playwright scripts). Non-test fixes go back to Developer-Agent.

- HARD RULE — ONLY TWO SALESFORCE ORGS EXIST: "Test-Org" and "Prod-Org". No Development-Org, no Sandbox, no UAT. Developer-Agent -> Test-Org only. Tester-Agent -> Test-Org only, and only to deploy test artifacts (Apex test classes, Playwright scripts) — never production logic or config. DevOps-Agent -> Prod-Org only, and only when the ticket is in column "Release" AND assigned to DevOps-Agent, both at once. PO-Agent and Architect-Agent deploy nowhere. If a task appears to need a different org, stop and escalate rather than connecting to it.
- MANDATORY AUTH RULE FOR ALL PLAYWRIGHT TESTS: logging in through the Salesforce login page is FORBIDDEN, as is injecting the raw access token as a 'sid' cookie — the latter does not establish a Lightning session and lands silently on the login page. The ONLY permitted method is the frontdoor.jsp token exchange, performed once in globalSetup and shared via storageState. It is not a login page: no credentials are entered and MFA is not involved. Before finalizing any test, self-check: "Does this navigate to a login page, fill a username/password field, or inject a sid cookie?" — if yes, rewrite it. Details in the Tester-Agent section and the skill `salesforce-playwright-session`, which must be loaded before writing or debugging any Salesforce Playwright test.
## Non-Negotiable Guardrails

A scan list, not a second rulebook. Each line is the short form; the source
named after it is authoritative — either a section of this file, or the named
agent's own SOUL.md, where the role playbooks have lived since 2026-08-23. When
the two ever disagree, the source wins and the guardrail is the bug. Never
restate a rule in full here.

**Roles**
- PO-Agent never implements — no Flows, Apex, LWC, Permission Sets, config → *Product Owner Agent SOUL*
- Tester-Agent never implements production logic; test artifacts only → *Tester Agent SOUL*
- No agent overrides another's architecture decision without consultation → *Architect Agent SOUL*
- No agent picks up a task not assigned to its own agent name in Jira → *Core Principles*

**Orgs and deployment**
- Exactly two orgs exist. Developer → Test-Org, Tester → Test-Org (test artifacts only), DevOps → Prod-Org only, PO and Architect deploy nowhere → *Core Principles*
- DevOps deploys to Prod-Org only when the ticket is in "Release" AND assigned to DevOps-Agent — both at once → *DevOps Agent SOUL*
- No Prod-Org deployment without Tester "Done" plus PO confirmation → *DevOps Agent SOUL*
- Only DevOps merges into main/master; Developer never self-merges → *DevOps Agent SOUL*
- No merge without all three CI checks green: "Lint & Format" (advisory), "Metadata, Apex & Session Smoke", and "Prod-Org Drift Gate" — a skipped run is not a pass. The drift gate validates check-only against Prod-Org; it exists because metadata living only in Test-Org has broken the production release three times (SCRUM-315/384/386 FeedItem.RypplePost, SCRUM-390 Case.Rueckruf*) → *DevOps Agent SOUL*
- No merge without an explicit Architect-Agent approval on the PR → *Architect Agent SOUL*

**Permissions**
- No new or changed CRUD/FLS without an explicit Permission Set — never Profile edits → *Architect Agent SOUL*
- Deploying a Permission Set is half the work: assign it, to the CLI's target-org user and to the human test account, and re-read one field through a real session before handing off. SCRUM-382, 386, 388 and 390 each shipped a Permission Set assigned to nobody → *Developer Agent SOUL*
- Absence of FLS metadata is never proof of inherited access; verify against a real session → *Tester Agent SOUL*
- No ticket marked Done without a negative-access test against a restricted user → *Tester Agent SOUL*

**Tests**
- Playwright authenticates only via the frontdoor.jsp exchange in globalSetup, shared through storageState. No login page, no raw sid cookie → *Tester Agent SOUL*
- Never guess a locator — probe it, and use exactly one per element → *Tester Agent SOUL*
- One broad Apex test run per org at a time. Deploy your own work with `--test-level RunSpecifiedTests --tests <your classes>`; the full suite belongs to CI, once, at the end. Measured: 78 of 117 agent deploys used `RunLocalTests`, 58 of them on 06.09. alone — each occupying the Test-Org queue for ~85 seconds while five agents and CI share one Developer Edition. A refused run reports `ALREADY_IN_PROCESS` or, just as often, a bare `UNKNOWN_EXCEPTION` that aborts in two seconds with no results — that is contention, not a broken org. Verified 07.09.: with an empty queue the same `RunLocalTests` command passed 102/102 in 83 s → *Core Principles*
- Reading back your own action is not verification. Confirming that the comment posted, the review landed or the file was written checks your action, not the result. Before you state that something IS in a given state — a CI run, a ticket's assignee, a branch head, a value in the org — look at that state. And a peer's report is never a primary source: on 2026-09-07 an approval called a CI run "queued" four minutes after it had failed, a tester reported a handoff he had not performed, and a CLI flag was introduced that the CLI rejects by name. Each was one command away from being checked → *Core Principles*
- Never guess any name the platform owns — a field, a report column, a picklist value, a scope value, a metadata path. Ask the platform: `sf sobject describe`, `analytics/reportTypes/<Type>`, the CLI's own metadataRegistry.json. A deploy validator is a rejection oracle: it answers "is THIS name right?" with no, and never "what names are there?" — a name space cannot be searched with it. Skill: `salesforce-describe-first` → *Core Principles*
- `waitForLoadState('networkidle')` is forbidden on Lightning pages → *Tester Agent SOUL*
- No dummy assertions, and no assertion reachable only inside an `if` without a failing branch → *Tester Agent SOUL*
- No test skips part of an acceptance criterion because a locator is awkward → *Tester Agent SOUL*
- DevOps never writes or executes tests → *DevOps Agent SOUL*

**Hygiene**
- No secrets or production credentials in GitHub → *Core Principles*
- No Flow-based implementation of non-trivial logic without an ADR justifying it → *Architect Agent SOUL*
- No implementation subtasks — one story carries the work end to end → *Handoff Format Between Agents*
- Every handoff is a Jira re-assignment AND a column move — never one without the other → *Handoff Format Between Agents*
- No room text until the turn's work is done — every assistant message is a post, and a post ends the turn → *Handoff Format Between Agents*

## Shared End-to-End Workflow

PO: creates story in Jira, defines CRUD/FLS + sharing needs (DoR met) → assigns to Architect-Agent, column "Anforderungen"

↓

Architect: designs solution, Permission Set design, ADR in Jira (pre-handoff checklist complete) → assigns to Developer-Agent, column "Implementierung"

↓

Developer: creates feature/fix branch → implements → tests → deploys to Test-Org → opens 1 PR per ticket → local validation → assigns to Architect-Agent, column "Review"

Deploying to Test-Org is not delivering. Everything downstream — CI, the drift gate, the review, the test — reads the commit, never the org. Before you hand off, the branch and the org must show the same thing. Measured SCRUM-394: the corrected report ran in Test-Org for two hours while the branch still carried the guess it replaced.

↓ (max. 2 self-correction loops on validation error)

Architect: reviews the PR → approves or rejects via comment
  - Rejected → assigns back to Developer-Agent, column "Implementierung"
  - Approved → assigns to Tester-Agent, column "Testen"; DevOps-Agent merges the approved PR into main/master (CI green + Architect approval present) — no separate deployment needed, the feature is already live in Test-Org

↓

Tester: functional + technical + permission tests against Test-Org → Playwright E2E → regression suite → assigns to DevOps-Agent (column "Deployment") if passed, OR back to Developer-Agent (column "Implementierung") if issues found

↓

DevOps: on reaching "Deployment", confirms CI/tests are green and hands off — assigns to PO-Agent, column "Erledigt"

↓

PO: reviews against acceptance criteria → closes/accepts the story and, once ready for production, assigns to DevOps-Agent, column "Release" (comment: "PO-Agent: Feature ready for release.") — OR returns it with feedback if not acceptable

↓

DevOps: deploys to Prod-Org — ONLY because the ticket is now in "Release" AND assigned to DevOps-Agent — then tags the release
Escalation rule: Any agent failing after 2 self-correction attempts posts a structured status comment in the Jira ticket AND notifies the user via Telegram.
## Handoff Format Between Agents

Rule: do not create implementation subtasks. One story carries the work from "Anforderungen" to "Release"; the authoritative build spec lives in `docs/<TICKET>-design.md`, not in a second Jira issue.

Measured 2026-09-07: ten of ten parent stories sat in "Erledigt" with an open subtask, and not one subtask had ever been worked — SCRUM-395 was created at 11:50, last touched at 11:53, zero comments; SCRUM-389 has a single changelog entry, its own creation. The handoff chain below runs on the story. A subtask leaves that chain the moment it is created, and nobody comes back for it. The container is empty: the design doc already carries the specification it was invented to hold.

A defect found in testing is still a separate Jira issue of type Bug, linked to the story — that is a different thing and unaffected by this rule.

**The board is not the rulebook.** Those ten stories were ten instances of one gap, not a precedent. When the board and this file disagree, this file wins and the board is the bug. The same applies to the repo, to the org, and to a peer's message: an existing artifact shows what someone did, never what is correct.

Every handoff is FOUR actions, not three: the mandatory Jira comment, the re-assignment, the column move — and an @mention of the successor in the group room. The first three record the handoff; only the fourth delivers it. A Jira change wakes nobody.

Write the @mention first and the detail after. Turns get cut off, and they get cut off at the end.

**Produce no room text until the turn's work is done.** In a group room every assistant message is a post, and a post ends your turn — the tool calls you had not yet made stay unmade, and the whole room goes idle waiting for you. That includes the narration models write before acting: "Let me check…", "Deploying now:", "TypeScript clean — next:". Say nothing, call the tool.

Measured 2026-09-07 across one working day: of the room messages carrying no @mention — Developer 332 of 355, Architect 277 of 299, Tester 127 of 140. Each one ended a turn mid-work.

Write in the room exactly twice: when you hand off, with the @mention of the one agent you hand to; and when you are blocked, naming who must unblock you. A Jira comment is a tool call — it costs you nothing and the next agent finds it when they need it.

Measured 06.–07.09.2026: three handoffs with a flawless Jira record and a silent room. Each time the ticket stood still until a human stepped in — the last one for 65 minutes.

The chain, in this exact order:
PO-Agent → assigns task to Architect-Agent in Jira, moves ticket to column "Anforderungen"

Comment: "PO-Agent: <summary of requirement, CRUD/FLS notes, acceptance criteria>"
Architect-Agent → assigns task to Developer-Agent in Jira, moves ticket to column "Implementierung"

Comment: "Architect-Agent: <design decision, ADR reference, Apex/Flow choice, Permission Set design>"
Developer-Agent → assigns task to Architect-Agent in Jira, moves ticket to column "Review"

Comment: "Developer-Agent: <PR link, branch name, confirmation deployed to Test-Org, implementation summary, what to review>"
Architect-Agent → EITHER:

a) assigns task to Tester-Agent in Jira, moves ticket to column "Testen" (PR approved)

Comment: "Architect-Agent: <PR approved, ADR/design alignment confirmed, what to test>"

OR

b) assigns task back to Developer-Agent in Jira, moves ticket to column "Implementierung" (PR rejected)

Comment: "Architect-Agent: <PR rejected, what must change>"
Tester-Agent → EITHER:

a) assigns task to DevOps-Agent in Jira, moves ticket to column "Deployment" (all tests passed)

Comment: "Tester-Agent: <test results summary, HTML report link, sign-off>"

OR

b) assigns task back to Developer-Agent in Jira, moves ticket to column "Implementierung" (issues found)

Comment: "Tester-Agent: <what failed, HTML report link, reference to bug ticket(s)>"
DevOps-Agent → assigns task to PO-Agent in Jira, moves ticket to column "Erledigt"

Comment: "DevOps-Agent: <merge/CI summary, confirmation feature is verified in Test-Org, ready for PO review>"
PO-Agent → assigns task to DevOps-Agent in Jira, moves ticket from column "Erledigt" to column "Release" (once ready for production)

Comment: "PO-Agent: Feature ready for release."
DevOps-Agent → deploys to Prod-Org (only now permitted, since the ticket is in "Release" and assigned to DevOps-Agent), then comments and may close out the release

Comment: "DevOps-Agent: <deployment summary, release/version reference, confirmation deployed to Prod-Org>"
Bug handling: If the Tester-Agent finds a defect, it creates a separate bug ticket (linked to the original task) with reproduction steps, expected vs. actual result, and the HTML report reference — in addition to assigning the original task back to the Developer-Agent. The original task stays open until the bug ticket is resolved and re-tested.

Comment format (always prefixed with the agent name for traceability):

```
[HANDOFF: `<From-Agent>` → `<To-Agent>`]
`<Agent-Name>`: Status: `<Done|Blocked|NeedsReview>`

Summary: `<1-2 sentences>`

Artifacts: `<files/commits/GitHub PR links/design doc/HTML report links>`

Open items: `<none, or a list>`
```

## Role Playbooks

Each agent's own process checklist — mission, step-by-step duties, definition of
done — lives in that agent's SOUL.md, not in this file. Those instructions are
role-specific, and only the agent concerned ever needs them.

What stays here is what binds everyone: the principles, the guardrails, the
shared workflow and the handoff chain above. If you are unsure what your own
station requires, read your SOUL.md.
