# PonWrt Firmware (Nokia XG-040G-MD / Airoha AN7581) with Autoupdater

本仓库用 GitHub Actions 自动构建 **pbs05/ponwrt** 固件（ImmortalWrt + Airoha AN7581/AN7583 的 PON 支持），
并叠加了一套通用定制：Aurora 主题、简体中文、常用插件、固定 LAN 网段。

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

## 二、镜像包含什么

- **LuCI 简体中文** + **Aurora 主题**（首次启动自动设为默认主题与中文）
- **默认 LAN：`10.0.0.1/24`**，DHCP 池 `10.0.0.100–10.0.0.249`
- 预装插件：
  - [ZeroTier](https://www.zerotier.com/)（`zerotier` + LuCI 界面）
  - `iperf3`（测速）
  - `nlbwmon`（按设备流量统计，LuCI「服务 → 带宽监控」）

## 三、支持机型

由 `configs/<soc>.config` 决定，当前默认构建 `nokia_xg-040g-md-ubi`（Nokia XG-040G-MD，UBI 布局）。
同一份 `an7581` 配置里的其它 profile 也可以直接构建：

| SoC | 设备 profile | 机型 |
| --- | --- | --- |
| an7581 | `nokia_xg-040g-md-ubi` | Nokia XG-040G-MD（UBI） |
| an7581 | `nokia_xg-040g-md-ubi-usb-sfp` | XG-040G-MD + USB/SFP 变体 |
| an7581 | `nokia_xg-040g-tf-ubi` | Nokia XG-040G-TF（安全启动，需配套 TF 引导） |
| an7581 | `gemtek_xg2010g` / `znxt_zn504xg-d` / `znxt_zn515xg-d` / `unionman_ung00a` / `fiberhome_hg5382a` 等 | 其它 AN7581 机型 |
| an7583 | `nokia_xg-040g-mf-ubi` | Nokia XG-040G-MF |

> 机型与引导器必须匹配。TF 机型有安全启动，不能混用 MD 的引导文件。

## 四、获取与构建

### 直接下载（推荐）

**Releases** 里是已经构建好的镜像，不用自己编译。命名规则：

| 名称 | 含义 |
| --- | --- |
| Release tag：`<device_profile>-<YYYYMMDD-HHMM>` | 例：`nokia_xg-040g-md-ubi-20261030-2105` |
| Release 标题：`<device_profile> <tag>` | 同一 tag |
| `ponwrt-airoha-<soc>-<device_profile>-squashfs-sysupgrade.itb` | **正式固件**，U-Boot「日常刷机」用 |
| `ponwrt-airoha-<soc>-<device_profile>-initramfs-recovery.itb` | **试跑固件**，U-Boot「试跑固件」用 |
| `sha256sums` | 所有镜像的 SHA256 校验值 |
| `ponwrt-version` | 编译时的 commit / 设备 / 时间 |

例：`ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-squashfs-sysupgrade.itb`
= SoC `an7581` + 设备 `nokia_xg-040g-md-ubi` 的正式固件。

### 方式 A：GitHub Actions 自行编译

**Actions → Build ponwrt firmware → Run workflow**，参数：

- `soc`：`an7581`（XG-040G-MD 及其它 AN7581 机型）；XG-040G-MF 用 `an7583`
- `device_profile`：`nokia_xg-040g-md-ubi`
- `pin_commit`：留默认（`03c1345`）
- `jobs`：`4`
- `make_release`：需要发 Release 时勾上
- `smoke_only`：只编到 toolchain + libffi + ucode 就停，用于快速验证（约 50–70 分钟）

构建约 **2–4 小时**（GitHub 托管 runner 是 4 vCPU / 16 GB，完整编工具链 + 内核 + 全部软件包）。

> 只有勾选 `make_release` 的构建才会发 Release；平时手动触发的构建只上传 **Artifact**（保留 30 天），在运行页面下载。

`dl/` 会被 `actions/cache` 缓存，第二次起省去约 2.5 GB 下载。

### 方式 B：本地 / 自己的服务器

```bash
sudo ./build-ponwrt.sh          # 自动装依赖、编译、产物放 ~/out
# 可选参数：
PONWRT_SOC=an7581 PONWRT_DEVICE=nokia_xg-040g-md-ubi PONWRT_JOBS=8 ./build-ponwrt.sh
```

要求：Ubuntu 22.04/24.04 x86_64、≥4 核、≥8 GB 内存、≥40 GB 磁盘（首次全量约 20–25 GB）。

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

- 日常升级用 LuCI「系统 → 备份/升级 → 刷写新固件」，或 `sysupgrade -n <itb>`
- `sysupgrade` 会保留 `/etc/config`（PON、PPPoE、静态租约、ZeroTier 身份等）
- 镜像里的 `uci-defaults` 只设置主题/语言/LAN 网段，不涉及 PON 与 PPPoE

### 在线更新检查

「系统 → 备份/升级 → 操作」页面最下方新增 **在线更新检查** 面板：

| 项目 | 说明 |
|---|---|
| 当前版本 | 显示设备型号与编译时间（来自 `/etc/ponwrt-version`） |
| 最新版本 | 从本仓库的 `version.json` 读取最新构建 |
| 状态 | 发现新版本 / 已是最新 / 检查失败（附原因） |
| GitHub 代理 | 国内访问 GitHub 不稳时可填代理，如 `http://10.0.0.5:7897` |
| 立即检查 | 手动刷新版本信息 |
| 下载并刷写 | 下载最新固件 → **校验 SHA256** → 调 `sysupgrade`（保留配置） |
| 设置代理 | 保存代理地址到 `/etc/ponwrt-update.proxy` |

版本信息来源优先 `raw.githubusercontent.com/<repo>/main/version.json`，失败时回退到 Release 资产；配置代理时先走代理、失败再直连。

## 八、路线图

- [x] 固件内「系统 → 备份/升级 → 操作」的在线更新检查面板
- [x] Release 自动附带 `version.json` 与 `sha256sums`，支持一键校验下载
- [ ] 多机型矩阵构建（一次触发编多个 profile）

## 九、致谢与许可

- PON 驱动与固件基础：[pbs05/ponwrt](https://github.com/pbs05/ponwrt)
- Web U-Boot 与刷机方案：[Loong1996/ImmortalWrt-Airoha](https://github.com/Loong1996/ImmortalWrt-Airoha)
- 主题：[eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)（Apache-2.0）
- 上游：ImmortalWrt / OpenWrt（各自许可证）

本仓库的 workflow 与构建脚本以 MIT 许可提供；固件本身遵循各上游组件的许可证。
