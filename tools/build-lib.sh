#!/usr/bin/env bash
# Explicit checks also work when the caller invokes these functions inside `if`.
logged_make() {
  local name="$1"
  shift
  local -a statuses
  if make "$@" 2>&1 | tee "$DIAG_DIR/$name.log"; then
    return 0
  else
    statuses=("${PIPESTATUS[@]}")
    printf 'make_exit=%s tee_exit=%s\n' "${statuses[0]}" "${statuses[1]}" >> "$DIAG_DIR/$name.status"
    if (( statuses[0] != 0 )); then return "${statuses[0]}"; fi
    return "${statuses[1]}"
  fi
}

run_make() {
  local phase="$1" rc
  shift
  if logged_make "$phase-parallel" -j"$NJOBS" V=s "$@"; then
    return 0
  else
    rc=$?
    printf '\nParallel %s failed (exit %s); retrying once with -j1 V=s, without cleaning.\n' "$phase" "$rc"
  fi
  # No grep and no clean: unknown errors and target/linux always reach diagnosis.
  if logged_make "$phase-serial" -j1 V=s "$@"; then
    return 0
  else
    rc=$?
    printf 'Detailed %s failed (exit %s). See %s/%s-serial.log\n' "$phase" "$rc" "$DIAG_DIR" "$phase"
    return "$rc"
  fi
}
