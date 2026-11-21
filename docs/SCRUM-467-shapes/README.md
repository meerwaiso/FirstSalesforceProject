# SCRUM-467 — verified metadata shapes

Every file under `force-app/` here passed ONE check-only deploy validation of the
whole set against Test-Org on 2026-11-21:
operation `0AfWU00000dIgjt0AC`, status **Succeeded, 13/13 components, 0 errors,
`checkOnly: true`** — nothing arrived in the org (read-back: `sf sobject describe
--sobject Opportunity --json --target-org Test-Org | grep -c 'Offer_'` → 0).

Developer duties:

1. Copy the metadata files to `force-app/main/default/…` with the same relative layout.
2. Do **not** copy `force-app/main/default/objects/Opportunity/Opportunity.object-meta.xml`
   and do **not** copy `sfdx-project.json` — the parent object file is only there so the
   CLI can resolve ValidationRules during the probe; the repo already owns the real one.
3. The Layout file is the `origin/master` layout **plus** the new "Offer validity"
   section. Diff it against the org's current layout before deploying
   (`sf project retrieve start --metadata "Layout:Opportunity.*"`), house rule: org-owned
   metadata is retrieved, not rewritten.
4. After the deploy: the Permission Set must be **assigned** (`PermissionSetAssignment`)
   to the CLI's target-org user and to the human test account, and one field must be read
   back through a real session — otherwise the feature is live but invisible and the
   symptom is a `No such column` SOQL error.

What these shapes prove (measured, see `docs/SCRUM-467-design.md` §11): a Date-typed
formula field with `+ 30` arithmetic, a Text formula with `&`/`TEXT()`, the 255-character
limits, the grouping-not-in-columns rule, `ISCHANGED(<field>)` in validation rules, and
that `PREVIOUS(<picklist>)` is rejected.
