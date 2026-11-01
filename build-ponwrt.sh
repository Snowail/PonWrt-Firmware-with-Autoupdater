#!/usr/bin/env bash
#
# 通用构建脚本：pbs05/ponwrt + 自定义 LuCI 主题/中文/常用插件
#
# 可用环境变量（统一 PONWRT_ 前缀，避免与 autotools 的通用变量撞名）：
#   PONWRT_SOC      SoC 目标，默认 an7581（可选 an7583）
#   PONWRT_DEVICE   设备 profile，默认 nokia_xg-040g-md-ubi
#   PONWRT_PIN      ponwrt 提交，默认 03c1345
#   PONWRT_JOBS     并发，默认按 nproc / 内存自动
#   PONWRT_SMOKE=1  冒烟测试：只编到 toolchain + libffi + ucode 就停
#   SRC_DIR         源码目录，默认 $HOME/ponwrt
#   OUT_DIR         产物目录，默认 $HOME/out
#
set -euo pipefail

# ---------------------------------------------------------------- 变量
# 绝对不能把 TARGET / DEVICE 这类通用名字以环境变量传给子 make：
# libffi 的 Makefile 里 TARGET 是“构建子目录名”，会被覆盖成 an7581，
# 导致 Build/InstallDev 阶段找不到 aarch64-openwrt-linux-*/fficonfig.h。
# 这里只接受 PONWRT_* 前缀，并兼容旧写法后立刻从环境里删掉。
SOC="${PONWRT_SOC:-${TARGET:-an7581}}"
DEV="${PONWRT_DEVICE:-${DEVICE:-nokia_xg-040g-md-ubi}}"
PIN="${PONWRT_PIN:-${PIN_COMMIT:-03c134544714617e196dd399c85ebb90fb6eefa1}}"
NJOBS="${PONWRT_JOBS:-${JOBS:-}}"
SMOKE_MODE="${PONWRT_SMOKE:-${SMOKE:-0}}"
DL_DIR="${PONWRT_DL:-}"
PKG_ONLY="${PONWRT_PKGS:-${PACKAGES_ONLY:-0}}"
unset TARGET DEVICE JOBS PIN_COMMIT SMOKE FORCE PACKAGES_ONLY \
      PONWRT_SOC PONWRT_DEVICE PONWRT_PIN PONWRT_JOBS PONWRT_SMOKE PONWRT_DL PONWRT_PKGS

REPO_URL="${REPO_URL:-https://github.com/pbs05/ponwrt.git}"
SRC_DIR="${SRC_DIR:-$HOME/ponwrt}"
OUT_DIR="${OUT_DIR:-$HOME/out}"
DATE_TAG="$(date -u +%Y%m%d-%H%M%S)"
DIAG_DIR="${DIAG_DIR:-$HOME/ponwrt-diagnostics}"
if [ -d "$DIAG_DIR" ] && [ -n "$(ls -A "$DIAG_DIR")" ]; then
  echo "!! 诊断目录必须为空: $DIAG_DIR"; exit 1
fi
mkdir -p "$DIAG_DIR"
LOG="$DIAG_DIR/build.log"

# 必须在 cd 之前算出脚本所在仓库的绝对路径（后面要取 overlay/ 和 tools/）
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/tools/build-lib.sh"

# 容器/root 下编译时，GNU tar 等 configure 会拒绝运行
export FORCE_UNSAFE_CONFIGURE=1

# ---- 镜像内附加软件包（按需增删）------------------------------------------
EXTRA_PACKAGES=(
  "CONFIG_LUCI_LANG_zh_Hans=y"              # LuCI 全量简体中文
  "CONFIG_PACKAGE_luci-theme-aurora=y"      # Aurora 主题（eamonxg/luci-theme-aurora）
  "CONFIG_PACKAGE_luci-compat=y"
  "CONFIG_PACKAGE_zerotier=y"
  "CONFIG_PACKAGE_luci-app-zerotier=y"
  "CONFIG_PACKAGE_iperf3=y"
  "CONFIG_PACKAGE_luci-app-nlbwmon=y"       # 设备列表 / 按设备流量
  "CONFIG_PACKAGE_curl=y"                    # 更新检查需要（支持代理）
  "CONFIG_PACKAGE_jsonfilter=y"
  "CONFIG_PACKAGE_ca-bundle=y"
  "CONFIG_PACKAGE_luci-app-ponwrt-update=y"   # 后端包，界面集成进备份/升级页
  "CONFIG_CCACHE_DIR=\"$HOME/ponwrt-ccache\""
)

exec > >(tee -a "$LOG") 2>&1
say() { printf '\n==> %s\n' "$*"; }
say "日志: $LOG"

collect_diagnostics() {
  local rc=$?
  trap - EXIT
  set +e
  printf '%s\n' "$rc" > "$DIAG_DIR/build-exit-code"
  if (( rc != 0 )); then preserve_failed_outputs; fi
  { df -h; free -h; } > "$DIAG_DIR/resources.txt" 2>&1
  dmesg --ctime > "$DIAG_DIR/kernel-messages.txt" 2>&1
  if [ -d "$SRC_DIR" ]; then
    for file in .config feeds.conf tmp/.config-package.in tmp/.packageinfo; do
      [ ! -f "$SRC_DIR/$file" ] || cp "$SRC_DIR/$file" "$DIAG_DIR/$(basename "$file")"
    done
    [ ! -d "$SRC_DIR/logs" ] || cp -a "$SRC_DIR/logs" "$DIAG_DIR/openwrt-logs"
    (cd "$SRC_DIR" && ./scripts/diffconfig.sh) > "$DIAG_DIR/diffconfig" 2>&1
    git -C "$SRC_DIR" diff > "$DIAG_DIR/upstream.patch"
  fi
  CCACHE_DIR="$HOME/ponwrt-ccache" ccache --show-stats > "$DIAG_DIR/ccache.txt" 2>&1
  exit "$rc"
}
trap collect_diagnostics EXIT

# ============================================================ 0. 预检
[ "$(uname -m)" = "x86_64" ] || { echo "!! 需要 x86_64 构建机"; exit 1; }
[[ "$SOC" =~ ^an758[13]$ && "$DEV" =~ ^[a-z0-9][a-z0-9_-]+$ && "$PIN" =~ ^[0-9a-f]{40}$ ]] \
  || { echo '!! 非法 SoC、profile 或 commit（必须是完整 SHA）'; exit 1; }
[[ "$SMOKE_MODE" =~ ^[01]$ && "$PKG_ONLY" =~ ^[01]$ && "$SMOKE_MODE$PKG_ONLY" != 11 ]] \
  || { echo '!! 冒烟模式和只编包模式不可同时开启'; exit 1; }
[[ -z "$NJOBS" || "$NJOBS" =~ ^[1-9][0-9]?$ ]] || { echo '!! jobs 必须为 1–99'; exit 1; }
# A clean source and output prevent stale files or the old overwritten package/Makefile.
[ ! -e "$SRC_DIR" ] || { echo "!! 请使用新的源码目录: $SRC_DIR"; exit 1; }
if [ -d "$OUT_DIR" ] && [ -n "$(ls -A "$OUT_DIR")" ]; then
  echo "!! 产物目录必须为空: $OUT_DIR"; exit 1
fi
CORES="$(nproc)"
MEM_MB="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"
FREE_GB="$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')"
# /etc/os-release exists on the Linux builder, not on the Windows lint host.
# shellcheck disable=SC1091
echo "系统: $(. /etc/os-release && echo "$PRETTY_NAME")  内核 $(uname -r)"
echo "CPU : ${CORES} 核  内存 ${MEM_MB} MB  可用磁盘 ${FREE_GB} GB"
MEM_JOBS="$(( MEM_MB / 1500 ))"; [ "$MEM_JOBS" -ge 1 ] || MEM_JOBS=1
NJOBS="${NJOBS:-$(( CORES < MEM_JOBS ? CORES : MEM_JOBS ))}"
[ "$NJOBS" -ge 1 ] || NJOBS=1
echo "并发: -j${NJOBS}   目标: ${SOC} / ${DEV}"

# ============================================================ 1. 依赖
say "[1/7] 安装编译依赖"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
  asciidoc autoconf automake autopoint binutils bison build-essential bzip2 ccache \
  clang cmake cpio curl device-tree-compiler flex gawk gettext git g++-multilib \
  gcc-multilib gperf help2man intltool libelf-dev libglib2.0-dev libgmp3-dev \
  libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev libreadline-dev \
  libssl-dev libtool libyaml-dev lld llvm ninja-build p7zip-full patch pkgconf \
  python3 python3-docutils python3-pip python3-ply python3-pyelftools qemu-utils \
  re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs unzip wget \
  xmlto xxd zlib1g-dev zstd file time nodejs

# ============================================================ 2. 源码
say "[2/7] 获取 ponwrt 源码 @ ${PIN:0:9}"
git init "$SRC_DIR"
cd "$SRC_DIR"
git remote add origin "$REPO_URL"
git fetch --depth=1 origin "$PIN"
git checkout --detach FETCH_HEAD
[ "$(git rev-parse HEAD)" = "$PIN" ]
echo "commit: $(git rev-parse HEAD)  $(git log -1 --format='%cd %s' --date=short)"

# 可选的持久化下载缓存（CI 用）：把源码树里的 dl/ 指到缓存目录
if [ -n "$DL_DIR" ]; then
  mkdir -p "$DL_DIR"
  ln -s "$DL_DIR" dl
  echo "dl 缓存: $DL_DIR"
fi

# ============================================================ 3. feeds
say "[3/7] 安装 feeds"
python3 "$REPO_DIR/tools/source-lock.py" prepare "$REPO_DIR/sources.lock.json" "$SRC_DIR"
./scripts/feeds update -a 2>&1 | tee "$DIAG_DIR/feeds-update.log"

say "[3b/7] 固定 Aurora 主题版本"
AURORA_FEED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["aurora"]["url"])' "$REPO_DIR/sources.lock.json")"
AURORA_PIN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["aurora"]["commit"])' "$REPO_DIR/sources.lock.json")"
git init package/luci-theme-aurora
git -C package/luci-theme-aurora remote add origin "$AURORA_FEED"
git -C package/luci-theme-aurora fetch --depth=1 origin "$AURORA_PIN"
git -C package/luci-theme-aurora checkout --detach FETCH_HEAD
python3 "$REPO_DIR/tools/source-lock.py" verify "$REPO_DIR/sources.lock.json" "$SRC_DIR" > "$DIAG_DIR/sources-resolved.json"

say "[3d/7] 正确组装更新后端包并修补现有升级页面"
PKG="package/luci-app-ponwrt-update"
mkdir -p "$PKG"
cp -a "$REPO_DIR/package/luci-app-ponwrt-update/." "$PKG/"
mkdir -p "$PKG/root"
cp -a "$REPO_DIR/overlay/." "$PKG/root/"
chmod +x "$PKG/root/usr/bin/ponwrt-update-check"
git diff --exit-code -- package/Makefile
./scripts/feeds install -a 2>&1 | tee "$DIAG_DIR/feeds-install.log"

FLASH_JS="feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js"
if [ -f "$FLASH_JS" ]; then
  python3 "$REPO_DIR/tools/patch-flash.py" "$FLASH_JS"
  HEADER="feeds/luci/modules/luci-base/ucode/template/header.ut"
  grep -Fq 'sessionid' "$HEADER" && grep -Fq 'ctx.authsession' "$HEADER" || { echo '缺少 LuCI 登录模板'; exit 1; }
  cat "$REPO_DIR/tools/ponwrt-banner.ut" >> "$HEADER"
  node --check "$FLASH_JS"
  node "$REPO_DIR/tests/test-flash-page.js" "$FLASH_JS"
  cp "$FLASH_JS" "$DIAG_DIR/flash.js"
else
  echo "  !! 未找到 $FLASH_JS"; exit 1
fi

# 双保险：libffi 3.4.7 自带 PKG_BUILD_PARALLEL:=1，其 make -j 也可能出问题
say "[3c/7] 关闭 libffi 的并行编译"
sed -i 's/^PKG_BUILD_PARALLEL:=1$/PKG_BUILD_PARALLEL:=0/' package/libs/libffi/Makefile
if ! grep -q '^PKG_BUILD_PARALLEL:=0$' package/libs/libffi/Makefile; then
  echo "  !! 未能修改 libffi Makefile"; exit 1
fi
echo "  OK   libffi 已改为串行编译"

# ============================================================ 4. 配置
say "[4/7] 生成 .config 并叠加定制项"
python3 "$REPO_DIR/tools/prepare-config.py" "configs/${SOC}.config" .config "$SOC" "$DEV" "${EXTRA_PACKAGES[@]}"
logged_make defconfig defconfig
grep -q 'config PACKAGE_luci-app-ponwrt-update' tmp/.config-package.in \
  || { echo '!! 包元数据中未发现更新插件'; exit 1; }

echo "---- 定制项确认 ----"
for line in "${EXTRA_PACKAGES[@]}"; do
  if grep -Fxq "$line" .config; then echo "  OK   $line"; else echo "  MISS $line"; exit 1; fi
done
SELECTED="$(grep -Ec '^CONFIG_TARGET_DEVICE_.*_DEVICE_.*=y$' .config || true)"
[ "$SELECTED" = 1 ] || { echo "!! 选中的机型数量异常: $SELECTED"; exit 1; }
if ! grep -Fxq "CONFIG_TARGET_DEVICE_airoha_${SOC}_DEVICE_${DEV}=y" .config; then
  echo "  !! 设备 ${DEV} 未启用，终止"; exit 1
fi
echo "  OK   设备 ${DEV}"

# ---- 通用 uci-defaults（不含任何个人数据）----
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/90-ponwrt-theme-lang <<'UCI'
#!/bin/sh
[ -f /etc/config/luci ] || exit 0
uci -q batch <<-EOF
	set luci.main.mediaurlbase='/luci-static/aurora'
	set luci.main.lang='zh_cn'
	commit luci
EOF
exit 0
UCI
cat > files/etc/uci-defaults/91-ponwrt-lan-ip <<'UCI'
#!/bin/sh
[ -f /etc/config/network ] || exit 0
uci -q batch <<-EOF
	set network.lan.ipaddr='10.0.0.1'
	set network.lan.netmask='255.255.255.0'
	set dhcp.lan.start='100'
	set dhcp.lan.limit='150'
	commit network
	commit dhcp
EOF
exit 0
UCI
chmod +x files/etc/uci-defaults/90-ponwrt-theme-lang files/etc/uci-defaults/91-ponwrt-lan-ip

# ---- 版本标记：供在线更新检查对比 ----
mkdir -p files/etc
cat > files/etc/ponwrt-version <<VER
commit=${PIN}
device=${DEV}
target=${SOC}
built=${DATE_TAG}
VER

# ============================================================ 5. 下载
say "[5/7] 预下载源码包"
run_make download download
# Some upstream download recipes print a failure but still return zero.
if grep -Eq 'build failed|ERROR: .*failed' "$DIAG_DIR/download-parallel.log" \
   && [ ! -f "$DIAG_DIR/download-serial.log" ]; then
  logged_make download-serial -j1 V=s download
fi
DOWNLOAD_LOG="$DIAG_DIR/download-serial.log"
[ -f "$DOWNLOAD_LOG" ] || DOWNLOAD_LOG="$DIAG_DIR/download-parallel.log"
if grep -Eq 'build failed|ERROR: .*failed' "$DOWNLOAD_LOG"; then
  echo '!! 下载日志仍有失败记录，停止编译'; exit 1
fi
touch "$DIAG_DIR/download.ok"

# ============================================================ 6. 编译
# 仅编译更新插件相关的三个包（给已刷旧固件的机器单独安装用）
if [ "${PKG_ONLY}" = "1" ]; then
  say "[6/7] PACKAGES_ONLY=1：只编 luci-app-ponwrt-update / curl / jsonfilter"
  run_make tools tools/install
  run_make toolchain toolchain/install
  run_make packages package/luci-app-ponwrt-update/compile package/feeds/packages/curl/compile package/utils/jsonfilter/compile
  python3 "$REPO_DIR/tools/collect-artifacts.py" packages "$SRC_DIR" "$OUT_DIR" "$SOC" "$DEV"
  ls -lh "$OUT_DIR"
  say "打包完成"
  exit 0
fi

if [ "${SMOKE_MODE}" = "1" ]; then
  say "[6/7] SMOKE=1：只验证 toolchain + libffi + ucode"
  run_make tools tools/install
  run_make toolchain toolchain/install
  run_make libffi package/libs/libffi/compile
  run_make ucode package/utils/ucode/compile
  say "冒烟测试通过（toolchain + libffi + ucode）"
  exit 0
fi

say "[6/7] 编译（-j${NJOBS}）"
run_make world
touch "$DIAG_DIR/compile.ok"

# ============================================================ 7. 产物
say "[7/7] 收集产物"
python3 "$REPO_DIR/tools/collect-artifacts.py" firmware "$SRC_DIR" "$OUT_DIR" "$SOC" "$DEV"
ls -lh "$OUT_DIR"
say "完成"
