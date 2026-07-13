#!/usr/bin/env bash
#
# mayhem/test.sh — run the AUTHORED behavioral oracle for the url-parse harness
# code path (the `url` crate: parse / quirks setters / form_urlencoded).
#
# WHY AUTHORED (not deno's upstream suite): deno's upstream tests (cargo test on the
# workspace, tests/unit/*.ts, tests/specs, WPT) all require building the full `deno`
# binary — V8 + the entire runtime, tens of GB and hours of build, plus network at
# test time — which cannot run inside the fuzz commit image, and none of them
# exercise the crate this harness actually fuzzes (the `url` crate, historically via
# the `deno_core::url` re-export). The oracle asserts known-answer outputs over the
# same APIs the harness drives, so a no-op/exit(0) sabotage patch FAILS it.
#
# Runs the PRE-BUILT libtest binary produced by mayhem/build.sh (no compiling here)
# and maps its output to CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

RUNNER=/mayhem/url-oracle-tests
if [ ! -x "$RUNNER" ]; then
  echo "ERROR: $RUNNER missing — mayhem/build.sh should have built it" >&2
  emit_ctrf "cargo-libtest" 0 1
  exit 1
fi

out="$("$RUNNER" --test-threads=1 2>&1)"; rc=$?
echo "$out"

# libtest summary: "test result: ok. 8 passed; 0 failed; 0 ignored; ..."
summary="$(printf '%s\n' "$out" | grep -m1 '^test result:')"
passed="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) passed.*/\1/p')"
failed="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
skipped="$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) ignored.*/\1/p')"
passed="${passed:-0}"; failed="${failed:-0}"; skipped="${skipped:-0}"

# A runner that produced no summary (crashed / neutered to exit 0) is a failure.
if [ -z "$summary" ] || { [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; }; then
  echo "ERROR: oracle runner produced no libtest summary (rc=$rc)" >&2
  emit_ctrf "cargo-libtest" 0 1
  exit 1
fi
[ "$rc" -ne 0 ] && [ "$failed" -eq 0 ] && failed=1

emit_ctrf "cargo-libtest" "$passed" "$failed" "$skipped"
