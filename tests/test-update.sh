#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_TEST="$(mktemp -d)"
trap 'rm -rf "$TMP_TEST"' EXIT
export TMP_TEST
sed -e "s|/etc/ponwrt-version|$TMP_TEST/local|g" \
    -e "s|/etc/ponwrt-update.proxy|$TMP_TEST/proxy|g" \
    -e "s|/tmp/ponwrt-update.json|$TMP_TEST/remote.json|g" \
    -e "s|/tmp/ponwrt-update.itb|$TMP_TEST/image.itb|g" \
    "$ROOT/overlay/usr/bin/ponwrt-update-check" > "$TMP_TEST/update.sh"
printf 'device=nokia_xg-040g-md-ubi\ntarget=an7581\nbuilt=20261030-120000\n' > "$TMP_TEST/local"
printf fixture > "$TMP_TEST/firmware"
export TEST_SHA
TEST_SHA="$(sha256sum "$TMP_TEST/firmware" | awk '{print $1}')"
export TEST_DEVICE=nokia_xg-040g-md-ubi TEST_BUILT=20261031-120000
export TEST_FILE=ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-squashfs-sysupgrade.itb
export TEST_URL="https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/releases/download/test/$TEST_FILE"
curl() {
  local out=''
  while (( $# )); do
    if [[ "$1" == -o ]]; then out="$2"; shift; fi
    shift
  done
  cp "$TMP_TEST/firmware" "$out"
}
jsonfilter() {
  case "${*: -1}" in
    '@.version') echo test ;;
    '@.built') echo "$TEST_BUILT" ;;
    '@.file') echo "$TEST_FILE" ;;
    '@.device') echo "$TEST_DEVICE" ;;
    '@.sha256') echo "$TEST_SHA" ;;
    '@.download_url') echo "$TEST_URL" ;;
  esac
}
sysupgrade() { printf '%s\n' "$*" >> "$TMP_TEST/flash-calls"; return 0; }
export -f curl jsonfilter sysupgrade
bash "$TMP_TEST/update.sh" --flash > "$TMP_TEST/output"
[[ "$(wc -l < "$TMP_TEST/flash-calls")" == 2 ]]
grep -q '^-T ' "$TMP_TEST/flash-calls"
rm "$TMP_TEST/flash-calls"
TEST_DEVICE=wrong-device
if bash "$TMP_TEST/update.sh" --flash > "$TMP_TEST/output"; then echo 'FAIL: wrong device accepted'; exit 1; fi
[[ ! -e "$TMP_TEST/flash-calls" ]]
TEST_DEVICE=nokia_xg-040g-md-ubi
TEST_URL=https://example.invalid/firmware.itb
if bash "$TMP_TEST/update.sh" --flash > "$TMP_TEST/output"; then echo 'FAIL: wrong URL accepted'; exit 1; fi
[[ ! -e "$TMP_TEST/flash-calls" ]]
TEST_URL="https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/releases/download/test/$TEST_FILE"
TEST_BUILT=20261029-120000
bash "$TMP_TEST/update.sh" --flash > "$TMP_TEST/output"
[[ ! -e "$TMP_TEST/flash-calls" ]]
echo 'PASS: compatible image, sysupgrade test, wrong device, wrong URL, downgrade rejection (all mocked)'
