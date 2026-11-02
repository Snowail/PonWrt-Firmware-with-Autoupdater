#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${PONWRT_SOC:?}" "${PONWRT_DEVICE:?}" "${PONWRT_PIN:?}"
BASE_DIR="${BASE_DIR:-$HOME/base}"
WORK_DIR="${WORK_DIR:-$HOME/imagebuilder-work}"
OUT_DIR="${OUT_DIR:-$HOME/out}"
[[ "$PONWRT_SOC" =~ ^an758[13]$ && "$PONWRT_DEVICE" =~ ^[a-z0-9][a-z0-9_-]+$ ]]
[[ "$PONWRT_PIN" =~ ^[0-9a-f]{40}$ ]]
[[ ! -e "$WORK_DIR" && ! -e "$OUT_DIR" ]]
(cd "$BASE_DIR" && sha256sum -c sha256sums)
python3 - "$BASE_DIR/base.json" "$PONWRT_SOC" "$PONWRT_DEVICE" "$PONWRT_PIN" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data['soc'] == sys.argv[2] and data['commit'] == sys.argv[4]
assert sys.argv[3] in data['devices']
PY
mkdir -p "$WORK_DIR/ib" "$WORK_DIR/source/bin/targets/airoha/$PONWRT_SOC"
tar --zstd -xf "$BASE_DIR/imagebuilder.tar.zst" -C "$WORK_DIR/ib" --strip-components=1
cp -a "$BASE_DIR/files" "$WORK_DIR/source/files"
chmod +x "$WORK_DIR/source/files/etc/uci-defaults/"*
# Runtime files are assembled fresh so UI/backend changes can reuse the kernel base.
cp -a "$REPO_DIR/overlay/." "$WORK_DIR/source/files/"
cp "$REPO_DIR/tools/99-ponwrt-service-defaults" "$WORK_DIR/source/files/etc/uci-defaults/"
chmod +x "$WORK_DIR/source/files/etc/uci-defaults/"* "$WORK_DIR/source/files/usr/bin/ponwrt-update-check"
luci_pin="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["feeds"]["luci"]["commit"])' "$REPO_DIR/sources.lock.json")"
page="$WORK_DIR/source/files/www/luci-static/resources/view/system/flash.js"
header="$WORK_DIR/source/files/usr/share/ucode/luci/template/header.ut"
mkdir -p "$(dirname "$page")" "$(dirname "$header")"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/immortalwrt/luci/$luci_pin/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js" -o "$page"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/immortalwrt/luci/$luci_pin/modules/luci-base/ucode/template/header.ut" -o "$header"
python3 "$REPO_DIR/tools/patch-flash.py" "$page"
cat "$REPO_DIR/tools/ponwrt-banner.ut" >> "$header"
node --check "$page"
node "$REPO_DIR/tests/test-flash-page.js" "$page"
samba_page="$WORK_DIR/source/files/www/luci-static/resources/view/samba4.js"
samba_acl="$WORK_DIR/source/files/usr/share/rpcd/acl.d/luci-app-samba4.json"
mkdir -p "$(dirname "$samba_acl")"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/immortalwrt/luci/$luci_pin/applications/luci-app-samba4/htdocs/luci-static/resources/view/samba4.js" -o "$samba_page"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/immortalwrt/luci/$luci_pin/applications/luci-app-samba4/root/usr/share/rpcd/acl.d/luci-app-samba4.json" -o "$samba_acl"
python3 "$REPO_DIR/tools/patch-samba.py" "$samba_page" "$samba_acl"
node --check "$samba_page"
node "$REPO_DIR/tests/test-samba-page.js" "$samba_page"
VERSION="$WORK_DIR/source/files/etc/ponwrt-version"
printf 'commit=%s\ndevice=%s\ntarget=%s\nbuilt=%s\n' \
    "$PONWRT_PIN" "$PONWRT_DEVICE" "$PONWRT_SOC" "$(date -u +%Y%m%d-%H%M%S)" > "$VERSION"
python3 - "$BASE_DIR/base-profiles.json" "$VERSION" "${UPSTREAM_TIME:?}" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
kernel = json.load(open(sys.argv[1]))['linux_kernel']['version']
stamp = datetime.fromisoformat(sys.argv[3].replace('Z', '+00:00'))
display = f"{kernel} / {stamp.astimezone(timezone(timedelta(hours=8))):%Y-%m-%d %H:%M:%S}"
with open(sys.argv[2], 'a') as stream:
    stream.write(f"kernel={kernel}\nupstream_time={sys.argv[3]}\ndisplay_version={display}\n")
PY
PACKAGES="$(python3 "$REPO_DIR/tools/imagebuilder-packages.py" "$WORK_DIR/ib" "$BASE_DIR/packages.txt" "$REPO_DIR/public-packages.txt")"
make -C "$WORK_DIR/ib" image PROFILE="$PONWRT_DEVICE" PACKAGES="$PACKAGES" \
    FILES="$WORK_DIR/source/files" BIN_DIR="$WORK_DIR/source/bin/targets/airoha/$PONWRT_SOC" \
    CONFIG_TARGET_ROOTFS_INITRAMFS= ROOTFS_FILESYSTEM=squashfs ADD_LOCAL_KEY=1 \
    DISABLED_SERVICES="tailscale samba4"
python3 "$REPO_DIR/tools/collect-artifacts.py" imagebuilder "$WORK_DIR/source" "$OUT_DIR" "$PONWRT_SOC" "$PONWRT_DEVICE"
manifest=("$OUT_DIR"/*.manifest)
while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    grep -q "^$pkg " "${manifest[0]}" || { echo "Missing package: $pkg"; exit 1; }
done < "$REPO_DIR/public-packages.txt"
if [[ "$PONWRT_DEVICE" == nokia_xg-040g-md-ubi ]]; then
    image_bytes=$(stat -c %s "$OUT_DIR"/*-squashfs-sysupgrade.itb)
    (( image_bytes <= 192 * 1024 * 1024 ))
fi
