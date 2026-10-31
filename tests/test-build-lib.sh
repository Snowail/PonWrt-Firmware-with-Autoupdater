#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/build-lib.sh"
TMP_TEST="$(mktemp -d)"
trap 'rm -rf "$TMP_TEST"' EXIT
DIAG_DIR="$TMP_TEST/logs"
mkdir -p "$DIAG_DIR"
NJOBS=4

# A shell function stands in for make; it never invokes a compiler.
make() {
  printf '%s\n' "$*" >> "$TMP_TEST/calls"
  if [[ "$*" == *-j4* ]]; then
    echo "${FAKE_ERROR:-unclassified failure}"
    return 7
  fi
  echo 'serial diagnostic command and error context'
  return "${SERIAL_STATUS:-0}"
}

for FAKE_ERROR in 'ERROR: target/linux failed to build.' 'no matching ERROR line' 'ERROR: package/foo failed'; do
  export FAKE_ERROR
  run_make retry-test > "$TMP_TEST/console"
  [[ -s "$DIAG_DIR/retry-test-serial.log" ]]
  grep -q 'make_exit=7' "$DIAG_DIR/retry-test-parallel.status"
done
SERIAL_STATUS=23
if run_make final-failure > "$TMP_TEST/console"; then
  echo 'FAIL: final failure was swallowed'; exit 1
else
  [[ $? == 23 ]]
fi
if grep -q clean "$TMP_TEST/calls"; then echo 'FAIL: unexpected clean'; exit 1; fi

# A failed logger must not turn a successful command into a green build.
make() { echo success; return 0; }
tee() { cat >/dev/null; return 9; }
if run_make log-failure > "$TMP_TEST/console"; then
  echo 'FAIL: logger failure was swallowed'; exit 1
else
  [[ $? == 9 ]]
fi
unset -f tee
echo 'PASS: target/linux, unknown error, package error, exit code, no clean, tee failure'

SRC_DIR="$TMP_TEST/source"
SOC=an7581
mkdir -p "$SRC_DIR/bin/targets/airoha/$SOC"
printf image > "$SRC_DIR/bin/targets/airoha/$SOC/example.itb"
printf manifest > "$SRC_DIR/bin/targets/airoha/$SOC/example.manifest"
printf unrelated > "$SRC_DIR/bin/targets/airoha/$SOC/other.txt"
preserve_failed_outputs
[[ ! -d "$DIAG_DIR/unverified-images" ]]
touch "$DIAG_DIR/compile.ok"
preserve_failed_outputs
cmp "$SRC_DIR/bin/targets/airoha/$SOC/example.itb" "$DIAG_DIR/unverified-images/example.itb"
[[ -f "$DIAG_DIR/unverified-images/example.manifest" ]]
[[ -f "$DIAG_DIR/unverified-images/README.txt" ]]
[[ ! -f "$DIAG_DIR/unverified-images/other.txt" ]]
echo 'PASS: failed collection preserves completed images as unverified diagnostics'
