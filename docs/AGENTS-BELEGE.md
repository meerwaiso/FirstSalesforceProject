# AGENTS — Belege

Die gemessenen Vorfaelle hinter den Regeln in `AGENTS.md`. Ausgelagert am
15.09.2026, weil `AGENTS.md` die Grenze `context_file_max_chars` ueberschritten
hatte und in der Mitte abgeschnitten wurde — genau dort, wo die Belege standen.

Die Regeln selbst stehen weiterhin vollstaendig in `AGENTS.md`. Hier steht nur,
**warum** es sie gibt. Wer eine Regel bezweifelt, liest hier nach.

---

## B01

*- Escalate after max. 2 self-correction attempts — never loop silently…*

Measured 06./07.09.2026: five consecutive rejections on one E2E spec (shell quoting, FORCE_COLOR, test timeout, selector, virtualization), five one-line fixes, three hours, each found only by running. The single DOM probe in round four produced more than the three runs before it. The same counter binds tool calls, not just artifacts: Hermes' repeated-failure warning is a stop sign, not a status line. On 07.09.2026 an agent ran roughly sixty commands in fifteen minutes against one question, most of them invented CLI flags — `--display`, `--class-name`, `sf org object describe` — through three of those warnings, and ended up reading the credential store. `sf apex run test --help` names the real flag in one line.

## B02

***A failed tool call is not a failed method.** When the tool you reach…*

Measured 2026-09-08 on SCRUM-401: the Developer reached five times for `sf project retrieve start`, which is exactly the command that answers "how does this org spell this metadata" in one call. All five were rejected for invented flags — `--path`, `--verbose`, `-o` twice, `--source-dir`. He then abandoned the method, guessed four spellings of one column name across eleven deployments, and finally searched the web, which the Developer SOUL forbids as a next action after a failed deploy. One `--help` would have freed all five attempts. The method was right; only the typing was wrong.

## B03

***Verifying is not delegatable.** The rule against guessing platform n…*

Measured 2026-09-14 on SCRUM-414: the design document specified `sf field rename -r` for an API-name change and added "Developer prüft `sf field rename --help`". There is no such command — `sf commands` lists `cmdt:generate:field` and `schema:generate:field`, nothing that renames anything. Worse, the sentence the command was supporting was wrong on its own terms: Salesforce offers no metadata path that changes a custom field's API name, so the claim that the rename "preserves Data und History" described an operation the platform cannot perform. Renaming the file produces a second field and leaves the first one standing with its data. The Developer spent his turn reconstructing that operation from a premise nobody had tested, and the turn hit the time cap before he could deploy. Thirty seconds of `--help` before the ADR was written would have changed the ADR.

## B04

*Measured 2026-09-10 across fourteen days and all five agents: of 16,43…*

Measured 2026-09-10 across fourteen days and all five agents: of 16,439 turns that called a tool, 9,482 — 57.7 % — also carried prose, at 323 characters each. Together that is 3,061,736 characters, which is 70 % of everything the five agents wrote as visible text. It is the largest single block of output that changes no outcome, and it is paid for twice: once to generate it, then again on every later turn that carries it in the transcript.

## B05

*Measured 2026-09-10 on SCRUM-405. The Developer and the Tester each ar…*

Measured 2026-09-10 on SCRUM-405. The Developer and the Tester each arrived at this independently; neither found it written anywhere. The Tester was stopped outright — `git checkout` refused because `docs/SCRUM-404-design.md` was still modified from a ticket cancelled the day before, next to nine untracked leftovers. He named the constraint correctly ("I must not touch those files") and had a worktree up one turn later. The Developer, earlier the same morning, did the same and also stated he would remove it: his handoff read "the worktree is cleaned", and `scr405-wt` was still standing hours later. Announcing a cleanup is not performing one — the same gap this file already names for verification.

## B06

*Measured 2026-09-13: one second after PR #101 was merged, the shared f…*

Measured 2026-09-13: one second after PR #101 was merged, the shared folder was switched to the local `master`, which was 22 commits behind `origin/master`. Nothing looked wrong. Two hours later the PO blocked the release on two findings — the list view had "no source in the repository", and the release manifest "does not exist". Both were present in `origin/master` at `71b72cb`; neither was in the folder he was reading. The DevOps agent checked the same two files against `origin/master` and named the commit, which is why his answer held and the PO's did not.

## B07

*Measured 2026-09-10: at 15:20:03 an agent concluded "the Layout doesn'…*

Measured 2026-09-10: at 15:20:03 an agent concluded "the Layout doesn't have a `<fullName>` element (layouts are named by filename)". Sixty-seven seconds later he wrote "I need the layout's real `<fullName>`" and re-ran the same failing grep. Four of his six tool calls in that window searched for an element he had already proved absent. The manifest needed the filename all along.

## B08

*Measured 2026-09-10 on SCRUM-407: a reported permission block, "even a…*

Measured 2026-09-10 on SCRUM-407: a reported permission block, "even as a System Admin", did not reproduce for the identical user on the identical org. It was a name-format failure that the CLI dressed as a permission error. Forty-four minutes passed between the report and the retraction. The fault was shared — the design doc had specified the broken call — and the diagnosis now lives in the `salesforce-deploy-diagnostics` skill.

## B09

*Measured 2026-09-12 on SCRUM-411. A FlexiPage referenced `c_betreuungs…*

Measured 2026-09-12 on SCRUM-411. A FlexiPage referenced `c_betreuungsuebergabe` for a component named `betreuungsuebergabe`, and the LWC declared `lightning__RecordAction` without the required `actionType`. Both are one-line fixes in files this team wrote. Instead four agents spent four hours, ran a deploy matrix across two orgs, concluded the org's Lightning design-time index was defective, and prepared a Salesforce Support escalation. The malformed name was quoted 183 times in messages — the doubled `c` was in every one of them. Over the same period 328 probes went to the org or the deploy engine and 65 opened a `*-meta.xml`. The org was never wrong: `AuraDefinitionBundle` was empty because the repository contains no Aura component at all.

## B10

*Measured 2026-09-12 on SCRUM-411. Four probes were run — LWC alone gre…*

Measured 2026-09-12 on SCRUM-411. Four probes were run — LWC alone green, LWC plus QuickAction red, QuickAction alone red, QuickAction real deploy red — and read as mounting proof of a broken org resolver. Every one of them fits a misspelled component reference just as well, which is what it was. The probe that separates the two was never run: deploy against a component that already resolves, or compare the name in the file with the name in the org.

## B11

*Standing on `master` is the same violation and the easier one to miss,…*

Measured 2026-09-08, on the first ticket after the repository was cleaned to a single branch: the whole of SCRUM-401 — new field, permission set, list view, build manifest — was written straight onto `master`, and a `git checkout master && git pull` was run in the middle of it. The check is one command and it is the same one: if the first line of `git status -sb` says `master`, cut the branch before you write anything.

## B12

*Measured 2026-09-07: four branches carry commits from two or three tic…*

Measured 2026-09-07: four branches carry commits from two or three tickets each — `feature/SCRUM-370-374-e2e-specs` (370, 374, 375), `feature/SCRUM-378-lead-nachfassliste` (378, 380), `feature/SCRUM-382-visibility-test` (382, 384), `feature/SCRUM-396-betreuungsstufe` (396, 398). A shared branch means one PR carries two tickets: rejecting one blocks the other, the reviewer sees changes nobody asked him to review, and neither ticket can be merged on its own.

## B13

*Measured 2026-09-14 on SCRUM-414. CI was checked at 15:00:25 — gate jo…*

Measured 2026-09-14 on SCRUM-414. CI was checked at 15:00:25 — gate job success, not skipped. The Tester pushed his locator fix at 15:01:05, which made that check stale. The gate was declared satisfied at 15:05:00. The Tester's suite went green at 15:06:09, on record nowhere. The merge happened at 15:06:44. The test report, the reassignment and the column move followed at 15:34 — twenty-eight minutes later.

## B14

*Measured 2026-09-14 on SCRUM-414: the Tester's turn was prompted at 13…*

Measured 2026-09-14 on SCRUM-414: the Tester's turn was prompted at 13:08:24 and cut at 14:38:24. His decisive evidence was in hand at 14:29 — a DOM measurement showing zero checkbox, textbox and radio controls for both fields, which is the read-only proof — and the live list view was confirmed at 14:23, the Apex run at 13:53. The spec was written at 14:34:19: 195 lines, 29 assertions, sound work. Not committed, not run, not handed off. Eighty-five minutes of evidence, five minutes of delivery.

## B15

*Measured 2026-09-07: ten of ten parent stories sat in "Erledigt" with …*

Measured 2026-09-07: ten of ten parent stories sat in "Erledigt" with an open subtask, and not one subtask had ever been worked — SCRUM-395 was created at 11:50, last touched at 11:53, zero comments; SCRUM-389 has a single changelog entry, its own creation. The handoff chain below runs on the story. A subtask leaves that chain the moment it is created, and nobody comes back for it. The container is empty: the design doc already carries the specification it was invented to hold.

## B16

***A commit on your own disk is not a handoff.** Push before you announ…*

Measured 2026-09-08: the Architect wrote the SCRUM-401 design, committed it, commented in Jira, re-assigned and pinged the Developer — and never pushed. `f1a7789` existed on one disk. This rule has lived in the Developer's SOUL for weeks under "Push Before You Hand Off"; it belongs to all five.

## B17

*Measured 2026-09-08 on SCRUM-402: the Developer deployed to the Test-O…*

Measured 2026-09-08 on SCRUM-402: the Developer deployed to the Test-Org, verified the counts, honestly reported one acceptance criterion as unfinished — and kept the branch local, reasoning that the PR should carry the final green state. His repository copy of the list view carried column names his own dry run had already rejected; the deployed org copy carried different ones. Nothing in his workflow compares those two. A diff does.

## B18

*A handoff has two halves, and only the tracker counts…*

Measured 12.–15.09.2026, turns against ticket lookups:

    Tester      40 turns,  40 lookups   100 %
    Architect   45 turns,  40 lookups    89 %
    Developer   57 turns,  35 lookups    61 %
    DevOps      53 turns,  20 lookups    38 %
    PO          48 turns,  10 lookups    21 %

The two ends of the chain are the thin ones, and each drops a different half. Across the whole history the DevOps made six column moves and one field update: he moves tickets without renaming them. The PO made six field updates and one column move: he renames without moving.

On 2026-09-15 both halves failed within the same hour. The PO posted a complete acceptance for SCRUM-416 and left the ticket in "Erledigt" on his own name. The DevOps then deployed three times to the production org against a ticket that was neither in "Release" nor assigned to him — he had read the room message, not the ticket. Neither had to guess: both states are one call away.

## B19

*Release tags are `release/YYYY-MM-DD-SCRUM-NNN`…*

Measured 2026-09-15 on SCRUM-416. The DevOps looked for a tag convention, found 33 tags in the repository and every one of them beginning with `archiv/` or `archive/`, and concluded that was the convention. He tagged the production release `archiv/release-SCRUM-416-offene-chancen`.

The reasoning was right and the answer was wrong. Those 33 tags are gravestones for deleted branches — `archiv/feature-SCRUM-399-eskalationsstufe-fix`, `archive/wip-uncommitted-2026-08-22` — not releases. Not one release had ever been tagged, SCRUM-414 of the previous day included, so there was nothing else to recognise. He was reading a convention off an empty set.

`release/` separates the two kinds, and the leading date sorts chronologically on its own; under the old shape SCRUM-416 would have filed itself between 396 and 399.
