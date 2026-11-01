#!/usr/bin/env bash
set -euo pipefail
out=$(cd "$1" && pwd)
fixture=${2:-}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$out" && sha256sum -c sha256sums)
tar -xzf "$out/ponwrt-fast-ui.tar.gz" -C "$tmp"
bundle="$tmp/ponwrt-fast-ui"
export PONWRT_ROOT="$tmp/device"
root=$PONWRT_ROOT
page=www/luci-static/resources/view/system/flash.js
backend=usr/bin/ponwrt-update-check
acl=usr/share/rpcd/acl.d/luci-app-ponwrt-update.json
[[ "$(cd "$bundle/payload" && find . -type f)" == "./$page" ]]
mkdir -p "$root/etc" "$root/tmp" "$root/$(dirname "$page")" "$tmp/bin"
pin=$(sed -n 's/^ponwrt=//p' "$bundle/build-info")
short=$(sed -n 's/^luci=//p' "$bundle/build-info" | cut -c1-7)
if [[ -n "$fixture" ]]; then
    cp -R "$fixture/." "$root/"
else
    mkdir -p "$root/$(dirname "$backend")" "$root/$(dirname "$acl")"
    printf 'device=nokia_xg-040g-md-ubi\ntarget=an7581\ncommit=%s\n' "$pin" > "$root/etc/ponwrt-version"
    echo 'original page' > "$root/$page"
    echo 'original backend' > "$root/$backend"
    echo 'original acl' > "$root/$acl"
fi
chmod +x "$root/$backend"
cp -R "$root" "$tmp/before"
export PATH="$tmp/bin:$PATH" FAST_TEST_LUCI="26.302.04020~$short"
cat > "$tmp/bin/apk" <<'MOCK'
#!/bin/sh
echo "luci-mod-system $FAST_TEST_LUCI"
MOCK
chmod +x "$tmp/bin/apk"
run() { sh "$bundle/apply.sh" "$@"; }
must_fail() { if "$@"; then echo 'Unexpected success' >&2; exit 1; fi; }
run check
FAST_TEST_LUCI=other must_fail run install
[[ ! -e "$root/root/ponwrt-page-test/original" ]]
run install
cmp "$root/$page" "$bundle/payload/$page"
run install
sh "$root/root/ponwrt-page-test/rollback.sh" rollback
for file in "$page" "$backend" "$acl"; do cmp "$root/$file" "$tmp/before/$file"; done
echo tampered >> "$bundle/payload/$page"
must_fail run install
cmp "$root/$page" "$tmp/before/$page"
echo 'PASS: page-only payload, compatibility, integrity, repeat install and rollback'
