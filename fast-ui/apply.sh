#!/bin/sh
set -eu
umask 077

bundle=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
# An alternate root is used to exercise install and rollback on a fixture.
root=${PONWRT_ROOT:-}
state="$root/root/ponwrt-fast-ui"
backup="$state/original"
version="$root/etc/ponwrt-version"
paths='usr/bin/ponwrt-update-check usr/share/rpcd/acl.d/luci-app-ponwrt-update.json www/luci-static/resources/view/system/flash.js'
action=${1:-check}
die() { echo "$*" >&2; exit 1; }

check_bundle() {
    (cd "$bundle" && sha256sum -c sha256sums)
    pin=$(sed -n 's/^ponwrt=//p' "$bundle/build-info")
    luci=$(sed -n 's/^luci=//p' "$bundle/build-info" | cut -c1-7)
    grep -Fqx "commit=$pin" "$version" || die 'PonWrt 基线版本不匹配'
    grep -Fqx 'target=an7581' "$version" || die 'SoC 不匹配'
    grep -Fqx 'device=nokia_xg-040g-md-ubi' "$version" || die '机型不匹配'
    for cmd in curl jsonfilter apk; do command -v "$cmd" >/dev/null || die "缺少依赖 $cmd"; done
    installed=$(apk list --quiet --installed --manifest --no-network --repositories-file /dev/null luci-mod-system)
    case "$installed" in "luci-mod-system "*~"$luci") ;; *) die "LuCI 版本不匹配 ($installed)";; esac
    [ -f "$root/www/luci-static/resources/view/system/flash.js" ] || die '找不到现有 LuCI 升级页'
    [ -x "$root/etc/init.d/rpcd" ] || die '找不到 rpcd 服务'
}

# Use a temporary file on the destination filesystem before each rename.
replace_files() {
    for rel in $paths; do
        dest="$root/$rel"
        if [ -f "$1/$rel" ]; then
            mkdir -p "$(dirname "$dest")" && cp -p "$1/$rel" "$dest.fast-ui-new" &&
                mv -f "$dest.fast-ui-new" "$dest" || return 1
        elif [ -f "$1/$rel.absent" ]; then
            rm -f "$dest" || return 1
        else
            return 1
        fi
    done
}

case "$action" in
    check|install) check_bundle ;;
    rollback) [ -d "$backup" ] || die '没有可恢复的快速更新备份' ;;
    *) die '用法: sh apply.sh check|install|rollback' ;;
esac
if [ "$action" = check ]; then echo '兼容性与校验通过'; exit 0; fi
[ -n "$root" ] || [ "$(id -u)" = 0 ] || die '请用 root 运行安装或回滚'
lock="$root/tmp/ponwrt-fast-ui.lock"
mkdir "$lock" || die '已有快速更新正在运行'
restore_on_exit=no
finish() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$restore_on_exit" = yes ]; then
        if replace_files "$backup" && "$root/etc/init.d/rpcd" restart; then
            echo '已恢复首次快速安装前的文件' >&2
        else
            echo '请检查可用空间后执行 rollback' >&2
        fi
    fi
    rmdir "$lock"
    exit "$rc"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
if [ -d "$backup" ]; then
    cmp -s "$backup/ponwrt-version" "$version" || die '已有备份来自另一版固件，请先移走旧备份'
else
    mkdir -p "$state"
    stage=$(mktemp -d "$state/backup.XXXXXX")
    cp -p "$version" "$stage/ponwrt-version"
    for rel in $paths; do
        mkdir -p "$(dirname "$stage/$rel")"
        if [ -f "$root/$rel" ]; then cp -p "$root/$rel" "$stage/$rel"; else touch "$stage/$rel.absent"; fi
    done
    cp "$bundle/apply.sh" "$state/rollback.sh"
    mv "$stage" "$backup"
fi
if [ "$action" = install ]; then
    restore_on_exit=yes
    replace_files "$bundle/payload" || die '写入更新失败'
    "$root/etc/init.d/rpcd" restart || die 'rpcd 重启失败'
    restore_on_exit=no
    echo '更新已安装，请强制刷新 LuCI 升级页'
else
    replace_files "$backup" || die '恢复文件失败，请检查空间后重新执行 rollback'
    "$root/etc/init.d/rpcd" restart || die '已还原文件，请重启 rpcd'
    echo '已恢复首次快速安装前的文件'
fi
