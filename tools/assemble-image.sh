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
VERSION="$WORK_DIR/source/files/etc/ponwrt-version"
printf 'commit=%s\ndevice=%s\ntarget=%s\nbuilt=%s\n' \
    "$PONWRT_PIN" "$PONWRT_DEVICE" "$PONWRT_SOC" "$(date -u +%Y%m%d-%H%M%S)" > "$VERSION"
PACKAGES="$(tr '\n' ' ' < "$BASE_DIR/packages.txt")"
make -C "$WORK_DIR/ib" image PROFILE="$PONWRT_DEVICE" PACKAGES="$PACKAGES" \
    FILES="$WORK_DIR/source/files" BIN_DIR="$WORK_DIR/source/bin/targets/airoha/$PONWRT_SOC" \
    CONFIG_TARGET_ROOTFS_INITRAMFS= ROOTFS_FILESYSTEM=squashfs ADD_LOCAL_KEY=1
python3 "$REPO_DIR/tools/collect-artifacts.py" imagebuilder "$WORK_DIR/source" "$OUT_DIR" "$PONWRT_SOC" "$PONWRT_DEVICE"
manifest=("$OUT_DIR"/*.manifest)
while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    grep -q "^$pkg " "${manifest[0]}" || { echo "Missing package: $pkg"; exit 1; }
done < "$REPO_DIR/public-packages.txt"
if [[ "$PONWRT_DEVICE" == nokia_xg-040g-md-ubi ]]; then
    image_bytes=$(stat -c %s "$OUT_DIR"/*-squashfs-sysupgrade.itb)
    (( image_bytes <= 192 * 1024 * 1024 ))
fi
