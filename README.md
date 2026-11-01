# PonWrt Firmware (Airoha AN7581 / AN7583) with Autoupdater

本仓库用 GitHub Actions 自动构建 **pbs05/ponwrt** 固件（ImmortalWrt + Airoha AN7581/AN7583 的 PON 支持），
并叠加了一套通用定制：Aurora 主题、简体中文、常用插件、固定 LAN 网段。

[完整构建 #17](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41230731864) 已生成 Nokia MD UBI 镜像。在测试机验证“备份与更新”页面时，选择 **Actions → Test backup and update page**。快速包只替换页面。正式发布时，完整固件内置同一页面补丁。新增软件包随上游版本更新再编译。[页面测试与回滚](fast-ui/README.md)

---

## 一、固件来源

| 项目 | 来源 |
| --- | --- |
| 基础固件 | [pbs05/ponwrt](https://github.com/pbs05/ponwrt) —— 基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)，加入 Airoha AN7581 / AN7583 的 **PON 驱动** |
| 上游框架 | [OpenWrt](https://github.com/openwrt/openwrt) / [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) |
| LuCI 主题 | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)（Apache-2.0），本仓库以本地包方式编译进镜像 |
| 中文语言包 | ImmortalWrt luci feed，通过 `CONFIG_LUCI_LANG_zh_Hans=y` 全量启用 |
| 网页 U-Boot（刷机用） | [Loong1996/ImmortalWrt-Airoha](https://github.com/Loong1996/ImmortalWrt-Airoha) 的 Web U-Boot |

> ⚠️ 这是**第三方自编译固件**，与 Nokia、运营商、pbs05 均无隶属关系。风险自负。

## 二、公版构建配置

- **LuCI 简体中文** + **Aurora 主题**（首次启动自动设为默认主题与中文）
- **默认 LAN：`10.0.0.1/24`**，DHCP 池 `10.0.0.100–10.0.0.249`

### 公版额外软件包

| 用途 | 内置项目 |
|---|---|
| 界面、升级 | `luci-theme-aurora`、LuCI 简体中文、`luci-compat`、`luci-app-ponwrt-update`、`curl`、`jsonfilter`、`ca-bundle` |
| DNS | `adguardhome`、`luci-app-adguardhome` |
| 分流与公网服务 | `lucky`、`luci-app-lucky`、`frpc`、`luci-app-frpc` |
| 域名、唤醒与 NAT | `luci-app-ddns`、`ddns-scripts`、`ddns-scripts-services`、`luci-app-wol`、`luci-app-upnp`、`miniupnpd-nftables` |
| 远程组网 | `zerotier`、`luci-app-zerotier`、`tailscale`、`luci-app-tailscale-community`、`wireguard-tools`、`kmod-wireguard`、`luci-proto-wireguard` |
| 带宽与监控 | `nlbwmon`、`luci-app-nlbwmon`（按终端统计） |
| 文件与共享 | `openssh-sftp-server`、`samba4-server`、`luci-app-samba4` |
| 诊断 | `iperf3`、`bind-dig`、`ethtool-full`、`htop` |

全新安装默认关闭 AdGuard Home、Lucky 和 UPnP。由用户在 LuCI 中选择是否启用。保留配置升级时沿用已保存的服务设置。完整固件的实际依赖与版本见该次 Release 附带的 `.manifest`。

## 三、已验证机型与构建方式

本仓库已在 Nokia XG-040G-MD（AN7581、UBI 布局）上运行 #17 固件，并在该机上验证了新版 LuCI 页面及在线版本检查。对应的设备 profile 为 `nokia_xg-040g-md-ubi`。

每次完整构建读取指定上游提交的 `configs/an7581.config` 和 `configs/an7583.config`，为其中每个启用的 profile 创建独立并行任务。设备列表随上游更新。各任务分别校验 sysupgrade、上游列出的附加镜像、软件包清单和 SHA256。实机验证范围为 Nokia MD UBI，下方刷机说明针对该机型。

## 四、获取与构建

### 直接下载（推荐）

**Releases** 里是已经构建好的镜像，不用自己编译。命名规则：

| 名称 | 含义 |
| --- | --- |
| Release tag：`<device_profile>-<YYYYMMDD-HHMMSS>-<run_id>-<attempt>` | 设备、UTC 构建时间、Actions 运行 ID 和尝试次数 |
| Release 标题：`<device_profile> <tag>` | 同一 tag |
| `ponwrt-airoha-<soc>-<device_profile>-squashfs-sysupgrade.itb` | **正式固件**，U-Boot「日常刷机」用 |
| `ponwrt-airoha-<soc>-<device_profile>-initramfs-recovery.itb` | **试跑固件**，U-Boot「试跑固件」用 |
| `sha256sums` | 所有镜像的 SHA256 校验值 |
| `ponwrt-version` | 编译时的 commit / 设备 / 时间 |

例：`ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-squashfs-sysupgrade.itb`
= SoC `an7581` + 设备 `nokia_xg-040g-md-ubi` 的正式固件。

### 方式 A：GitHub Actions 自行编译

**Actions → Build ponwrt firmware → Run workflow**，参数：

- `pin_commit`：留默认（`03c1345`）
- `jobs`：`4`
- `make_release`：需要发 Release 时勾上
- `smoke_only`：只编到 toolchain + libffi + ucode 就停，用于快速验证（约 50–70 分钟）

构建时间取决于 runner、网络与缓存；完整构建 #17 约耗时 103 分钟。每个 job 构建对应机型的镜像，并保留上游的软件包选择。并行缩短多机型全部完成的等待时间，不会增加单个 runner 的算力。

> 只有勾选 `make_release` 的构建才会发 Release；平时手动触发的构建只上传 **Artifact**（保留 30 天），在运行页面下载。

`dl/`、ccache 和工具链分别缓存。ccache 保留 4 GB 上限，使用编译器内容校验，后续编译失败也保存已积累缓存。工具链仅精确匹配上游 SHA、完整配置、构建脚本、锁定 feeds 和 runner/系统包版本时恢复；恢复后仍执行 make 依赖检查。工具链成功就保存，无需等待固件完成。Rust 等 `hostpkg` 不包含在工具链缓存中。

缓存命中后的实际提速需通过后续 Actions 日志测量；首次构建仍需填充缓存。同一 SoC 的机型共享下载缓存和 ccache，由首个 profile 负责写入。多机型缓存共用仓库配额，旧缓存可能被 GitHub 淘汰，未配置付费 runner 或提高付费存储限额。源码和 feeds/主题版本通过 commit 与 `sources.lock.json` 固定。

### 跟随上游更新

Actions 的 **Check upstream PonWrt** 每 15 分钟检查一次 `pbs05/ponwrt` 默认分支，也可手动运行。发现新提交后，工作流锁定该 SHA，按对应上游配置为全部启用机型并行编译完整镜像并分别上传 Artifact。feeds 和主题沿用仓库锁定版本。若有构建正在排队或执行，监测会等到后续检查再选取最新提交。已记录的同一提交跳过重复构建；失败可在原运行中重试。验证 Artifact 后，可在手动构建中填入该 SHA 并勾选 `make_release` 发布正式版。

完整编译使用 4 GB ccache。优先恢复同一上游提交的缓存，更新提交时可复用同 SoC 的缓存。

### 方式 B：本地 / 自己的服务器

```bash
bash ./build-ponwrt.sh          # 安装依赖时使用 sudo；产物放 ~/out
# 可选参数：
PONWRT_SOC=an7581 PONWRT_DEVICE=nokia_xg-040g-md-ubi PONWRT_JOBS=8 bash ./build-ponwrt.sh
```

要求：Ubuntu 22.04/24.04 x86_64、≥4 核、≥8 GB 内存、≥40 GB 磁盘（首次全量约 20–25 GB）。

每次使用新的 `SRC_DIR`、空 `OUT_DIR` 和空 `DIAG_DIR`，避免历史构建污染；可复用外部下载缓存与 ccache。诊断默认放 `~/ponwrt-diagnostics`。

### 方式 C：Docker（FreeBSD/TrueNAS 等不方便装依赖的环境）

```bash
docker run -d --name ponwrt --network host \
  -v /path/to/build:/build -w /build ubuntu:24.04 sleep infinity
docker exec -it ponwrt bash -c 'bash /build/build-ponwrt.sh'
```

## 五、刷机

> **刷本固件之前，先完成三件事**（缺一不可）：
>
> 1. 按 [Loong1996 网页 U-Boot 指南](https://loong1996.github.io/ImmortalWrt-Airoha/recovery-guide.html) 给机器刷好 **网页 U-Boot**；
> 2. 在恢复页做一次**整片闪存备份**（`all_flash.bin`）；
> 3. 从备份里**提取 `bosa` 与 `ri` 两个分区**：`bosa` 是光模块校准数据，`ri` 是出厂 MAC / 序列号。
>    这两个分区**每台机器唯一**，丢了无法还原原厂状态，PON 也可能无法注册。
>    日常刷机不会动它们（只写 `fit` 卷），但**首次迁移/重建 UBI 前必须先备份**。

1. **先试跑**：U-Boot 恢复页 →「试跑固件」，上传 `*-initramfs-recovery.itb`（不写闪存，起不来断电即可）
2. **正式刷**：恢复页 →「日常刷机」，上传 `*-squashfs-sysupgrade.itb`
   - 只写 `fit` 卷，`bosa`（光模块校准）与 `ri`（出厂 MAC）**不会**被清掉
   - **不要勾「重建 UBI」**，除非你确实要清空整片闪存
3. 首次开机后按下一节配置 PON 与 PPPoE。

## 六、首次配置（PON / PPPoE）

### 1. PON 注册

LuCI（`http://10.0.0.1`）→ 网络 → PON：

- 模式：`XGPON`
- 光模块 SN：原厂光猫的 SN
- 认证方式按运营商来：
  - **LOID 认证**：填 LOID 与 LOID 密码
  - **部分移动省份**：SN + Password
- 同时在 **系统 → 管理权** 里设置 root 密码

配置正确后 PON 状态应为 **O5 并常驻**（截图为拔掉光纤时的状态，属正常）。
相关讨论见 [right.com.cn 原帖](https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8486486)。

### 2. PPPoE 拨号

**WAN 接口的设备默认是 `pon0`。** 如果线路是 VLAN 拨号，设备名要改成 `pon0.<你的 VLAN>`：

1. 先在**原厂光猫**里记下 PPPoE 的 **VLAN ID**（不同运营商、不同地区都不一样）；
2. LuCI → 网络 → 接口 → `wan` → **设备**：把 `pon0` 改成 `pon0.<你的 VLAN>`；
3. **协议**选 `PPPoE`，填宽带账号与密码，保存并应用。

### 3. 桥接模式（可选）

想把 2.5G 的 `lan1` 直接透传给下游路由器：

1. 网络 → 接口 → 设备 → `br-lan`：把 `lan1` **解绑**；
2. 新建一个网桥，把 `pon0` 和 `lan1` 加进去；
3. 接口页面给这个网桥建一个**无协议（Unmanaged）**接口，并把它拉起来；
4. 下游路由器接 `lan1` 拨号即可，**所有 VLAN 都会透传**。

## 七、升级

- 日常升级用 LuCI「系统 → 备份/升级 → 刷写新固件」，或 `sysupgrade <itb>`
- `sysupgrade` 会保留 `/etc/config`（PON、PPPoE、静态租约、ZeroTier 身份等）
- 镜像里的 `uci-defaults` 只设置主题/语言/LAN 网段，不涉及 PON 与 PPPoE

### 在线更新检查

「系统 → 备份/升级 → 操作」页面最下方新增 **在线更新检查** 面板：

| 项目 | 说明 |
|---|---|
| 当前版本 | 显示设备型号与编译时间（来自 `/etc/ponwrt-version`） |
| 最新版本 | 显示最近一次成功检查的正式版本，可点击“立即检查”刷新 |
| 状态 | 显示最近检查的结果和时间，首次检查前显示“尚未检查” |
| 固件检查频率 | 默认每周，可选每天、每周、每 30 天或关闭，选择后自动保存 |
| GitHub 代理 | 国内访问 GitHub 不稳时可填代理，如 `http://10.0.0.5:7897` |
| 立即检查 | 手动刷新版本信息 |
| 下载固件 | 设备后台下载到临时存储。页面显示已下载大小和进度，重新打开可继续查看。下载完成后校验 SHA256 和设备兼容性。 |
| 刷写已下载固件 | 下载校验通过后可用。用户单独确认后再次校验本地镜像，再调用 `sysupgrade` 保留配置刷写。 |
| 设置代理 | 保存代理地址到 `/etc/ponwrt-update.proxy` |

Nokia MD 保持原 `main/version.json` 更新入口，失败时回退到 latest Release 资产。其他机型读取 `main/versions/<soc>/<profile>/version.json`，不回退到 Nokia MD 的 latest；各机型的元数据提供固定 Release 下载地址。配置代理时先走代理、失败再直连。

设备的 cron 每小时第 17 分核对是否到期。没有成功记录时进行首次检查，之后从最近一次成功检查开始计时。断网时保留上次成功结果，下一小时重试。发现与本机匹配的新固件后，登录 LuCI 的用户会看到可打开“备份与更新”的横幅。已打开的页面每分钟刷新本地提示，安装固件仍需手动确认。

普通构建仅上传 Artifact；所选机型全部成功发布 Release 后，由一个汇总 job 写入各机型版本索引，其中 Nokia MD 同步更新 main/version.json。其它机型不会替换 Nokia MD 的 latest。若部分机型失败，已成功的机型仍保留产物，但本轮不回写版本索引。插件包提供后端和 ACL，页面仍集成在原“备份/升级”入口。

## 八、已完成的工作

- 单机型构建已生成 sysupgrade、recovery、软件包清单和 SHA-256 校验文件。[查看 #17 构建](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41230731864)
- 页面快速测试通道可单独安装和回滚 LuCI 升级页，已有固件可以直接验证页面改动。[安装与回滚说明](fast-ui/README.md)
- 更新后端支持手动检查、定时检查和登录提醒。测试机已成功查询正式发布版本。
- 公版软件包清单已接入完整构建。上方表格列出构建选择；已发布镜像的实际软件包以该版 Release 的 manifest 为准。[公版首次 Release 构建记录](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41294150019)

- 已加入多机型 matrix、精确匹配工具链缓存和各机型版本索引；待首次 CI 运行核验构建及缓存耗时。

## 九、致谢与许可

- PON 驱动与固件基础：[pbs05/ponwrt](https://github.com/pbs05/ponwrt)
- Web U-Boot 与刷机方案：[Loong1996/ImmortalWrt-Airoha](https://github.com/Loong1996/ImmortalWrt-Airoha)
- 主题：[eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)（Apache-2.0）
- 上游：ImmortalWrt / OpenWrt（各自许可证）

本仓库的 workflow 与构建脚本以 MIT 许可提供；固件本身遵循各上游组件的许可证。
