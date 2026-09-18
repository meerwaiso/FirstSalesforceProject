#!/usr/bin/env python3
import re, subprocess

ORG = "devops-agent@cline.test"

def run(cmd, t=180):
    r = subprocess.run(["bash", "-c", "FORCE_COLOR=0 NO_COLOR=1 " + cmd],
                       capture_output=True, text=True, timeout=t)
    return r.stdout + r.stderr

raw = run("sf apex log get -i 07LWU00000Pbwhl2AB -o " + ORG + " 2>&1")
raw = re.sub(r"\x1b\[[0-9;]*m", "", raw)
lines = raw.splitlines()

# Walk log: group into execution contexts by EXECUTION_STARTED
# Each trigger fire = CODE_UNIT_STARTED line mentioning CaseReactionTrigger
# Each DB read   = SOQL_EXECUTE_BEGIN SELECT ... Reactivation_Count__c
# Count per "outer" execution (top-level EXECUTION_STARTED that is not nested deeper).
# Simpler: count totals + the number of AfterUpdate fire events.
n_exec    = 0
n_trig    = 0
n_sooql   = 0
n_dml_upd = 0
fire_times = []
sqq_times  = []
for ln in lines:
    m = re.match(r"(\S+\s\S+)\|\|?(\d+)\|\|?EXECUTION_STARTED", ln)
    if "EXECUTION_STARTED" in ln:
        n_exec += 1
    if "CaseReactionTrigger" in ln and "CODE_UNIT_STARTED" in ln and "AfterUpdate" in ln:
        n_trig += 1
        fire_times.append(re.findall(r"^([\d:.]+)", ln))
    if "SOQL_EXECUTE_BEGIN" in ln and "Reactivation_Count__c" in ln:
        n_sooql += 1
    if "DML_BEGIN" in ln and "Case" in ln and "UPDATE" in ln.upper():
        n_dml_upd += 1

print("EXECUTION_STARTED total :", n_exec)
print("CaseReactionTrigger AfterUpdate fires:", n_trig)
print("DB reads of Reactivation_Count__c   :", n_sooql)
print("Case UPDATE DML blocks              :", n_dml_upd)
print("fire@:", [t[0] for t in fire_times])
