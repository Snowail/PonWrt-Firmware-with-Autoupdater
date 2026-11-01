#!/usr/bin/env bash
# Exercise the generated archive and on-device entry point in an isolated root.
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
mkdir -p "$root/etc/init.d" "$root/tmp" "$root/$(dirname "$page")" "$tmp/bin"
pin=$(sed -n 's/^ponwrt=//p' "$bundle/build-info")
short=$(sed -n 's/^luci=//p' "$bundle/build-info" | cut -c1-7)
if [[ -n "$fixture" ]]; then
    cp -R "$fixture/." "$root/"
else
    printf 'device=nokia_xg-040g-md-ubi\ntarget=an7581\ncommit=%s\n' "$pin" > "$root/etc/ponwrt-version"
    echo 'original page' > "$root/$page"
fi
cp "$root/$page" "$tmp/original.js"
cp -R "$root" "$tmp/before"
export PATH="$tmp/bin:$PATH" FAST_TEST_LUCI="26.302.04020~$short"
cat > "$tmp/bin/apk" <<'MOCK'
#!/bin/sh
echo "luci-mod-system $FAST_TEST_LUCI"
MOCK
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/jsonfilter"
cat > "$root/etc/init.d/rpcd" <<'MOCK'
#!/bin/sh
if [ -f "$PONWRT_ROOT/tmp/fail-restart" ]; then rm "$PONWRT_ROOT/tmp/fail-restart"; exit 1; fi
MOCK
chmod +x "$tmp/bin/"* "$root/etc/init.d/rpcd"
run() { sh "$bundle/apply.sh" "$@"; }
must_fail() { if "$@"; then echo 'Unexpected success' >&2; exit 1; fi; }
run check
FAST_TEST_LUCI=other must_fail run install
[[ ! -e "$root/root/ponwrt-fast-ui/original" ]]
run install
for file in "$page" "$backend" "$acl"; do cmp "$root/$file" "$bundle/payload/$file"; done
[[ -x "$root/$backend" ]]
run install
touch "$root/tmp/fail-restart"
must_fail run install
cmp "$root/$page" "$tmp/original.js"
run install
sh "$root/root/ponwrt-fast-ui/rollback.sh" rollback
for file in "$page" "$backend" "$acl"; do
    if [[ -f "$tmp/before/$file" ]]; then cmp "$root/$file" "$tmp/before/$file"; else [[ ! -e "$root/$file" ]]; fi
done
echo tampered >> "$bundle/payload/$page"
must_fail run install
cmp "$root/$page" "$tmp/original.js"
echo 'PASS: compatibility, integrity, installation, repeat update, failed restart and rollback'
