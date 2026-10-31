# PonWrt 构建流程与本次验收记录

更新时间：2026-10-31（Asia/Shanghai）。本次以工作区的 `PonWrt_Codex_交接文档.md` 为优先依据。

## 当前状态

本地修复已完成并通过脚本、工作流和模拟回归检查。使用者已授权提交、推送及一次 `make_release=false` 的完整诊断构建。**完整构建结果以对应 Actions 运行记录为准，不能仅凭本地回归宣称内核问题已解决或新固件可刷。** 本轮诊断不发布 Release。

唯一维护入口是本仓库的 `build-ponwrt.sh` 和 `.github/workflows/build.yml`。Windows 工作区外层同名文件属于旧副本，不要拿它们推送。`repo/` 是本地编辑副本，`publish-repo/` 是基于 GitHub 最新 main 建立的真实检出；发布时审查差异后一次性提交相关文件，避免逐文件上传导致工作流与脚本版本不同步。

## 已核实的故障

1. [失败 Run #15](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41174023546) 使用源码 `03c134544714617e196dd399c85ebb90fb6eefa1`，在编译步骤失败。提供的 ZIP 只有一个 280,744 字节的日志，没有镜像。日志已进入 `[6/7] 编译`，不能说它只在下载阶段失败。
2. [失败提交的脚本](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/blob/dc2fae31f72786837ac7525d42b5ed3ddeb57c3b/build-ponwrt.sh) 使用 `cp -a "$REPO_DIR/package/luci-app-ponwrt-update/." package/`：插件 Makefile 覆盖上游 `package/Makefile`，真正的插件目录缺少 Makefile。这是已确认的包组装错误，可解释插件 MISS；日志的 clean/prereq 覆盖警告与此一致。**尚不能证明它是 target/linux 失败的唯一原因。**
3. `set -euo pipefail` 下，失败检测的 grep 不匹配 `target/linux`，直接终止脚本，单线程详细重试没有执行。
4. 本地旧工作流用 profile 子串从整批 sha256sums 选镜像，存在匹配变体机型的问题；普通构建也回写版本信息；git push、Release 创建失败被 `|| true` 忽略。
5. [上游 an7581 配置](https://github.com/pbs05/ponwrt/blob/03c134544714617e196dd399c85ebb90fb6eefa1/configs/an7581.config) 选中了全部 13 个设备。旧脚本仅在最后收集指定设备，编译阶段并未限制机型。

## 调整后的流程

1. **预检**：校验 SoC、设备 profile、40 位源码 SHA、并发和模式组合；运行轻量回归测试。冒烟/只编包模式不能发布，发布只允许从 main 手动触发。
2. **缓存**：下载缓存放 `~/ponwrt-dl`；编译缓存放 `~/ponwrt-ccache`，限制 2 GB。仅复用下载文件和 ccache，不缓存整个源码树或工具链目录。下载阶段已完成时，即使后续编译失败也保存下载缓存。
3. **源码**：在新目录 shallow fetch 指定提交；`sources.lock.json` 固定 7 个 feeds 和 Aurora。每次检验实际 HEAD，并输出 `sources-resolved.json`。
4. **插件**：先把插件复制进 `package/luci-app-ponwrt-update/`，再生成包元数据；验证上游 `package/Makefile` 未改。插件包安装后端脚本和 ACL，现有“备份/升级”页使用 `patch-flash.py` 集成面板，不安装旧的独立菜单/view。补丁缺少锚点或 Node 语法检查失败立即停止。
5. **配置**：保留上游软件包选择，仅保留请求的设备 profile；启用 ccache、更新插件及依赖。`defconfig` 后检查包元数据、必需配置以及设备数量。必需项 MISS 立即失败，不在 defconfig 后强塞配置。
6. **下载/编译**：各阶段直接记录详细日志。并行失败最多重试一次 `-j1 V=s`，不依赖 grep 提取目标，也不盲目 clean 内核。分别保留 make/tee 退出状态。下载即使返回零，只要末次日志仍报告 build failed 也拒绝进入编译。
7. **产物**：精确匹配设备的 sysupgrade、recovery 镜像；核对上游 SHA256、profiles.json 的设备与哈希、manifest 中更新插件及依赖；再复制文件，生成 version.json 与只覆盖实际产物的 sha256sums。缺失产物即失败。
8. **上传与发布**：失败仍上传诊断。完整成功且勾选 make_release 时，先上传为 draft Release，再发布；只有正式 AN7581 / Nokia MD UBI 发布成功才回写 main/version.json，并成为 latest。其它机型 Release 不改变正式设备的更新入口。失败不吞掉退出码。

version.json 增加固定 Release tag 的 `download_url`。新后端优先使用此 URL，验证机型、文件名和 SHA256，并在刷写前执行 `sysupgrade -T`。旧的无 download_url 元数据仍可回退 latest。构建没有触碰任何设备；刷机路径的本地测试全部使用模拟命令。

## 第一次诊断构建

经使用者批准提交与推送后，Actions → Build ponwrt firmware → Run workflow：

| 参数 | 值 |
|---|---|
| branch | main |
| soc | an7581 |
| device_profile | nokia_xg-040g-md-ubi |
| pin_commit | 03c134544714617e196dd399c85ebb90fb6eefa1 |
| jobs | 4 |
| make_release | **false** |
| smoke_only | false |
| packages_only | false |

完整构建步骤限时 325 分钟，Job 360 分钟，预留诊断上传时间。首次构建时间应实测，不承诺固定耗时。全局串行避免版本回写竞争；GitHub 并发队列不会保证保存无限多个待运行请求，避免连续重复点击。

若失败，下载带 run ID 和 attempt 的 Artifact：

- 优先查看 `diagnostics/world-serial.log` 中第一个真实失败命令及上下文，而非末尾汇总；并行首次日志也保留。
- 若失败在配置/下载阶段，看 `defconfig.log`、`download-parallel.log`、`download-serial.log`、`.config`、`.config-package.in` 和 `.packageinfo`。
- `build-exit-code`、各阶段 `.status`、`resources.txt`、`kernel-messages.txt` 辅助区分命令失败、磁盘和内存问题；runner 不允许读取 dmesg 时，该文件记录权限错误，不能据此排除 OOM。
- 因硬终止、runner 故障或整个 Job 超时，always()/EXIT trap 也不能保证执行；正常步骤失败会收集日志。编译日志在执行时直接写入诊断目录。

只有新增日志明确定位后才修改内核补丁、设备树或驱动。不要重新从汇总错误猜根因。

## feeds 与剩余验收

锁文件是按 GitHub 默认分支截至 `2026-10-31T05:51:00Z` 的历史提交选出的**候选基线**。原失败日志没有记录 feeds SHA，不能称其为 Run #15 的精确复现，也不能称其已通过完整构建。来源/时间说明写在锁文件中，后续升级必须明确修改锁文件并重新构建。

qt5base、fwknopd、squeezelite 的循环依赖尚未做猜测式补丁，也没有删减上游 feeds。它们不在本次定制的必需包中；需要用修复包目录后生成的完整配置日志确认是否仍出现、是否影响所选包。锁定版本只解决漂移，不会自动修复依赖错误。

尚待 Actions/设备验收：

- 定位并解释 target/linux 的第一个底层错误；若新构建直接通过，也不把旧运行根因写成已完全证明。
- 验证 defconfig 后更新包启用、真实 manifest 包含插件、目标镜像和校验信息齐全。
- 完整构建成功后，再决定是否运行 make_release=true；核对 Release 和 main/version.json 的对应关系。
- 测试机试跑/启动、PON、LuCI 更新面板及真实升级仍属于硬件验收，当前未执行。

`packages_only` 只交付后端、curl、jsonfilter 安装包，兼容 APK/IPK 文件名。它不自动替换旧设备 flash.js，也不保证三个文件涵盖所有依赖；安装须匹配设备 ABI，保留此模式作诊断用途。

## 本地测试

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/test-build-lib.sh
bash tests/test-update.sh
bash -n build-ponwrt.sh
actionlint .github/workflows/build.yml
```

已通过 13 项 Python 回归、ShellCheck 0.11.0 和带 ShellCheck 的 actionlint 1.7.12；make 模拟测试覆盖内核/包/未知错误、详细重试、最终退出码、禁止 clean 与 tee 失败；更新模拟测试覆盖机型、固定下载 URL、回退版本阻止及 sysupgrade 预检。另已对锁定 LuCI 的真实 flash.js 打补丁并通过 `node --check`，对真实 an7581 配置验证只保留目标设备。以上均不等价于 Linux 完整编译或硬件验证。
