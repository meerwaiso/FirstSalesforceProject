# SCRUM-471 — Notizen (Architect, 2026-11-22)

Hard-won findings only, each with the command that produced it. Read this first after any
compaction; the design itself lives in `docs/SCRUM-471-design.md`.

## Board state (read back, not assumed)
- SCRUM-471: status `Zu erledigen` (= column Anforderungen), assignee `architect-agent`, priority High.
- Transitions available (jira_get_transitions): 11 Zu erledigen, 21 In Bearbeitung, 31 In Überprüfung, 41 Erledigt, 3 Deployment, 7 Release.

## Repo survey
- Surveyed `origin/master` @ `f9708a9343950470aef5e6f3afa4ada43929430f` (after `git fetch origin`).
- Shared checkout sits on `feature/SCRUM-424-first-response` with foreign uncommitted files
  (SCRUM-365…424 classes, docs/SCRUM-449-design.md, SCRUM-445/467 notes). Untouched by me.
- Worktree: `git worktree add .hermes/worktrees/SCRUM-471 -b feature/SCRUM-471-key-account origin/master`.
- Repo checkout user.name = `devops-agent` → commits made with
  `git -c user.name='architect-agent' -c user.email='architect-agent@cline.de' commit`.
- Account custom fields on master: 23 files, no key-account field. Standard `Account` has 95 fields.
- House shapes read from master: `objects/Account/fields/Is_Locked__c.field-meta.xml`
  (Checkbox + `defaultValue` + type), `permissionsets/SCRUM384_AccountBlocking` (fieldPermissions
  editable/readable, no objectPermissions), `SCRUM424_FirstResponse_Read` / `SCRUM431_Wartungsvertrag_ServiceTeam`
  (read-only PS), `SCRUM442_Satisfaction_Write` (write PS), `SCRUM470PreferredContactMethodFlsTest.cls`
  (FLS negative/positive probe incl. `mkTestUser` temp-User on 'Standard User' profile).
- Layouts on master: 4 Account layouts (default 429, Sales 341, Support 325, Marketing 286 lines);
  all first sections labelled `Account Information`, `Name` at position 2. SCRUM custom fields
  only appear in the default layout; Sales/Support/Marketing carry none (0 hits of Is_Locked__/Is_Inactive__).
- Layout item house shape: `<layoutItems><behavior>Edit</behavior><field>Is_Locked__c</field></layoutItems>`.

## Test-Org measurements (all via `sf data query --target-org Test-Org`)
- `SELECT Id, Name FROM Account` → **totalSize 251**.
- `SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Account' AND (…LIKE 'Is_%' OR …LIKE '%Key%')` (`--use-tooling-api`) → 3 rows: IsDeleted, Is_Locked__c, Is_Inactive__c. `Is_Key_Account__c` free.
- `SELECT Id,Name FROM Profile` (`--use-tooling-api`) → 41 rows, all standard profiles; no Sales/Service/Team profile.
- `SELECT Id,Username,… FROM User` → 8 users; humans: `meerwais.osmani@resourceful-bear-6f1u4j.com`, `devops-agent@cline.test`.
- `SELECT MasterLabel, DeveloperName, EntityDefinitionId, Type, ManageableState FROM FlexiPage` (`--use-tooling-api`) → 9 rows: 8 UtilityBar + 1 RecordPage for `User`. **No Account RecordPage** → detail page = Classic layout sections.
- `SELECT Name, Active, SobjectType FROM AssignmentRule` → 2 rows: Standard/Case, Standard/Lead. Nothing on Account.
- `SELECT … FROM ObjectPermissions WHERE SobjectType='Account'` → 109 rows (profiles + PSes). Real columns
  (`sf sobject describe -s ObjectPermissions`): PermissionsRead/PermissionsEdit/PermissionsCreate/
  PermissionsViewAllRecords/PermissionsModifyAllRecords — there is no `EditPermission`, no `Permissions`.
- `SELECT Id,Assignee.Username,PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN (…)` →
  newest house PSes (`SCRUM442_Satisfaction_Read`/`_Write`, `SCRUM453_ContactLeft_Read`/`_Set`,
  `SCRUM428_ServiceTeam`/`_Teamleitung`, `SCRUM431_Wartungsvertrag_ServiceTeam`) are each assigned to exactly
  those 2 users; older ones (`SCRUM382_CustomerSinceDays`) to 7.
- `SELECT Id,Name FROM Group` → 45 rows: Queues `Billing`, `First Level Support`, `Technischer Support`,
  `Vertragsservice` + auto Role/RoleAndSubordinates groups (Name null) + ManagedContent roles. No Sales/Service group.

## Commands that answered nothing (wrong call, not an org finding — fixed, not escalated)
- `FieldPermissions … --use-tooling-api` → `sObject type 'FieldPermissions' is not supported` (house note).
- `SELECT … GroupMembership` → `sObject type 'GroupMembership' is not supported`;
  `FieldDefinition WHERE EntityDefinition.QualifiedApiName='SharingRule'` → 0 rows.
  ⇒ group membership and sharing rules were NOT measurable this way; no conclusion drawn from them.
- `FlexiPage`/`Group` guessed columns (`Name` on FlexiPage, `NumberOfMembers` on Group) → INVALID_FIELD.

## Decisions already taken (do not re-decide)
- Declarative only: 1 Checkbox field + 2 Permission Sets + 4 layout deltas. No Apex, no Flow, no trigger,
  no ValidationRule — Apex/Flow rejected in the ADR with reasons.
- Name `Is_Key_Account__c`, label `Key Account`, `defaultValue=false` → AC1 and AC9 covered by the platform default.
- AC5/AC7 enforced by field-level security (Read PS without edit, Set PS to the narrower group),
  proven only by the SCRUM-470-shaped Apex FLS class; the browser cannot prove it (house finding).
- No sharing/OWD change.
