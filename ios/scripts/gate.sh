#!/usr/bin/env bash
# The gate: everything that can FAIL, and nothing that cannot -- on four
# simulators at once.
#
# The sweeps (VisualSweep, DesignerSweep, RowShot, InkShot, InkZoomShot) carry
# no assertions about the product -- they photograph the app for a human to look
# at. Measured across twelve gate logs they were 43.6 of the gate's 76 minutes,
# and nine of its ten most expensive tests. A screenshot cannot fail a build, so
# paying for it on every run buys nothing.
#
# PerfSweep is skipped for the same reason: it MEASURES. There is no agreed
# latency budget for it to assert against, and inventing one to make it a gate
# would be inventing a requirement.
#
# RenderShot and ReorgShot are NOT sweeps and are NOT skipped: they photograph
# too, but they also assert -- three and six assertions -- so they can fail.
#
# They are NOT deleted and NOT unrunnable. To take a set of sweeps:
#   xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
#     -destination "$DEST" -only-testing:ScorangerUITests/VisualSweep
#
# WHY THE SHARDING IS DONE HERE rather than with -parallel-testing-enabled:
# xcodebuild's own parallel testing distributes test CLASSES. Eighty-one of the
# suite's eighty-eight tests are in ONE class, so it would hand one worker the
# whole gate and three workers a minute of work each. This enumerates test
# METHODS and deals them out, which is the only split that balances.
#
# THE HAZARD IT IS BUILT AROUND: two xcodebuild runs against the SAME simulator
# collide, execute zero tests, and report success. Every worker therefore gets
# its own device, created here and reused by name, and the run FAILS unless the
# number of tests that actually executed equals the number enumerated.
#
# THE SECOND HAZARD, found by using it: four workers make the host slower than
# any test author measured against, and a UI test that waits a wall-clock
# budget ACROSS AN ENGINE CALL then measures the machine rather than the app.
# testAnArrangementWithNoVersionsSaysSoAndCanBeDeleted waited 40s for a row to
# go after a delete: 25s solo, past 40s under four workers. It cost two release
# gates.
#
# The rule, and it is the test's job, not the gate's: never spend a wall-clock
# budget across an engine call. Wait on the signal the app RAISES when the work
# returned -- the undo bar after a delete, a save button going away -- and give
# only the redraw after it a short fixed budget. See waitForDeleteToLand.
#
# Release gates run sharded, like this one. Serial is not the safer option it
# looks like: the 0.6.4 release gate died serially, killed by other work on the
# host, so what makes a gate trustworthy is a QUIET machine and tests that do
# not race -- not one worker. And a test that only passes solo is a broken test
# whichever way the gate is run; serial would hide it until CI or a slower Mac
# found it again.
#
# Usage:
#   scripts/gate.sh                    # 4 workers
#   scripts/gate.sh -j 6               # 6 workers
#   scripts/gate.sh --serial [udid]    # one simulator, the old behaviour
#   scripts/gate.sh -- -only-testing:ScorangerUITests/StateReset
set -euo pipefail
cd "$(dirname "$0")/.."

WORKERS="${GATE_WORKERS:-4}"
SERIAL=""
SERIAL_UDID=""
EXTRA=()
while (( $# )); do
  case "$1" in
    -j|--jobs)  WORKERS="$2"; shift 2 ;;
    --serial)   SERIAL=1; shift
                if [[ $# -gt 0 && "$1" != -* ]]; then SERIAL_UDID="$1"; shift; fi ;;
    --)         shift; EXTRA=("$@"); break ;;
    *)          EXTRA+=("$1"); shift ;;
  esac
done

PROJECT=Scoranger.xcodeproj
SCHEME=Scoranger
DD=DerivedData-Gate
OUT="${GATE_OUT:-$PWD/build/gate}"
SKIP=(
  -skip-testing:ScorangerUITests/VisualSweep
  -skip-testing:ScorangerUITests/DesignerSweep
  -skip-testing:ScorangerUITests/RowShot
  -skip-testing:ScorangerUITests/InkShot
  -skip-testing:ScorangerUITests/InkZoomShot
  -skip-testing:ScorangerUITests/PerfSweep
  # TopBarShot photographs the bar before and after a change for a human to
  # compare, and one of its two shots wants an OMR service on 127.0.0.1 that a
  # gate has no reason to be running. Neither asserts.
  -skip-testing:ScorangerUITests/TopBarShot
)

DEVTYPE="${GATE_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB}"
RUNTIME=$(xcrun simctl list runtimes -j \
  | python3 -c 'import json,sys; rs=[r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]]; print(sorted(rs, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')

# A simulator per worker, made once and kept. Named, so a second gate on the
# same machine reuses these rather than piling up clones -- and so it never
# borrows the device somebody is watching a release run on.
sim_for() {
  local name="scoranger-gate-$1" udid
  udid=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for _, ds in json.load(sys.stdin)['devices'].items():
    for d in ds:
        if d['name'] == '$name' and d.get('isAvailable'):
            print(d['udid']); raise SystemExit
")
  [[ -n "$udid" ]] || udid=$(xcrun simctl create "$name" "$DEVTYPE" "$RUNTIME")
  echo "$udid"
}

rm -rf "$OUT"; mkdir -p "$OUT"

if [[ -n "$SERIAL" ]]; then
  # A BARE --serial used to resolve `name=iPad Pro 11-inch (M5)`, and on a
  # machine where that name matches exactly one device it took whichever
  # simulator a release gate was already using. Two runs on one simulator kill
  # each other: the second dies with "Test crashed with signal kill before
  # establishing connection" and silently records a fraction of its tests. So
  # --serial now uses a gate-owned simulator of its own unless told otherwise,
  # and the release simulator is never taken by accident.
  DEST="platform=iOS Simulator,id=$(sim_for serial)"
  [[ -n "$SERIAL_UDID" ]] && DEST="platform=iOS Simulator,id=$SERIAL_UDID"
  exec xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
    "${SKIP[@]}" ${EXTRA+"${EXTRA[@]}"}
fi

echo "==> building once for $WORKERS workers"
BUILD_SIM=$(sim_for 1)
xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$BUILD_SIM" -derivedDataPath "$DD" \
  > "$OUT/build.log" 2>&1 \
  || { echo "BUILD FAILED — $OUT/build.log"; tail -40 "$OUT/build.log"; exit 1; }

XCTESTRUN=$(ls -t "$DD"/Build/Products/*.xctestrun | head -1)
echo "    $XCTESTRUN"

echo "==> enumerating"
xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
  -destination "platform=iOS Simulator,id=$BUILD_SIM" \
  "${SKIP[@]}" ${EXTRA+"${EXTRA[@]}"} \
  -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
  -test-enumeration-output-path "$OUT/tests.json" > "$OUT/enumerate.log" 2>&1 \
  || { echo "ENUMERATION FAILED — $OUT/enumerate.log"; tail -40 "$OUT/enumerate.log"; exit 1; }

# Deal the tests out. The unit target is 502 tests in five seconds, so it goes
# to one worker whole rather than being sliced; the UI tests are what costs, and
# they are dealt one at a time. Slowest first, longest-processing-time greedy,
# using the durations the last run recorded -- an unknown test is assumed
# median, so a new test is never the thing that unbalances the run.
python3 - "$OUT/tests.json" "$WORKERS" "$OUT" scripts/gate-durations.tsv <<'PY'
import json, sys, os, collections
tests_json, workers, out, durfile = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]

# enabledTests only: -skip-testing is honoured by the enumeration, and the
# sweeps it skips turn up under disabledTests in the same file.
ids = set()
for value in json.load(open(tests_json)).get("values", []):
    for test in value.get("enabledTests", []):
        i = test.get("identifier")
        if isinstance(i, str) and i.count("/") >= 2:
            ids.add(i)
if not ids:
    sys.exit("no tests enumerated")

ui   = sorted(i for i in ids if i.startswith("ScorangerUITests/"))
unit = sorted(i for i in ids if not i.startswith("ScorangerUITests/"))

dur = {}
if os.path.exists(durfile):
    for line in open(durfile):
        parts = line.split("\t")
        if len(parts) == 2:
            try: dur[parts[0].strip()] = float(parts[1])
            except ValueError: pass
known = sorted(dur[i] for i in ui if i in dur)
median = known[len(known)//2] if known else 21.0

shards = [[] for _ in range(workers)]
load   = [0.0] * workers
# the unit target as one lump, on the worker that will finish first anyway
if unit:
    shards[0].append("ScorangerTests")
    load[0] += 6.0
for t in sorted(ui, key=lambda t: -dur.get(t, median)):
    k = load.index(min(load))
    shards[k].append(t)
    load[k] += dur.get(t, median)

for n, (s, l) in enumerate(zip(shards, load), 1):
    with open(os.path.join(out, f"shard-{n}.txt"), "w") as f:
        f.write("\n".join(s) + "\n")
    print(f"    worker {n}: {len(s)} entries, ~{l:.0f}s predicted")
print(f"    {len(ui)} UI tests + {len(unit)} unit tests enumerated")
with open(os.path.join(out, "expected.txt"), "w") as f:
    f.write(f"{len(ui) + len(unit)}\n")
PY

EXPECTED=$(cat "$OUT/expected.txt")
echo "==> running $EXPECTED tests on $WORKERS simulators"
START=$(date +%s)
pids=(); udids=()
for n in $(seq 1 "$WORKERS"); do
  udid=$(sim_for "$n"); udids+=("$udid")
  args=()
  while read -r t; do [[ -n "$t" ]] && args+=("-only-testing:$t"); done < "$OUT/shard-$n.txt"
  if (( ${#args[@]} == 0 )); then pids+=(0); continue; fi
  ( xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
      -destination "platform=iOS Simulator,id=$udid" \
      -resultBundlePath "$OUT/worker-$n.xcresult" \
      "${args[@]}" ${EXTRA+"${EXTRA[@]}"} > "$OUT/worker-$n.log" 2>&1 ) &
  pids+=($!)
done

fail=0
for n in $(seq 1 "$WORKERS"); do
  pid=${pids[$((n-1))]}
  [[ "$pid" == 0 ]] && continue
  if ! wait "$pid"; then echo "    worker $n FAILED"; fail=1; fi
done
ELAPSED=$(( $(date +%s) - START ))

# Did they actually RUN? Two xcodebuild runs on one simulator report success
# having executed nothing, which is why this is an assertion and not a print.
echo "==> results"
count=0
python3 - "$OUT" "$WORKERS" "$EXPECTED" scripts/gate-durations.tsv <<'PY' || count=$?
import json, subprocess, sys, os
out, workers, expected, durfile = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
total = passed = failed = skipped = 0
durations = {}
for n in range(1, workers + 1):
    path = os.path.join(out, f"worker-{n}.xcresult")
    if not os.path.exists(path):
        print(f"    worker {n}: NO RESULT BUNDLE"); continue
    s = json.loads(subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "summary",
         "--path", path, "--format", "json"]))
    t = s.get("totalTestCount", 0)
    total += t; passed += s.get("passedTests", 0)
    failed += s.get("failedTests", 0); skipped += s.get("skippedTests", 0)
    print(f"    worker {n}: {t} tests, {s.get('failedTests',0)} failed")
    try:
        tests = json.loads(subprocess.check_output(
            ["xcrun", "xcresulttool", "get", "test-results", "tests",
             "--path", path, "--format", "json"]))
    except subprocess.CalledProcessError:
        continue

    def seconds(text):
        # "1m 22s", "41s", "0.5s"
        total = 0.0
        for part in str(text or "").replace(",", " ").split():
            try:
                if part.endswith("ms"): total += float(part[:-2]) / 1000
                elif part.endswith("s"): total += float(part[:-1])
                elif part.endswith("m"): total += float(part[:-1]) * 60
                elif part.endswith("h"): total += float(part[:-1]) * 3600
            except ValueError:
                pass
        return total

    # A Test Case's nodeIdentifier is "Class/method()"; the TARGET is the name
    # of the bundle node above it, and -only-testing wants all three. Reading
    # the class off the enclosing suite instead wrote "RenderShot/RenderShot/
    # testX()" for every class whose name is not the target's, and those tests
    # then had no recorded duration to balance with.
    def walk(node, bundle=""):
        if not isinstance(node, dict):
            if isinstance(node, list):
                for v in node: walk(v, bundle)
            return
        kind = node.get("nodeType")
        if kind and kind.endswith("test bundle"):
            bundle = node.get("name") or bundle
        if kind == "Test Case" and node.get("nodeIdentifier") and bundle:
            secs = seconds(node.get("duration"))
            if secs:
                durations[f"{bundle}/{node['nodeIdentifier']}"] = secs
        for child in node.get("children", []):
            walk(child, bundle)
    walk(tests.get("testNodes", tests))

print(f"    TOTAL {total} tests: {passed} passed, {failed} failed, {skipped} skipped")
if durations:
    # MERGED, never replaced: a run narrowed with -only-testing would otherwise
    # throw away the timings of every test it did not run, and the next full
    # gate would split on nothing.
    table = {}
    if os.path.exists(durfile):
        for line in open(durfile):
            parts = line.split("\t")
            if len(parts) == 2:
                try: table[parts[0].strip()] = float(parts[1])
                except ValueError: pass
    table.update(durations)
    with open(durfile, "w") as f:
        for k in sorted(table):
            f.write(f"{k}\t{table[k]:.1f}\n")
if total < expected:
    print(f"!!! {expected} tests were enumerated but only {total} executed.")
    print("!!! A worker ran nothing -- check that each has its own simulator.")
    sys.exit(2)
sys.exit(1 if failed else 0)
PY

printf '==> gate finished in %dm %ds\n' $((ELAPSED/60)) $((ELAPSED%60))
(( fail == 0 && count == 0 )) || exit 1
