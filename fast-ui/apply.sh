#!/bin/sh
set -eu
umask 077

bundle=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
root=${PONWRT_ROOT:-}
state="$root/root/ponwrt-page-test"
backup="$state/original"
version="$root/etc/ponwrt-version"
page=www/luci-static/resources/view/system/flash.js
dest="$root/$page"
action=${1:-check}
die() { echo "$*" >&2; exit 1; }

case "$action" in
    check|install)
        (cd "$bundle" && sha256sum -c sha256sums)
        pin=$(sed -n 's/^ponwrt=//p' "$bundle/build-info")
        luci=$(sed -n 's/^luci=//p' "$bundle/build-info" | cut -c1-7)
        grep -Fqx "commit=$pin" "$version" || die 'PonWrt 基线版本不匹配'
        grep -Fqx 'target=an7581' "$version" || die 'SoC 不匹配'
        grep -Fqx 'device=nokia_xg-040g-md-ubi' "$version" || die '机型不匹配'
        installed=$(apk list --quiet --installed --manifest --no-network --repositories-file /dev/null luci-mod-system)
        case "$installed" in "luci-mod-system "*~"$luci") ;; *) die "LuCI 版本不匹配 ($installed)";; esac
        [ -f "$dest" ] || die '找不到现有 LuCI 升级页'
        [ -x "$root/usr/bin/ponwrt-update-check" ] || die '固件缺少现有更新后端'
        [ -f "$root/usr/share/rpcd/acl.d/luci-app-ponwrt-update.json" ] || die '固件缺少更新页权限文件'
        ;;
    rollback) [ -f "$backup/flash.js" ] || die '没有可恢复的页面备份' ;;
    *) die '用法: sh apply.sh check|install|rollback' ;;
esac
if [ "$action" = check ]; then echo '兼容性与校验通过'; exit 0; fi
[ -n "$root" ] || [ "$(id -u)" = 0 ] || die '请用 root 运行安装或回滚'
lock="$root/tmp/ponwrt-fast-ui.lock"
mkdir "$lock" || die '已有快速更新正在运行'
trap 'rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM
if [ -d "$backup" ]; then
    cmp -s "$backup/ponwrt-version" "$version" || die '备份来自另一版固件，请先移走旧备份'
else
    mkdir -p "$state"
    stage=$(mktemp -d "$state/backup.XXXXXX")
    cp -p "$version" "$stage/ponwrt-version"
    cp -p "$dest" "$stage/flash.js"
    cp "$bundle/apply.sh" "$state/rollback.sh"
    mv "$stage" "$backup"
fi
src="$bundle/payload/$page"
[ "$action" = install ] || src="$backup/flash.js"
tmp=$(mktemp "$dest.XXXXXX")
trap 'rm -f "$tmp"; rmdir "$lock"' EXIT
cp -p "$src" "$tmp"
mv -f "$tmp" "$dest"
echo '页面已替换，请强制刷新 LuCI 备份与更新页'
