#!/usr/bin/env bash
# Exercise the pinned upstream's real file-selection functions without flashing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${1:?path to the pinned upstream sbin/sysupgrade}"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
mkdir -p "$TMP_TEST/etc" "$TMP_TEST/lib/upgrade/keep.d" "$TMP_TEST/lib/apk/packages" "$TMP_TEST/restored"
cp "$ROOT/overlay/lib/upgrade/keep.d/ponwrt-update" "$TMP_TEST/lib/upgrade/keep.d/"
printf 'http://10.0.0.5:7897\n' > "$TMP_TEST/etc/ponwrt-update.proxy"
printf 'monthly\n' > "$TMP_TEST/etc/ponwrt-update.interval"
printf 'old image identity\n' > "$TMP_TEST/etc/ponwrt-version"
printf 'old result\n' > "$TMP_TEST/etc/ponwrt-update.state"
: > "$TMP_TEST/etc/sysupgrade.conf"
# Only source file-selection functions, never the upgrade entry point.
awk '/^list_conffiles\(\)/ {copy=1} /^build_list_of_backup_overlay_files\(\)/ {copy=0} copy' "$1" |
    sed -e "s|/etc/|$TMP_TEST/etc/|g" -e "s|/lib/apk/|$TMP_TEST/lib/apk/|g" \
        -e "s|/lib/upgrade/|$TMP_TEST/lib/upgrade/|g" -e "s|/usr/lib/opkg/|$TMP_TEST/opkg/|g" > "$TMP_TEST/functions"
sed -i "s|^/etc/|$TMP_TEST/etc/|" "$TMP_TEST/lib/upgrade/keep.d/ponwrt-update"
source "$TMP_TEST/functions"
find_filter=''
build_list_of_backup_config_files "$TMP_TEST/list" || exit 1
printf '%s\n' "$TMP_TEST/etc/ponwrt-update.interval" "$TMP_TEST/etc/ponwrt-update.proxy" > "$TMP_TEST/expected"
diff -u "$TMP_TEST/expected" "$TMP_TEST/list"
sed "s|^$TMP_TEST/||" "$TMP_TEST/list" > "$TMP_TEST/relative"
tar -czf "$TMP_TEST/backup.tar.gz" -C "$TMP_TEST" -T "$TMP_TEST/relative"
tar -xzf "$TMP_TEST/backup.tar.gz" -C "$TMP_TEST/restored"
cmp "$TMP_TEST/etc/ponwrt-update.proxy" "$TMP_TEST/restored/etc/ponwrt-update.proxy"
cmp "$TMP_TEST/etc/ponwrt-update.interval" "$TMP_TEST/restored/etc/ponwrt-update.interval"
# Missing proxy on a clean image must not prevent backup; cleared proxy stays cleared.
rm "$TMP_TEST/etc/ponwrt-update.proxy"
build_list_of_backup_config_files "$TMP_TEST/list" || exit 1
[[ $(wc -l < "$TMP_TEST/list") == 1 ]]
printf '\n' > "$TMP_TEST/etc/ponwrt-update.proxy"
build_list_of_backup_config_files "$TMP_TEST/list" || exit 1
grep -Fxq "$TMP_TEST/etc/ponwrt-update.proxy" "$TMP_TEST/list"
echo 'PASS: upstream backup selection and restore preserve proxy/interval, exclude version/state'
