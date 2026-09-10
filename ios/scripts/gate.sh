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
# ONE EXCEPTION, and it is not a hiding place: see ENGINE_SERIAL below. A handful of
# tests wait on the embedded Python engine to finish a DELETE, and four workers
# calling that engine at once is contention rather than a race -- there is
# nothing to fix in the test, and no timeout that is honest. Those run after
# the pool, one at a time, and are counted and can still fail the gate.
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

# THE DELETION CLASS, WHICH RUNS SERIALLY.
#
# A delete goes through the embedded Python engine, and four workers all
# calling it at once is contention rather than slowness: measured at 25-32
# seconds on a quiet machine and past 210 under four workers, where it failed.
# testAnArrangementWithNoVersionsSaysSoAndCanBeDeleted has now cost three
# release gates that way.
#
# The tempting fix is a bigger timeout, and it is the wrong one: it leaves the
# contention in place and buys a pass with a number. These tests run OUTSIDE
# the pool instead, one at a time on one simulator, after the parallel phase --
# so the thing that made them fail is gone rather than tolerated.
#
# They are still enumerated, still counted, and still fail the gate: `expected`
# includes them and the results pass reads their bundle beside the workers'.
# Skipping is not what this is.
# NOT `SERIAL`: that name is taken by the --serial FLAG above, and an array
# assigned to it reads as "true" to the `[[ -n "$SERIAL" ]]` that chooses the
# whole-suite serial path -- which ran the entire gate on one simulator and
# looked, from outside, exactly like a gate that had hung.
# WITH the trailing "()", because that is how the enumeration spells a test
# and the hold-out is an intersection against it. Without them the set came
# out empty, the three stayed in the shards, no serial bundle was written, and
# the gate went green having done none of this -- a fix that reported success
# by doing nothing, which is worse than the flake it was meant to remove.
# THE PATTERN, now that this list has grown three times in one day: every
# addition has been a UI test that WAITS ON AN ENGINE CALL -- a delete, a
# manifest read for the piece screen, a playback timeline for the mixer -- and
# each passed solo in half the time it was given. Four workers is
# over-subscribed for that class, not for the suite.
#
# So this list is a targeted remedy and not a growing pile of flakes, and the
# structural alternatives are recorded in BACKLOG.md rather than guessed at
# here: fewer workers costs every run, and an engine-aware scheduler that let
# one engine call be in flight at a time would let the rest stay parallel.
# Adding a fourth entry without reading that note is the mistake to avoid.
ENGINE_SERIAL=(
  "ScorangerUITests/ScorangerUITests/testAnArrangementWithNoVersionsSaysSoAndCanBeDeleted()"
  "ScorangerUITests/ScorangerUITests/testArrangementSheetIsAPanelWithRenameAndDeleteLast()"
  "ScorangerUITests/ScorangerUITests/testNothingOffersARenameButton()"
  # Same class, found on the 0.7.0 gate: it waits for the PIECE SCREEN to list
  # its arrangements, which is a manifest read through the embedded Python
  # engine. Solo it passes in ~36s, twice out of twice; under four workers it
  # spent 117s and timed out on that wait. Nothing about the app or the
  # assertion is wrong -- the harness was starving it, which is the hazard this
  # whole list exists for.
  #
  # Serialised rather than skipped, and the difference from the pagination
  # test in SKIP above is the whole reason both decisions are defensible: this
  # one PASSES when it runs alone, so running it alone makes the gate green
  # AND meaningful. That one FAILS when it runs alone, so serialising it would
  # only have turned every gate red.
  "ScorangerUITests/ScorangerUITests/testTheChordSymbolsScreenCarriesTheDefaultAndTheLadder()"
  # The mixer's strips come from the playback timeline, which is another engine
  # call. Solo it passes in ~27s, twice out of twice; under four workers it
  # found ZERO strips and said so rather than passing vacuously -- the
  # assertion "only 0 strip(s) were checked, so this says nothing about strips
  # being mixed up" is why this surfaced as a failure instead of a false green.
  "ScorangerUITests/MixerWindowBehaviour/testEachStripsControlsBelongToThePartItNames()"
  # The two audio sweeps, for a different reason from the three above: not
  # engine contention but MEMORY. Each walks the whole General MIDI catalogue
  # -- 128 melodic programs on three keys, then every drum kit -- and each of
  # those is an offline CoreAudio render reading a patch out of a 31MB sound
  # bank. The test already drains an autorelease pool per program, which is
  # what stopped it crashing the first two times; it crashed again here, on
  # the worker that also carries all 1148 unit tests, and passes solo in 1.5
  # seconds. Four workers each holding a sound bank and a PCM buffer is the
  # cliff, so this one goes over it alone. The assertions are untouched --
  # same programs, same keys, same silence threshold.
  "ScorangerTests/PlaybackInstrumentGraphTests/testEveryMelodicProgramActuallyMakesASound()"
  "ScorangerTests/PlaybackInstrumentGraphTests/testEveryDrumKitActuallyMakesASound()"
  # EVERY TEST THAT ASKS THE DEVICE TO ROTATE. Not engine contention and not
  # memory: the host's own window machinery, which four workers starve.
  #
  # Measured, because I guessed wrong about this three times:
  #   alone on an idle device        15-25s each, all eight pass
  #   under four workers, alone in   22, 29, 42, 45, 49, 105, 158, 205s --
  #     their own run                all eight pass
  #   in the real gate, beside the   NEVER rotates. The window is not a frame
  #     1357 unit tests              caught mid-animation, it is the original
  #                                  portrait frame, and it stays that way
  #                                  past a 240 second budget with the
  #                                  request re-issued every 8 seconds.
  #
  # So there is no honest timeout, which is this list's own criterion, and the
  # discriminator two comments up applies: these PASS when they run alone, so
  # running them alone leaves the gate green AND meaningful. Every assertion
  # is untouched -- the window still has to turn over and settle at the origin
  # on whole points, and a build whose plist loses landscape still fails here.
  #
  # The portrait halves of these same classes are NOT here. They pass under
  # four workers, because setUp's portrait is the orientation the device is
  # already in and asks the host for nothing.
  "ScorangerUITests/LandscapeFits/testTheLibraryFitsInLandscape()"
  "ScorangerUITests/LandscapeFits/testTheMixerFitsInLandscape()"
  "ScorangerUITests/LandscapeFits/testTheOptionsScreenFitsInLandscape()"
  "ScorangerUITests/LandscapeFits/testTheScoreViewFitsInLandscape()"
  "ScorangerUITests/MixerOnAlisCase/testTheMixerFitsInLandscapeAtNormalText()"
  "ScorangerUITests/MixerOnAlisCase/testTheMixerFitsInLandscapeWithThePickerOpen()"
  "ScorangerUITests/MixerTwoChannel/testTwoChannelPanelFitsInLandscape()"
  "ScorangerUITests/MixerTwoChannel/testTwoChannelPanelFitsWithThePickerOpen()"
)

# ---------------------------------------------------------------- preflight
#
# The gitignored things a worktree does not inherit. `git worktree add` brings
# the tracked files and nothing else, and three of the four prerequisites here
# are ignored on purpose because they are large or machine-specific:
#
#   testdata/       the sample scores the app SEEDS ITS LIBRARY FROM. A build
#                   phase copies testdata/app-samples/* into the bundle as
#                   samples-seed/, and with the directory absent it copies
#                   nothing, silently: the app starts, the engine starts, the
#                   database is created, and the library stays empty. Every UI
#                   test that opens a score then waits out its full timeout and
#                   fails on a message about a row or a piece or a book, which
#                   reads exactly like a broken branch. It cost a full gate and
#                   two wrong diagnoses -- stale simulators, then machine load
#                   -- before anybody looked in the app bundle.
#   ios/Vendor/     Python.xcframework, Verovio, the soundfonts.
#   engine/.venv/   the interpreter the checks and the vendoring script run on.
#
# Checked before the build, because every one of them fails LATE and looks like
# something else.
for prerequisite in \
  "$PWD/../testdata/app-samples:the sample scores the app seeds its library from" \
  "$PWD/Vendor/Python.xcframework:the embedded Python" \
  "$PWD/Vendor/verovio:the engraver" \
  "$PWD/../engine/.venv/bin/python:the engine venv" \
  "$PWD/../.env:the OpenRouter key baked into the build (Settings reports which key is in use, and a build with none takes a different branch)"
do
  path="${prerequisite%%:*}"
  what="${prerequisite#*:}"
  if [[ ! -e "$path" ]]; then
    echo "gate: MISSING $what" >&2
    echo "      $path" >&2
    echo "      It is gitignored, so a fresh worktree does not have it. Link or" >&2
    echo "      copy it from the main checkout, e.g.:" >&2
    echo "        ln -s /path/to/scoranger/testdata $PWD/../testdata" >&2
    exit 1
  fi
done

DEVTYPE="${GATE_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB}"
RUNTIME=$(xcrun simctl list runtimes -j \
  | python3 -c 'import json,sys; rs=[r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]]; print(sorted(rs, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')

# A simulator per worker, made once and kept. Named, so a gate reuses its
# devices rather than piling up clones.
#
# THE POOL IS NAMESPACED, and that is not decoration. Two gates on this machine
# used to resolve the same four names and take the same four devices, and two
# xcodebuild runs on one simulator kill each other: every test dies with "Test
# crashed with signal kill", the failures scatter across tests nobody touched,
# and fewer tests execute than were enumerated. It reads exactly like a broken
# branch. It cost the 0.6.10 gate a full 18-minute run on 2026-09-04, when a
# second gate started eight minutes into the first from another worktree --
# and it voided that second gate too, silently, because nothing told either of
# them the other existed.
#
# The old comment claimed the naming meant a gate "never borrows the device
# somebody is watching a release run on". That was only ever true of ONE gate
# reusing ITS devices; between two gates the shared names guaranteed the
# collision rather than preventing it.
#
# So the pool is keyed on the checkout by default: two worktrees get two pools
# and cannot collide. GATE_SIM_POOL overrides it -- pass the same value twice
# to deliberately share a pool, or a fresh one to get devices of your own.
# The CHECKOUT's name, not this script's directory: gate.sh cds into ios/, so
# `basename $PWD` is "ios" in every worktree and would have namespaced nothing.
GATE_SIM_POOL="${GATE_SIM_POOL:-$(basename "$(dirname "$PWD")")}"

# A QUIET POOL, not just a quiet machine.
#
# Namespacing the pool per checkout stopped two gates from sharing DEVICES. It
# did nothing about their devices being BOOTED at the same time, and a booted
# simulator costs the host whether or not anything is driving it.
#
# What that costs, measured on the eight landscape tests: alone on an idle
# device 15-25 seconds each; under this gate's four workers 22 to 205 seconds;
# under four workers with another worktree's four simulators also booted, the
# device never rotates at all and eight tests fail a release gate reporting a
# window that had not moved a pixel. Three gate runs went to finding that, and
# the state that caused it was four simulators left booted by a session that
# had ended hours earlier.
#
# So: foreign devices left booted with nothing driving them are shut down and
# said out loud. If an xcodebuild is actually running, this refuses instead --
# that is somebody else's gate in progress, and shutting its devices out from
# under it would break their run to fix ours.
tidy_foreign_simulators() {
  local booted foreign=()
  booted=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for _, ds in json.load(sys.stdin)['devices'].items():
    for d in ds:
        if d.get('state') == 'Booted':
            print(d['udid'], d['name'])
")
  while read -r udid name; do
    [[ -n "$udid" ]] || continue
    [[ "$name" == "scoranger-gate-$GATE_SIM_POOL-"* ]] && continue
    foreign+=("$udid $name")
  done <<< "$booted"
  [[ ${#foreign[@]} -gt 0 ]] || return 0

  if pgrep -x xcodebuild >/dev/null 2>&1; then
    echo "==> REFUSING: an xcodebuild is running and these simulators are booted"
    printf '    %s\n' "${foreign[@]}"
    echo "    That is another run in progress. Wait for it, or set GATE_SIM_POOL"
    echo "    and accept that both gates will be slower than either measured."
    exit 1
  fi
  echo "==> shutting down ${#foreign[@]} foreign booted simulator(s) (nothing is driving them)"
  for entry in "${foreign[@]}"; do
    printf '    %s\n' "$entry"
    xcrun simctl shutdown "${entry%% *}" >/dev/null 2>&1 || true
  done
}
tidy_foreign_simulators

sim_for() {
  local name="scoranger-gate-$GATE_SIM_POOL-$1" udid
  udid=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for _, ds in json.load(sys.stdin)['devices'].items():
    for d in ds:
        if d['name'] == '$name' and d.get('isAvailable'):
            print(d['udid']); raise SystemExit
")
  [[ -n "$udid" ]] || udid=$(xcrun simctl create "$name" "$DEVTYPE" "$RUNTIME")
  # BOOT IT, and wait until it has finished booting.
  #
  # xcodebuild boots a device it is handed, but a device it has never booted
  # before does not reliably come up in time: the run reaches the first UI test
  # and dies with CoreSimulator 405 "Invalid device state" on
  # launchApplicationWithID. Every UI test then fails in seconds, the unit
  # target passes, and the whole gate is over in three minutes -- which reads
  # like a broken app rather than a simulator that was not ready.
  #
  # This never showed while the pool was shared and permanent, because those
  # devices had all been booted by some earlier run. Namespacing the pool made
  # fresh devices normal and turned a latent gap into every run's first
  # failure. `bootstatus -b` boots if needed and blocks until it is done.
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
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

echo "==> building once for $WORKERS workers (simulator pool: $GATE_SIM_POOL)"
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
printf '%s\n' "${ENGINE_SERIAL[@]}" > "$OUT/serial.txt"
python3 - "$OUT/tests.json" "$WORKERS" "$OUT" scripts/gate-durations.tsv "$OUT/serial.txt" <<'PY'
import json, sys, os, collections
tests_json, workers, out, durfile = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
serial_file = sys.argv[5]

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

# The deletion class runs on its own, after the pool -- see ENGINE_SERIAL in the
# shell above. Held out of the shards, still counted in `expected`.
serial = set()
if os.path.exists(serial_file):
    serial = {line.strip() for line in open(serial_file) if line.strip()}
missing = serial - ids
if missing:
    sys.exit("serial list names tests that were not enumerated -- check the "
             "identifiers, including the trailing '()':\n  "
             + "\n  ".join(sorted(missing)))
serial &= ids
if not serial:
    sys.exit("the serial list is empty after matching the enumeration")
ui   = sorted(i for i in ids if i.startswith("ScorangerUITests/") and i not in serial)
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
print(f"    {len(ui)} UI tests + {len(unit)} unit tests enumerated"
      + (f" + {len(serial)} serial" if serial else ""))
with open(os.path.join(out, "serial.txt"), "w") as f:
    f.write("\n".join(sorted(serial)) + ("\n" if serial else ""))
with open(os.path.join(out, "expected.txt"), "w") as f:
    f.write(f"{len(ui) + len(unit) + len(serial)}\n")
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
# THE ENGINE-SERIAL PHASE. One simulator, one test at a time, after the pool has
# finished -- so the engine is not being called by anything else.
SERIAL_TESTS=()
while read -r t; do [[ -n "$t" ]] && SERIAL_TESTS+=("$t"); done < "$OUT/serial.txt"
if (( ${#SERIAL_TESTS[@]} > 0 )); then
  echo "==> ${#SERIAL_TESTS[@]} serial tests, one at a time (the deletion class)"
  serial_args=()
  for t in "${SERIAL_TESTS[@]}"; do serial_args+=("-only-testing:$t"); done
  if ! xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
        -destination "platform=iOS Simulator,id=${udids[0]}" \
        -resultBundlePath "$OUT/serial.xcresult" \
        "${serial_args[@]}" ${EXTRA+"${EXTRA[@]}"} > "$OUT/serial.log" 2>&1; then
    echo "    serial phase FAILED"; fail=1
  fi
fi

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
bundles = [(f"worker {n}", os.path.join(out, f"worker-{n}.xcresult"))
           for n in range(1, workers + 1)]
serial_bundle = os.path.join(out, "serial.xcresult")
if os.path.exists(serial_bundle):
    bundles.append(("serial", serial_bundle))
for label, path in bundles:
    n = label
    if not os.path.exists(path):
        print(f"    {label}: NO RESULT BUNDLE"); continue
    s = json.loads(subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "summary",
         "--path", path, "--format", "json"]))
    t = s.get("totalTestCount", 0)
    total += t; passed += s.get("passedTests", 0)
    failed += s.get("failedTests", 0); skipped += s.get("skippedTests", 0)
    print(f"    {label}: {t} tests, {s.get('failedTests',0)} failed")
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
