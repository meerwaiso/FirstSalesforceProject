# SCRUM-468 Tester-Notizen

Hard-won facts, one line each. Read this first after every compaction.

## Fixture seed (Test-Org, 2026-11-21, TAG '[TEST-SCRUM-468]')

- Org baseline war 0 live records — Tester seeds all of it (PO comment: counts to create).
- Accounts: A=001WU00002LkYeHYAV B=001WU00002LkS94YAF C=001WU00002LkKUsYAN
- Devices: D1=a08WU00000kxdSfYAI (DEV-0008, Lent_Out, overdue 30) D2=a08WU00000kxdUHYAY (DEV-0009, Lent_Out, overdue 15) D3=a08WU00000kxdVtYAI (DEV-0010, Available) D4=a08WU00000kxXOyYAM (DEV-0011, Written_Off)
- Loans (LOAN-0007..0012): L1=a09WU00000W1ZHZYA3 (D1,A open, due 2026-10-22) L2=a09WU00000W1iJ7YAJ (D2,A open, due 2026-11-06) L3=a09WU00000W1ZarYAF (D3,A ret 2026-10-21, dur 14) L4=a09WU00000W1iRBYAZ (D3,B ret, dur 14) L5=a09WU00000W1iUPYAZ (D4,B ret, dur 25) L6=a09WU00000W1cdZYAR (D4,C ret, dur 28)
- Measured read-back: devices 4 (2 Lent_Out Overdue_Today=true overdue 30/15, 1 Available, 1 Written_Off), loans 6 (2 open, 4 returned), customers 3, colleagues U1=005WU000017tBhRYAU (Meerwais Osmani) U2=005WU000017tBpVYAU (Integration User).
- Overdue report ground truth in org right now: exactly D1(30) and D2(15).

## Guard behaviour measured over REST (LoanRecordGuard fires on create)

- Loans for ONE device must be sequential: creating a second loan while the first is open is REJECTED with "device DEV-xxxx is already on loan to ... — a device may be with exactly one customer at a time" (FIELD_CUSTOM_VALIDATION_EXCEPTION, rc=1). That is AC4 proven at REST level.
- LoanRecordGuard afterInsert fills device Current\_\* half and sets Status\_\_c=Lent_Out automatically.
- Updating Loan_Return_Datum\_\_c flips device back to Available (LoanReturnGuard).
- Setting Status\_\_c='Written_Off' via sf data update record succeeded for the CLI user (holds SCRUM468_Writeoff).
- `sf data create record -s X -v "A=1 B=2"` pairs separated by SPACES; refused create exits rc 1 with JSON error body — execSync-style callers must read stdout, not assume ids.

## CI verdict measured 2026-11-21 on PR #190 head 9f91b7b

gh pr checks 190: Lint & Format pass 48s | Metadata, Apex & Session Smoke pass 3m2s | Prod-Org Drift Gate pass 12m4s | README pass 6s — all four green ON THIS HEAD (architect/dev open item closed).

## Test budget measured before Apex run

ApexTestQueueItem rows in 24h: 255 vs ceiling 500 (max(500, 10×classes)) — room for the scoped 2-class run.

## Commands that behaved differently

- `sf data update record` exists (subcommands: bulk/record). Used -s/-i/-v.

- RECORD PAGE headless (probe468y measured): the record body renders ONLY the Related tabpanel (duplicate checker +
  standard related lists, all with (0) counts); the Details tabpanel never activates headless after the tab click
  (aria stays 5.2k, tabs render as 'tab Related [selected]' + 'tab Details' without panel). The loan Related-List sits
  in the Details sections -> a rendered row assertion on the record page is NOT reachable headless in this org.
  AC5/AC7 therefore covered at org level: relationshipLabel/Name read back from DEPLOYED metadata + live SOQL + the
  deployed ListView columns. Coverage table says so explicitly - not claimed as a browser assertion.
