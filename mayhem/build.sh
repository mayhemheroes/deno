#!/usr/bin/env bash
#
# mayhem/build.sh — build the url-parse cargo-fuzz target as a sanitized libFuzzer
# binary, plus the pre-built oracle test runner that mayhem/test.sh executes.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem.
# Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# This first (online) build populates the cargo registry under $CARGO_HOME; the
# re-run resolves crates from that cache (the rlenv runtime exports
# CARGO_NET_OFFLINE=true), so do NOT hard-code `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# The deno repo root pins rust 1.95.0 via rust-toolchain.toml; the fuzz build needs
# the image's pinned NIGHTLY (for -Zsanitizer=address). RUSTUP_TOOLCHAIN is set by
# the Dockerfile ENV to the installed channel and overrides the toolchain file.

# Honor the $SANITIZER_FLAGS contract (SPEC): rustc ignores the clang-oriented
# $SANITIZER_FLAGS, so we map the ASan intent to the rustc flag. ASan is the default
# halting sanitizer; an explicit empty SANITIZER_FLAGS still keeps ASan here.
SANITIZER_FLAGS="${SANITIZER_FLAGS:-}"
RUST_SANITIZER="-Zsanitizer=address"
case "$SANITIZER_FLAGS" in
  *address*|"") : ;;  # ASan requested (default) or no override
esac

# Debug-info contract (SPEC §6.2 item 10): Mayhem triage cannot read DWARF >= 4, and
# LLVM default -Cdebuginfo emits DWARF-5, so pin DWARF < 4 explicitly. Overridable via
# $RUST_DEBUG_FLAGS (the rust arm of the DEBUG_FLAGS contract verify-repo checks).
export RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:--Cdebuginfo=1 -Zdwarf-version=3}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing ${RUST_SANITIZER} ${RUST_DEBUG_FLAGS} -Cforce-frame-pointers"

# libfuzzer-sys compiles a C++ runtime shim via the cc crate; clang defaults to DWARF-5,
# so pin the C/C++ objects to DWARF-3 too (the cc crate honors CFLAGS/CXXFLAGS).
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

# The rustc nightly ships a PRECOMPILED ASan runtime (librustc-*_rt.asan.a) whose
# compiler-rt CUs carry DWARF-5 (clang default); those runtime CUs would land in the
# linked fuzz binary and (being emitted first) fail the DWARF < 4 gate. Triage does not
# need runtime debug symbols; strip them (the archive is writable, chowned to 2000).
for _asan in $(find /opt/toolchains/rust -name "librustc-*_rt.asan.a" 2>/dev/null); do
  echo "stripping DWARF-5 debug info from runtime archive: $_asan"
  objcopy --strip-debug "$_asan" "$_asan.tmp" && mv "$_asan.tmp" "$_asan"
done

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the oracle test runner (normal flags, NO sanitizers) so mayhem/test.sh only
# RUNS it. `cargo test --no-run` compiles the libtest binary; copy it to a stable path.
echo "=== building oracle test runner (normal flags) ==="
( unset RUSTFLAGS
  cd "$SRC/mayhem/oracle"
  cargo test --no-run --release
  bin="$(find target/release/deps -maxdepth 1 -name 'url_oracle-*' -type f -executable | head -1)"
  [ -n "$bin" ] || { echo "ERROR: oracle test binary not built" >&2; exit 1; }
  cp "$bin" /mayhem/url-oracle-tests
  echo "built /mayhem/url-oracle-tests"
)

echo "build.sh complete"
