#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_TEST="$(mktemp -d)"
trap 'rm -rf "$TMP_TEST"' EXIT
export TMP_TEST
sed -e "s|/etc/ponwrt-version|$TMP_TEST/local|g" \
    -e "s|/etc/ponwrt-update.proxy|$TMP_TEST/proxy|g" \
    -e "s|/etc/ponwrt-update.interval|$TMP_TEST/interval|g" \
    -e "s|/etc/ponwrt-update.state|$TMP_TEST/state|g" \
    "$ROOT/overlay/usr/bin/ponwrt-update-check" > "$TMP_TEST/update.sh"
printf 'device=nokia_xg-040g-md-ubi\ntarget=an7581\nbuilt=20261030-120000\n' > "$TMP_TEST/local"
printf fixture > "$TMP_TEST/firmware"
export TEST_SHA
TEST_SHA="$(sha256sum "$TMP_TEST/firmware" | awk '{print $1}')"
export TEST_DEVICE=nokia_xg-040g-md-ubi TEST_BUILT=20261031-120000
export TEST_FILE=ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-squashfs-sysupgrade.itb
export TEST_URL="https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/releases/download/test/$TEST_FILE"
curl() {
  echo fetch >> "$TMP_TEST/requests"
  [[ ${TEST_OFFLINE:-0} == 0 ]] || return 1
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

TEST_BUILT=20261031-120000
rm "$TMP_TEST/state" "$TMP_TEST/requests"
scheduled() { bash "$TMP_TEST/update.sh" --scheduled; }
scheduled
[[ $(sed -n '3p' "$TMP_TEST/state") == test ]]
now=$(date +%s)
age_state() { sed -i "2s/.*/$((now - $1))/" "$TMP_TEST/state"; }
age_state 518400 # Six days since a successful weekly check.
scheduled
[[ $(wc -l < "$TMP_TEST/requests") == 1 ]]
age_state 604800
scheduled
[[ $(wc -l < "$TMP_TEST/requests") == 2 ]]
echo monthly > "$TMP_TEST/interval"
age_state 604800
scheduled
[[ $(wc -l < "$TMP_TEST/requests") == 2 ]]
echo off > "$TMP_TEST/interval"
age_state 3000000
scheduled
[[ $(wc -l < "$TMP_TEST/requests") == 2 ]]
echo daily > "$TMP_TEST/interval"
cp "$TMP_TEST/state" "$TMP_TEST/last-good"
if TEST_OFFLINE=1 scheduled; then exit 1; fi
cmp "$TMP_TEST/state" "$TMP_TEST/last-good"
TEST_BUILT=20261029-120000
scheduled
[[ -z $(sed -n '3p' "$TMP_TEST/state") && ! -e "$TMP_TEST/flash-calls" ]]
echo 'PASS: weekly default, configurable intervals, disabled checks, offline retry and clearing notice'

# Exercise the first-boot hook twice with an existing administrator job.
mkdir "$TMP_TEST/crontabs"
echo '7 3 * * * /usr/bin/other-task' > "$TMP_TEST/crontabs/root"
sed -e "s|/etc/crontabs|$TMP_TEST/crontabs|g" -e 's|/etc/init.d/cron running|false|' \
    "$ROOT/overlay/etc/uci-defaults/92-ponwrt-update-schedule" > "$TMP_TEST/first-boot"
sh "$TMP_TEST/first-boot"
sh "$TMP_TEST/first-boot"
[[ $(grep -Fxc '17 * * * * /usr/bin/ponwrt-update-check --scheduled' "$TMP_TEST/crontabs/root") == 1 ]]
grep -Fqx '7 3 * * * /usr/bin/other-task' "$TMP_TEST/crontabs/root"
