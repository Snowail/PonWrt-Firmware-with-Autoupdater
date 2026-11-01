# PonWrt Firmware (Airoha AN7581 / AN7583) with Autoupdater

本仓库用 GitHub Actions 自动构建 **pbs05/ponwrt** 固件（ImmortalWrt + Airoha AN7581/AN7583 的 PON 支持），并添加了Aurora 主题、简体中文、常用插件、修改了固定 LAN 网段 (10.0.0.2/24)。

另外在 [系统 > 备份与更新] 中新增了**自动检查本仓库固件更新**的功能，默认每周检查一次，可以配置更新检查周期和http代理，检测到新固件会在LuCI提醒用户转到 [系统 > 备份与更新]，下载固件后自动校验SHA256，通过后允许用户点击刷写。

> ⚠️ 固件更新默认保留配置，但无法保留用户在 [系统 > 软件包] 或者终端apk命令安装的额外软件包，可以在固件更新后重新安装软件包，配置会保留。

---

## 一、固件来源

| 项目 | 来源 |
| --- | --- |
| 基础固件 | [pbs05/ponwrt](https://github.com/pbs05/ponwrt) —— 基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)，加入 Airoha AN7581 / AN7583 的 **PON 驱动** |
| 上游框架 | [OpenWrt](https://github.com/openwrt/openwrt) / [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) |
| LuCI 主题 | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)（Apache-2.0），本仓库以本地包方式编译进镜像 |
| 中文语言包 | ImmortalWrt luci feed，通过 `CONFIG_LUCI_LANG_zh_Hans=y` 全量启用 |
| 网页 U-Boot（刷机用） | [Loong1996/ImmortalWrt-Airoha](https://github.com/Loong1996/ImmortalWrt-Airoha) 的 Web U-Boot |



## 二、构建配置

- **LuCI 简体中文** + **Aurora 主题**（首次启动自动设为默认主题与中文）
- **默认 LAN：`10.0.0.1/24`**，DHCP 池 `10.0.0.100–10.0.0.249`

### 额外软件包

| 用途 | 内置项目 |
|---|---|
| 界面、升级 | `luci-theme-aurora`、LuCI 简体中文、`luci-compat`、`luci-app-ponwrt-update`、`curl`、`jsonfilter`、`ca-bundle` |
| DNS | `adguardhome`、`luci-app-adguardhome` |
| 分流与公网服务 | `lucky`、`luci-app-lucky`、`frpc`、`luci-app-frpc` |
| 域名、唤醒与 NAT | `luci-app-ddns`、`ddns-scripts`、`ddns-scripts-services`、`luci-app-wol`、`luci-app-upnp`、`miniupnpd-nftables` |
| 远程组网 | `zerotier`、`luci-app-zerotier`、`tailscale`、`luci-app-tailscale-community`、`wireguard-tools`、`kmod-wireguard`、`luci-proto-wireguard` |
| 带宽与监控 | `nlbwmon`、`luci-app-nlbwmon`（按终端统计流量） |
| 文件与共享 | `openssh-sftp-server`、`samba4-server`、`luci-app-samba4` |
| 诊断 | `iperf3`、`bind-dig`、`ethtool-full`、`htop` |

全新安装默认关闭 AdGuard Home、Lucky 和 UPnP。由用户在 LuCI 中选择是否启用。保留配置升级时沿用已保存的服务设置。完整固件的实际依赖与版本见该次 Release 附带的 `.manifest`。

> 科学上网因性能不佳暂时未加入

## 三、设备支持列表

全部机型使用 Image Builder 生成日常升级镜像；基础编译另附 recovery 镜像。

Actions 每天北京时间早上 8 点检查上游更新，发现新版本后自动构建全部机型。

| SoC | 设备 | Profile | 原厂校准/身份数据分区 |
| --- | --- | --- | --- |
| AN7581 | FiberHome HG5382A | `fiberhome_hg5382a` | `factory` |
| AN7581 | FiberHome HG5585F CT | `fiberhome_hg5585f-ct` | `factory` |
| AN7581 | FiberHome HG5585F CU | `fiberhome_hg5585f-cu` | `factory` |
| AN7581 | Gemtek XG2010G | `gemtek_xg2010g` | `dsd` |
| AN7581 | Nokia XG-040G-MD UBI | `nokia_xg-040g-md-ubi` | `bosa`、`ri` |
| AN7581 | Nokia XG-040G-TF UBI | `nokia_xg-040g-tf-ubi` | `bosa`、`ri` |
| AN7581 | UnionMan UNG00A | `unionman_ung00a` | `reservearea` |
| AN7581 | ZNXT ZN504XG-D | `znxt_zn504xg-d` | `reservearea` |
| AN7581 | ZNXT ZN515XG-D | `znxt_zn515xg-d` | `reservearea` |
| AN7583 | Nokia XG-040G-MF | `nokia_xg-040g-mf`、`nokia_xg-040g-mf-ubi` | `bosa`、`ri` |

设备列表来自 [pbs05/ponwrt](https://github.com/pbs05/ponwrt/blob/master/README_zh.md)。已实机验证 Nokia XG-040G-MD（UBI 版）。下方刷机说明适用于该版本。

## 四、首次使用

**⚠️刷本固件之前，先完成三件事**（缺一不可）：

1. 按 [Loong1996 网页 U-Boot 指南](https://loong1996.github.io/ImmortalWrt-Airoha/recovery-guide.html) 给机器刷好 **网页 U-Boot**；
2. 在备份页做一次**整片闪存备份**（`all_flash.bin`）；
3. 从备份里**提取 `bosa` 与 `ri` 两个分区**：`bosa` 是光模块校准数据，`ri` 是出厂 MAC / 序列号。
   这两个分区**每台机器唯一**，丢了无法还原原厂状态，PON 也可能无法注册。
   日常刷机不会动它们（只写 `fit` 卷），但**首次迁移/重建 UBI 前必须先备份**，详情参考第一条指南（串口引导需要做完网页写入三样，并且把bosa和ri分区在 [按卷写入] 里写回去）。

### 下载固件

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

### 刷机

1. **先试跑**：U-Boot 恢复页 →「试跑固件」，上传 `*-initramfs-recovery.itb` 刷入（不写闪存，起不来断电即可），确认机器能正常启动进入LuCI
2. **正式刷**：U-Boot 恢复页 →「日常刷机」，上传 `*-squashfs-sysupgrade.itb`
   - 只写 `fit` 卷，`bosa`（光模块校准）与 `ri`（出厂 MAC）**不会**被清掉
   - **不要勾「重建 UBI」**，除非你确实要清空整片闪存
3. 首次开机后使用 `http://10.0.0.1 `或 `http://immortalwrt.lan`登录LuCI

### PON 注册

 网络 → PON → 配置：

- 线路模式：默认或者你知道你在干嘛
- 序列号（SN）：运营商光猫的 SN
- Registration-ID：SN + Password 认证时填写的密码
- 认证方式按运营商来：
  - **LOID 认证**：在  `OMCI 设置` → `身份认证` 填 LOID 与 LOID 密码
  - **SN + Password (部分移动省份)**： 在 `Registration-ID` 填写密码
- 同时在 **系统 → 管理权** 里设置 root 密码

配置正确后 PON 状态应为 **O5 并常驻**（截图为拔掉光纤时的状态，属正常）。
相关讨论见 [right.com.cn 原帖](https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8486486)。

### PPPoE 拨号

**WAN 接口的设备默认是 `pon0`。** 如果线路是 VLAN 拨号，设备名要改成 `pon0.<你的 VLAN>`：

1. 先在**原厂光猫**里记下 PPPoE 的 **VLAN ID**（不同运营商、不同地区都不一样）；
2. LuCI → 网络 → 接口 → `wan` → **设备**：把 `pon0` 改成 `pon0.<你的 VLAN>` 比如 `pon0.81`；
3. **协议**选 `PPPoE`，填宽带账号与密码，保存并应用；
4. 如果PPPoE自动下发了 `WAN_6`，可以把自带的那个 `WAN_6` 删了。

### 桥接模式（可选）

想把 2.5G 的 `lan1` 直接透传给下游路由器：

1. 网络 → 接口 → 设备 → `br-lan`：把 `lan1` **解绑**；
2. 新建一个网桥，把 `pon0` 和 `lan1` 加进去；
3. 接口页面给这个网桥建一个**无协议（Unmanaged）**接口，并把它拉起来；
4. 下游路由器接 `lan1` 拨号即可，**所有 VLAN 都会透传**。

## 五、升级

- 手动升级用「系统 → 备份与更新 → 操作 → 更新固件」，或终端 `sysupgrade <itb>`

- `sysupgrade` 会保留 `/etc/config`（PON、PPPoE、静态租约、ZeroTier 身份等）

- 镜像里的 `uci-defaults` 只设置主题/语言/LAN 网段，不涉及 PON 与 PPPoE

  > ⚠️更新前强烈建议在同一页面最顶端 `生成备份`

### 在线更新检查

「系统 → 备份与更新 → 操作」页面最下方新增 **在线更新检查** 面板：

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
| 设置代理 | 支持http代理，保存代理地址到 `/etc/ponwrt-update.proxy` |

设备的 cron 每小时第 17 分核对是否到期。没有成功记录时进行首次检查，之后从最近一次成功检查开始计时。断网时保留上次成功结果，下一小时重试。发现与本机匹配的新固件后，登录 LuCI 的用户会看到可打开“备份与更新”的横幅。已打开的页面每分钟刷新本地提示，安装固件仍需手动确认。

## 六、已完成的工作

- 单机型构建已生成 sysupgrade、recovery、软件包清单和 SHA-256 校验文件。[查看 #17 构建](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41230731864)
- 页面快速测试通道可单独安装和回滚 LuCI 升级页，已有固件可以直接验证页面改动。[安装与回滚说明](fast-ui/README.md)
- 更新后端支持手动检查、定时检查和登录提醒。测试机已成功查询正式发布版本。
- 公版软件包清单已接入完整构建。上方表格列出构建选择；已发布镜像的实际软件包以该版 Release 的 manifest 为准。[公版首次 Release 构建记录](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41294150019)

- 已加入多机型 matrix、精确匹配工具链缓存和各机型版本索引；待首次 CI 运行核验构建及缓存耗时。

## 七、致谢与许可

- PON 驱动与固件基础：[pbs05/ponwrt](https://github.com/pbs05/ponwrt)
- Web U-Boot 与刷机方案：[Loong1996/ImmortalWrt-Airoha](https://github.com/Loong1996/ImmortalWrt-Airoha)
- 主题：[eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)（Apache-2.0）
- 上游：ImmortalWrt / OpenWrt（各自许可证）

本仓库的 workflow 与构建脚本以 MIT 许可提供；固件本身遵循各上游组件的许可证。
