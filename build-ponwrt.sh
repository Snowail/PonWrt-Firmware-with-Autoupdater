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
unset TARGET DEVICE JOBS PIN_COMMIT SMOKE FORCE \
      PONWRT_SOC PONWRT_DEVICE PONWRT_PIN PONWRT_JOBS PONWRT_SMOKE PONWRT_DL

REPO_URL="${REPO_URL:-https://github.com/pbs05/ponwrt.git}"
SRC_DIR="${SRC_DIR:-$HOME/ponwrt}"
OUT_DIR="${OUT_DIR:-$HOME/out}"
AURORA_FEED="${AURORA_FEED:-https://github.com/eamonxg/luci-theme-aurora.git}"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG="$HOME/ponwrt-build-$DATE_TAG.log"

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
)

exec > >(tee -a "$LOG") 2>&1
say() { printf '\n==> %s\n' "$*"; }
say "日志: $LOG"

# ============================================================ 0. 预检
[ "$(uname -m)" = "x86_64" ] || { echo "!! 需要 x86_64 构建机"; exit 1; }
CORES="$(nproc)"
MEM_MB="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"
FREE_GB="$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')"
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
  xmlto xxd zlib1g-dev zstd file time
$SUDO apt-get install -y --no-install-recommends python3-distutils 2>/dev/null || true

# ============================================================ 2. 源码
say "[2/7] 获取 ponwrt 源码 @ ${PIN:0:9}"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" fetch --all --tags --prune
else
  git clone "$REPO_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"
git checkout "$PIN"
echo "commit: $(git rev-parse HEAD)  $(git log -1 --format='%cd %s' --date=short)"

# 可选的持久化下载缓存（CI 用）：把源码树里的 dl/ 指到缓存目录
if [ -n "$DL_DIR" ]; then
  mkdir -p "$DL_DIR"
  rm -rf dl
  ln -s "$DL_DIR" dl
  echo "dl 缓存: $DL_DIR"
fi

# ============================================================ 3. feeds
say "[3/7] 安装 feeds"
cp -f feeds.conf.default feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a

say "[3b/7] 取 Aurora 主题（仓库根目录即一个 LuCI 包，需放进 package/）"
if [ ! -f package/luci-theme-aurora/Makefile ]; then
  rm -rf package/luci-theme-aurora
  git clone --depth 1 "$AURORA_FEED" package/luci-theme-aurora
  rm -rf package/luci-theme-aurora/.git
fi

say "[3d/7] 注入 overlay（更新检查脚本 + ACL）并给备份/升级页打补丁"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p files
[ -d "$REPO_DIR/overlay" ] && cp -a "$REPO_DIR/overlay/." files/
chmod +x files/usr/bin/ponwrt-update-check 2>/dev/null || true

FLASH_JS="feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js"
if [ -f "$FLASH_JS" ]; then
  python3 "$REPO_DIR/tools/patch-flash.py" "$FLASH_JS"
  if command -v node >/dev/null 2>&1; then
    node --check "$FLASH_JS" && echo "  OK   flash.js 语法检查通过"
  fi
else
  echo "  !! 未找到 $FLASH_JS，跳过补丁"
fi

# 双保险：libffi 3.4.7 自带 PKG_BUILD_PARALLEL:=1，其 make -j 也可能出问题
say "[3c/7] 关闭 libffi 的并行编译"
sed -i 's/^PKG_BUILD_PARALLEL:=1$/PKG_BUILD_PARALLEL:=0/' package/libs/libffi/Makefile
grep -q '^PKG_BUILD_PARALLEL:=0$' package/libs/libffi/Makefile \
  && echo "  OK   libffi 已改为串行编译" \
  || { echo "  !! 未能修改 libffi Makefile"; exit 1; }

# ============================================================ 4. 配置
say "[4/7] 生成 .config 并叠加定制项"
cp "configs/${SOC}.config" .config
printf '%s\n' "${EXTRA_PACKAGES[@]}" >> .config
make defconfig

echo "---- 定制项确认 ----"
for line in "${EXTRA_PACKAGES[@]}"; do
  if grep -qx "$line" .config; then echo "  OK   $line"; else echo "  MISS $line"; fi
done
grep -q "^CONFIG_TARGET_DEVICE_airoha_${SOC}_DEVICE_${DEV}=y" .config \
  && echo "  OK   设备 ${DEV}" \
  || { echo "  !! 设备 ${DEV} 未启用，终止"; exit 1; }

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
make download -j4 || make download -j1 V=s

# ============================================================ 6. 编译
if [ "${SMOKE_MODE}" = "1" ]; then
  say "[6/7] SMOKE=1：只验证 toolchain + libffi + ucode"
  make -j"${NJOBS}" toolchain/compile
  make -j1 package/libs/libffi/clean
  make -j1 package/libs/libffi/compile V=s
  make -j1 package/utils/ucode/compile V=s
  say "冒烟测试通过（toolchain + libffi + ucode）"
  exit 0
fi

say "[6/7] 编译（-j${NJOBS}）"
if ! make -j"${NJOBS}"; then
  FAILED="$(grep -oE 'ERROR: (package|feeds)/[^ ]+ failed' "$LOG" | tail -1 | awk '{print $2}')"
  say "并行编译失败（${FAILED:-未知}），清理该包后改用 -j1 V=s 重试"
  [ -n "${FAILED:-}" ] && make "$FAILED/clean" || true
  make -j1 V=s || { echo "!! 编译失败"; exit 1; }
fi

# ============================================================ 7. 产物
say "[7/7] 收集产物"
BIN="bin/targets/airoha/${SOC}"
mkdir -p "$OUT_DIR"
cp "$BIN"/sha256sums "$OUT_DIR"/ 2>/dev/null || true
cp "$BIN"/ponwrt-*"${DEV}"-squashfs-sysupgrade.itb "$OUT_DIR"/ 2>/dev/null || true
cp "$BIN"/ponwrt-*"${DEV}"-initramfs-recovery.itb "$OUT_DIR"/ 2>/dev/null || true
cp "$BIN"/ponwrt-*"${DEV}".manifest "$OUT_DIR"/ 2>/dev/null || true
cp files/etc/ponwrt-version "$OUT_DIR"/ 2>/dev/null || true
ls -lh "$OUT_DIR"
say "完成"
