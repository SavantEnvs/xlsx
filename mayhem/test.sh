#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the FULL upstream test suite of tealeg/xlsx (the single
# root package's `go test` suite: quicktest + gocheck behavioral assertions),
# pre-compiled by mayhem/build.sh into mayhem-build/xlsx.test. This script only
# RUNS the binary and maps the verbose output to CTRF counts.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/mayhem-build/xlsx.test"
if [ ! -x "$RUNNER" ]; then
  echo "FATAL: pre-built test runner missing at $RUNNER (mayhem/build.sh must produce it)" >&2
  emit_ctrf "go-test" 0 1 0
  exit 1
fi

LOG=/tmp/xlsx-test.log
rc=0
# Run from the repo root: the suite reads fixtures via relative paths (testdocs/).
#
# -test.parallel=1 serializes the suite's t.Parallel() subtests to close an
# UPSTREAM test-helper race (present at the mirrored commit, unfixed upstream;
# introduced by f8c23d2 "Enable parallel testing"): testutil.go's csRunO/csRunC
# run the {MemoryCellStore,DiskVCellStore} variants with c.Parallel() and
# register a cleanTempDir Cleanup that bulk-deletes ALL /tmp/cellstore* dirs.
# At the one nested call site (file_test.go "#707 should be fixed", inside
# TestSliceReader/TestFileToSliceUnmerged) that Cleanup fires when one parallel
# sibling finishes while the other sibling's live DiskV store is still on disk,
# wiping it mid-test -> scheduling-dependent failures (this exact race produced
# the 2026-07-18 cloud failure: 543 tests, 538 pass, 4 fail, 1 skip — the 4
# fails and 3 never-spawned subtests are the #707 subtree). With -test.parallel=1
# no two parallel subtests ever overlap, so a Cleanup can never delete a live
# sibling store. ALL 546 tests still run, with all behavioral assertions.
"$RUNNER" -test.v -test.parallel=1 > "$LOG" 2>&1 || rc=$?
tail -5 "$LOG"
# Diagnosability: name the failing tests (the tail alone loses them).
grep -E '^[[:space:]]*--- FAIL:' "$LOG" || true

# Map the verbose go-test output (top-level + subtest result lines) to counts.
P=$(grep -cE '^[[:space:]]*--- PASS:' "$LOG" || true)
F=$(grep -cE '^[[:space:]]*--- FAIL:' "$LOG" || true)
S=$(grep -cE '^[[:space:]]*--- SKIP:' "$LOG" || true)

# A crashed/neutered runner (no parsable results, or nonzero exit) is a failure.
if [ "$rc" -ne 0 ] && [ "$F" -eq 0 ]; then F=1; fi
if [ $(( P + F + S )) -eq 0 ]; then
  echo "FATAL: test runner produced no test results" >&2
  emit_ctrf "go-test" 0 1 0
  exit 1
fi

emit_ctrf "go-test" "$P" "$F" "$S"
