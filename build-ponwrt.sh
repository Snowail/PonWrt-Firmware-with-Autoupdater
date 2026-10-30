#!/usr/bin/env bash
#
# 通用构建脚本：pbs05/ponwrt + 自定义 LuCI 主题/中文/常用插件
#
# 可用环境变量：
#   TARGET      soctarget，默认 an7581（可选 an7583）
#   DEVICE      设备 profile，默认 nokia_xg-040g-md-ubi
#   PIN_COMMIT  ponwrt 提交，默认 03c1345
#   JOBS        并发，默认 nproc
#   SRC_DIR     源码目录，默认 $HOME/ponwrt
#   OUT_DIR     产物目录，默认 $HOME/out
#   REPO_URL    ponwrt 仓库地址
#
# 产物：$OUT_DIR 下的 squashfs-sysupgrade.itb / initramfs-recovery.itb / sha256sums
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/pbs05/ponwrt.git}"
SRC_DIR="${SRC_DIR:-$HOME/ponwrt}"
TARGET="${TARGET:-an7581}"
DEVICE="${DEVICE:-nokia_xg-040g-md-ubi}"
PIN_COMMIT="${PIN_COMMIT:-03c134544714617e196dd399c85ebb90fb6eefa1}"
JOBS="${JOBS:-$(nproc)}"
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
JOBS="${JOBS:-$(( CORES < MEM_JOBS ? CORES : MEM_JOBS ))}"
[ "$JOBS" -ge 1 ] || JOBS=1
echo "并发: -j$JOBS   目标: $TARGET / $DEVICE"

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
say "[2/7] 获取 ponwrt 源码 @ ${PIN_COMMIT:0:9}"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" fetch --all --tags --prune
else
  git clone "$REPO_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"
git checkout "$PIN_COMMIT"
echo "commit: $(git rev-parse HEAD)  $(git log -1 --format='%cd %s' --date=short)"

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

# libffi 3.4.7 自带 PKG_BUILD_PARALLEL:=1，其 make -j 会偶发不生成
# aarch64-*/fficonfig.h，导致 Build/InstallDev 的 cp 失败。这里关掉它的并行。
say "[3c/7] 关闭 libffi 的并行编译"
sed -i 's/^PKG_BUILD_PARALLEL:=1$/PKG_BUILD_PARALLEL:=0/' package/libs/libffi/Makefile
grep -q '^PKG_BUILD_PARALLEL:=0$' package/libs/libffi/Makefile \
  && echo "  OK   libffi 已改为串行编译" \
  || { echo "  !! 未能修改 libffi Makefile"; exit 1; }

# ============================================================ 4. 配置
say "[4/7] 生成 .config 并叠加定制项"
cp "configs/${TARGET}.config" .config
printf '%s\n' "${EXTRA_PACKAGES[@]}" >> .config
make defconfig

echo "---- 定制项确认 ----"
for line in "${EXTRA_PACKAGES[@]}"; do
  if grep -qx "$line" .config; then echo "  OK   $line"; else echo "  MISS $line"; fi
done
grep -q "^CONFIG_TARGET_DEVICE_airoha_${TARGET}_DEVICE_${DEVICE}=y" .config \
  && echo "  OK   设备 $DEVICE" \
  || { echo "  !! 设备 $DEVICE 未启用，终止"; exit 1; }

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
commit=${PIN_COMMIT}
device=${DEVICE}
target=${TARGET}
built=${DATE_TAG}
VER

# ============================================================ 5. 下载
say "[5/7] 预下载源码包"
make download -j4 || make download -j1 V=s

# ============================================================ 6. 编译
say "[6/7] 编译（-j$JOBS）"

# libffi 的 Makefile 在高并发下会偶发 race：configure 的 stamp 已写、
# 但 fficonfig.h 没生成，安装阶段就 cp 不到文件。先串行单独编它，
# 之后的 world 编译就不会再碰（也不会留下半成品状态）。
say "预编译 libffi（串行，规避并行 race）"
make -j"$JOBS" toolchain/compile
make -j1 package/libs/libffi/clean
make -j1 package/libs/libffi/host-compile package/libs/libffi/compile

# 冒烟测试：只验证到 ucode（libffi 的直接依赖方）就停，用于快速验证工具链
if [ "${SMOKE:-0}" = "1" ]; then
  say "SMOKE=1：验证 ucode 编译后退出"
  make -j1 package/utils/ucode/compile
  say "冒烟测试通过（toolchain + libffi + ucode）"
  exit 0
fi

say "开始 world 编译"
if ! make -j"$JOBS"; then
  FAILED="$(grep -oE 'ERROR: (package|feeds)/[^ ]+ failed' "$LOG" | tail -1 | awk '{print $2}')"
  say "并行编译失败（$FAILED），清理该包后改用 -j1 V=s 重试"
  [ -n "${FAILED:-}" ] && make "$FAILED/clean" || true
  make -j1 V=s || { echo "!! 编译失败"; exit 1; }
fi

# ============================================================ 7. 产物
say "[7/7] 收集产物"
BIN="bin/targets/airoha/${TARGET}"
mkdir -p "$OUT_DIR"
cp "$BIN"/sha256sums "$OUT_DIR"/ 2>/dev/null || true
cp "$BIN"/ponwrt-*"${DEVICE}"-squashfs-sysupgrade.itb "$OUT_DIR"/ 2>/dev/null || true
cp "$BIN"/ponwrt-*"${DEVICE}"-initramfs-recovery.itb "$OUT_DIR"/ 2>/dev/null || true
cp "$BIN"/ponwrt-*"${DEVICE}".manifest "$OUT_DIR"/ 2>/dev/null || true
cp files/etc/ponwrt-version "$OUT_DIR"/ 2>/dev/null || true
ls -lh "$OUT_DIR"
say "完成"
