#!/usr/bin/env python3
# SCRUM-463 Tester: die Lifecycle eines deploy-Validation, tested against a real org.
# Run from the repo root:  tests/ci/SCRUM-463-validate-cancel.test.py
# Exit 0 only when every assertion held; every scenario prints its own evidence.
#
#   AC1  a run that is cancelled while its validation is still live cancels that
#        validation in the org (both cancel paths: the SIGTERM trap AND the
#        `if: cancelled()` step reading the id file)
#   AC3  a validation that finishes normally still produces its verdict and the
#        shape the gate parser reads — cancelling must not swallow a real verdict
#   AC4  a cancelled validation states "no verdict" and never writes a verdict
#        file, so the parser cannot read green
#   neg  a FINISHED operation must not be cancelled and its verdict file must
#        survive untouched
#
# Test-Org only, check-only validations (--source-dir points at a one-component
# fixture, so a run costs seconds, not the full force-app).
import json, os, re, subprocess, time, hashlib, sys

ROOT = os.getcwd()
SCRIPT = os.path.join(ROOT, "scripts", "ci-prod-validate.sh")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "scr463-validate")
ORG = "Test-Org"
results = []


def check(label, ok, evidence):
    results.append((label, bool(ok), evidence))
    print(("PASS " if ok else "FAIL ") + label + " :: " + evidence)


def jsonish(text):
    i = text.find("{")
    if i < 0:
        return {}
    try:
        return json.loads(text[i:])
    except Exception:
        return {}


def sf_report(job):
    """Read one deploy operation back through the Tooling API."""
    p = subprocess.run(["sf", "project", "deploy", "report", "-o", ORG, "-i", job, "--json"],
                       capture_output=True, text=True, timeout=180)
    return jsonish(p.stdout + p.stderr).get("result", {})


def report_done(job, tries=12):
    """A cancellation finishes in the org seconds after the call — poll until done."""
    rep = {}
    for _ in range(tries):
        rep = sf_report(job)
        if rep.get("done") is True:
            return rep
        time.sleep(5)
    return rep


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest() if os.path.exists(path) else "MISSING"


def validate_args(out, idfile):
    return [SCRIPT, "--org", ORG, "--source-dir", FIXTURE,
            "--test-level", "RunLocalTests", "--wait", "20", "--out", out, "--id-file", idfile]


def wait_for_id(idfile, limit=90):
    """The id must be on disk before any polling — that is what the cancel step reads."""
    for _ in range(limit):
        if os.path.getsize(idfile) if os.path.exists(idfile) else False:
            return open(idfile).read().strip()
        time.sleep(2)
    return ""


# ---------- AC3: a validation that finishes normally keeps its verdict ----------
outA = os.path.join(ROOT, "test-results", "scr463-verdict-A.json")
idA = os.path.join(ROOT, "test-results", ".ci-validate-job-id-A")
os.makedirs(os.path.join(ROOT, "test-results"), exist_ok=True)
pA = subprocess.run(validate_args(outA, idA),
                    capture_output=True, text=True, timeout=1500)
jobA = wait_for_id(idA)
dA = jsonish(open(outA).read()) if os.path.exists(outA) else {}
rA = dA.get("result", {})
cfA = (rA.get("details") or {}).get("componentFailures")
check("AC3 exit code 0 (a finished validation is green)",
      pA.returncode == 0,
      "rc=%s status=%s job=%s" % (pA.returncode, rA.get("status"), jobA))
check("AC3 verdict file written and readable JSON",
      os.path.getsize(outA) > 0 if os.path.exists(outA) else False,
      "file=%s bytes=%s" % (outA, os.path.getsize(outA) if os.path.exists(outA) else 0))
check("AC3 shape the gate parser reads (result + details.componentFailures + message)",
      "result" in dA and isinstance(cfA, list) and "message" in dA,
      "componentFailures=%s message=%r" % (cfA, dA.get("message")))
check("AC3 the finished operation was NOT cancelled",
      "cancel" not in str(rA.get("status", "none")).lower(),
      "status=%s done=%s" % (rA.get("status"), rA.get("done")))

# ---------- AC1a: the SIGTERM trap path ----------
outB = os.path.join(ROOT, "test-results", "scr463-verdict-B.json")
idB = os.path.join(ROOT, "test-results", ".ci-validate-job-id-B")
pb = subprocess.Popen(validate_args(outB, idB), stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT, text=True)
jobB = wait_for_id(idB)
pb.terminate()                      # GitHub kills the process: the trap gets TERM+EXIT
outBtxt = pb.communicate(timeout=120)[0]
rcB = pb.returncode
repB = report_done(jobB) if jobB else {}
check("AC1a trap path: the live operation was cancelled in the org",
      str(repB.get("status", "")).lower().startswith("cancel") and repB.get("done") is True,
      "job=%s status=%s done=%s deployed=%s checkOnly=%s" % (
          jobB, repB.get("status"), repB.get("done"), repB.get("numberComponentsDeployed"), repB.get("checkOnly")))
check("AC1a the script says no verdict and exits red",
      rcB == 1 and "no verdict" in outBtxt,
      "rc=%s line=%s" % (rcB, [l for l in outBtxt.splitlines() if "no verdict" in l][:1]))
check("AC1a no verdict file was written (the parser cannot read green)",
      not os.path.exists(outB),
      "out=%s exists=%s" % (outB, os.path.exists(outB)))

# ---------- AC1b: the `if: cancelled()` step reads the id file (SIGKILL: no trap) ----------
outC = os.path.join(ROOT, "test-results", "scr463-verdict-C.json")
idC = os.path.join(ROOT, "test-results", ".ci-validate-job-id-C")
pc = subprocess.Popen(validate_args(outC, idC), stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT, text=True)
jobC = wait_for_id(idC)
pc.kill()                           # killed too fast for any handler: only the id file survives
pc.wait(timeout=60)
pC = subprocess.run([SCRIPT, "--cancel", "--org", ORG, "--id-file", idC],
                    capture_output=True, text=True, timeout=300)
txtC = pC.stdout + pC.stderr
repC = report_done(jobC) if jobC else {}
check("AC1b id-file path: the live operation was cancelled in the org",
      str(repC.get("status", "")).lower().startswith("cancel") and repC.get("done") is True,
      "job=%s status=%s done=%s deployed=%s" % (jobC, repC.get("status"), repC.get("done"),
                                                repC.get("numberComponentsDeployed")))
check("AC1b the cancel step names the operation it cancelled, not the most recent one",
      jobC in txtC and "most recent" not in txtC,
      "job=%s in output; rc=%s" % (jobC, pC.returncode))
check("AC4 the cancelled run states plainly that there is no verdict",
      "no verdict" in txtC,
      "line=%s" % [l for l in txtC.splitlines() if "no verdict" in l][:1])
check("AC4 the cancelled run wrote no verdict file",
      not os.path.exists(outC),
      "out=%s exists=%s" % (outC, os.path.exists(outC)))

# ---------- negative case: a finished operation must not be cancelled ----------
idD = os.path.join(ROOT, "test-results", ".ci-validate-job-id-D")
open(idD, "w").write(jobA + "\n")
before = sha(outA)
pD = subprocess.run([SCRIPT, "--cancel", "--org", ORG, "--id-file", idD],
                    capture_output=True, text=True, timeout=300)
txtD = pD.stdout + pD.stderr
after = sha(outA)
check("negative: a finished operation is refused, not cancelled",
      "already finished" in txtD and "CannotCancelDeployError" not in txtD,
      "job=%s rc=%s line=%s" % (jobA, pD.returncode, [l for l in txtD.splitlines() if "finished" in l][:1]))
check("negative: the real verdict file survived untouched",
      before == after and before != "MISSING",
      "sha256 before=%s after=%s" % (before[:16], after[:16]))
check("negative: the cancel step wrote no verdict of its own",
      not os.path.exists(os.path.join(ROOT, "test-results", "scr463-verdict-D.json")),
      "no --out given; file absent")

print("\n--- SCRUM-463 coverage ---")
for label, ok, ev in results:
    print("%-72s %s" % (label, "PASS" if ok else "FAIL"))
failed = [r for r in results if not r[1]]
print("AC2 (never more than one live validation per PR) NOT COVERED — it needs six pushes and the"
      " workflow wiring in .github/workflows/, which the user applies; no test of mine can reach it.")
sys.exit(1 if failed else 0)
