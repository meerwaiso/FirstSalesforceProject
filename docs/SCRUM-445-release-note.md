## 14.10.2026 — Gross Discounts need the Manager's Approval before a Deal is won (SCRUM-445)

**Was sich aendert**

- Every opportunity now carries the **discount offered to the customer, in percent**.
  You type it in once; it is shown on the deal and every colleague in sales can see it.
- **Up to and including 15 %** nothing changes for you: you close the deal as won on your own.
- **Above 15 %** the deal can no longer be closed as won. Your **direct manager** gets an
  approval request — no separate email from you, the manager is informed on the record itself.
  Once the manager approved, closing as won works.
- **Above 25 % is refused outright** — even an approval does not open the way. A discount that
  high never reaches the customer.
- A manager who **rejects** has to give a short reason. The deal stays blocked, and you see
  who decided, when, and why — so you can renegotiate with the customer.
- **Raise the discount after an approval and the approval no longer counts** — a new one is
  requested. **Lower it and the approval still counts**, nobody has to approve again.
- Sales management sees **all deals currently waiting for an approval, with how long each has
  been waiting** (counted from the moment the approval was requested). An approval that sits
  around for days is visible as such.
- Only **you (the owner) and sales management may change the discount**; every other colleague
  can look but not touch.

**Wo man es sieht**

- On the deal itself: a "Discount Approval" section on the detail page — discount in %,
  approval state, waiting time, decision and reason.
- In the list **"Discount Approval Waiting"** on the Opportunities tab: everything waiting,
  with the waiting time.

**What is deliberately NOT in here**

- Deals that are **already won or lost were not touched** — no discount, no approval state
  on them. The rule applies to everything that gets closed from now on.
- There is no renegotiation screen beyond showing the decision and the reason — you talk to
  the customer yourself.
- The discount is a percentage of the deal. Absolute amounts and price calculations stay as
  they are.

**Beleg (Prod-Org, read back by the PO on 14.10.2026)**

- Release tag `release/2026-10-14-SCRUM-445` (tag object `36e78bc`, target `0d5a379`, parent
  = squash merge `2696e6c` of PR #166).
- 8 of 8 Opportunity fields present in Prod (`FieldDefinition` query): `Discount_in_Pct__c`,
  `Discount_Approval__c`, `Approval_Requested_On__c`, `Approval_Decided_On__c`,
  `Approval_Decided_By__c`, `Approved_Discount_Value__c`, `Rejection_Reason__c`,
  `Approval_Waiting_Days__c`.
- 7 Permission Sets exist in Prod, **all 7 assigned to both Prod users** (14 assignment rows,
  queried by PS name) — the feature is not only deployed, it is reachable.
- `Discount_Approval__c` is editable **only** via `SCRUM445_Discount_Manager`; the read-only
  set grants viewing — a sales rep cannot set "Approved" themselves.
- Deploy jobs: phase 1 `scr445-phase1-fields.xml`, phase 2 `scr445-phase2-referencing.xml`
  (12 components), `scr445-systemps.xml`, `scr445-rework-446-447.xml`, phase 3 test classes.
- **Open item, not part of this release:** SCRUM-448 — 6 Apex test methods still carry
  Test-Org usernames and fail in Prod, which keeps the Prod-Org Drift Gate red. The feature
  itself is live and permission-verified; the gate re-greens when SCRUM-448 is fixed.
