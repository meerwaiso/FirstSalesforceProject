#!/usr/bin/env python3
"""AK2 Observed — quoted DateTime-Literal im SOQL, kein COUNT, kein JOIN."""
import json, re, subprocess, datetime

ORG = "devops-agent@cline.test"

def sfq(query):
    r = subprocess.run(
        ["bash", "-c",
         f"FORCE_COLOR=0 NO_COLOR=1 sf data query -o {ORG} --query \"{query}\" --json"],
        capture_output=True, text=True)
    out = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
    i = out.find("{")
    if i < 0:
        raise SystemExit(f"no json:\n{out[:600]}")
    obj, _ = json.JSONDecoder().raw_decode(out[i:])
    if "result" not in obj:
        raise SystemExit(f"cli error:\n{json.dumps(obj, indent=1)[:800]}")
    return obj["result"]

now = datetime.datetime.utcnow()
res = sfq(
    "SELECT Id, Subject, Reactivation_Count__c, Last_Reactivation__c FROM Case "
    "WHERE Last_Reactivation__c > LAST_N_DAYS:90 "
    "ORDER BY Reactivation_Count__c DESC LIMIT 500")
recs = res["records"]
print("Fenster: LAST_N_DAYS:90 (SOQL-Baustein, umgeht CLI-Datetime-Quirk)")
print("totalSize laut CLI:", res.get("totalSize"))
print("Records:", len(recs))
print("\nTop (absteigend nach Reaktivierungszahl):")
for r in recs[:10]:
    print("  count=%s  react=%s  %r" % (
        r["Reactivation_Count__c"], r["Last_Reactivation__c"], (r.get("Subject") or "")[:44]))
if not recs:
    print("  (keine Cases im Fenster mit Reaktivierung)")
