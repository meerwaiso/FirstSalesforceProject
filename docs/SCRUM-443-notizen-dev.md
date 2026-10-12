
## SCRUM-443 (Tester-found AC6 defect, 2026-10-11)
- Defect measured by the Tester: Report Miserable_Kunde_Satisfaction rendered 0 rows org-wide;
  cause timeFrameFilter INTERVAL_LAST90 on Account.Satisfaction_Fenster_Start__c while the
  Rebuilder writes Fenster_Start = today.addMonths(-3) = 92 days back -> never matches.
- No 3-month interval token: CLI metadataRegistry lists LAST7/30/60/90/120, LASTMONTH,
  LASTWEEK, CURRENT, CUSTOM. Fix = option (a): timeFrameFilter removed from the metadata.
- Measured deploy behaviour: after `sf project deploy start --manifest manifest/scr443-report.xml`
  the org stores the platform DEFAULT placeholder `<timeFrameFilter><dateColumn>DUE_DATE
  </dateColumn><interval>INTERVAL_CUSTOM</interval></timeFrameFilter>` (read back via
  `sf project retrieve start -m "Report:Sales/Miserable_Kunde_Satisfaction" -t <dir>` + unzip).
  INTERVAL_CUSTOM without bounds = no time restriction; the LAST90 restriction is gone.
- Deploy gotcha: `sf project deploy validate --test-level RunAllTestsInOrg` (the default)
  reached an ORG-ONLY leftover class SCRUM434Probe (Id 01pWU00000Sivk1YAB, not in the repo)
  whose openCaseInRunAs_triggersMustNotBreak now hits the SCRUM-442 ValRule. CI runs
  RunLocalTests (repo only) and was green on this head. Use RunSpecifiedTests for own work.
- Report metadata deploy needs the folder-qualified member `Sales/Miserable_Kunde_Satisfaction`
  in the manifest; retrieve needs the same qualified name (`Report:...` and bare names both
  return "cannot be found").
