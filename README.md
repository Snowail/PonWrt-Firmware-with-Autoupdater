# PonWrt Firmware (Nokia XG-040G-MD / Airoha AN7581) with Autoupdater

本仓库用 GitHub Actions 自动构建 **pbs05/ponwrt** 固件（ImmortalWrt + Airoha AN7581/AN7583 的 PON 支持），
并叠加了一套通用定制：Aurora 主题、简体中文、常用插件、固定 LAN 网段。
**镜像不含任何个人数据**，任何人都可以直接使用，刷完自行配置。

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
  - `nlbwmon`（按设备流量统计，LuCI「状态 → nlbwmon」）

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

## 四、如何构建

### 方式 A：GitHub Actions（推荐，免费）

1. 打开仓库 **Actions → Build ponwrt firmware → Run workflow**
2. 填参数：
   - `soc`：`an7581`（XG-040G-MD 及其它 AN7581 机型）；XG-040G-MF 用 `an7583`
   - `device_profile`：`nokia_xg-040g-md-ubi`
   - `pin_commit`：留默认（`03c1345`）
   - `jobs`：`4`
   - `make_release`：需要发 Release 时勾上
   - `smoke_only`：只编到 toolchain + libffi + ucode 就停，用于快速验证（约 25 分钟）
3. 构建约 **60–90 分钟**，完成后在运行页面下载 artifact（保留 30 天）

`dl/` 会被 `actions/cache` 缓存，第二次起省去约 2.5 GB 下载。
私有仓库每月 2000 Actions 分钟；**公开仓库不限量**。

> 参数名特意用了 `soc` / `device_profile`，而不是 `target` / `device`。
> 因为 `TARGET`、`DEVICE` 这类通用名字一旦作为环境变量传给 `make`，会被各个子项目的
> Makefile 当成自己的变量（例如 libffi 会把 `TARGET` 当作构建子目录名），造成极难排查的构建失败。

### 方式 B：本地 / 自己的服务器

```bash
sudo ./build-ponwrt.sh          # 自动装依赖、编译、产物放 ~/out
# 可选（全部带 PONWRT_ 前缀，避免和 autotools 变量撞名）：
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

1. **先试跑**：U-Boot 恢复页 →「试跑固件」，上传 `*-initramfs-recovery.itb`（不写闪存，起不来断电即可）
2. **正式刷**：恢复页 →「日常刷机」，上传 `*-squashfs-sysupgrade.itb`
   - 只写 `fit` 卷，`bosa`（光模块校准）与 `ri`（出厂 MAC）**不会**被清掉
   - **不要勾「重建 UBI」**，除非你确实要清空整片闪存
3. **首次开机**后按你的线路参数配置：
   - LuCI（`http://10.0.0.1`）→ 网络 → PON：填 **XGPON 模式、光模块 SN、LOID/注册号**
   - 网络 → 接口 → WAN：`pon0.81` 上做 **PPPoE 拨号**
   - 系统 → 管理权：设置 root 密码
   - 如果之前用 `sysupgrade -b` 备份过：**系统 → 备份/升级 → 上传归档** 一次性恢复

## 六、升级

- 日常升级用 LuCI「系统 → 备份/升级 → 刷写新固件」，或 `sysupgrade -n <itb>`
- `sysupgrade` 会保留 `/etc/config`（PON、PPPoE、静态租约、ZeroTier 身份等）
- 镜像里的 `uci-defaults` 只设置主题/语言/LAN 网段，不涉及 PON 与 PPPoE

## 七、路线图

- [ ] 固件内「系统 → 固件更新」页面：定时检查本仓库 Release，登录 LuCI 后提示新版本
- [ ] Release 自动附带 `version.json` 与 `sha256sums`，支持一键校验下载
- [ ] 多机型矩阵构建（一次触发编多个 profile）

## 八、致谢与许可

- PON 驱动与固件基础：[pbs05/ponwrt](https://github.com/pbs05/ponwrt)
- Web U-Boot 与刷机方案：[Loong1996/ImmortalWrt-Airoha](https://github.com/Loong1996/ImmortalWrt-Airoha)
- 主题：[eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)（Apache-2.0）
- 上游：ImmortalWrt / OpenWrt（各自许可证）

本仓库的 workflow 与构建脚本以 MIT 许可提供；固件本身遵循各上游组件的许可证。
