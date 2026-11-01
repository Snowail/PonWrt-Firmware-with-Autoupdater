# 在现有固件上更新插件和升级页

适用于 Nokia XG-040G-MD UBI。已验证的固件基线为 [Actions #17](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41230731864)。安装器检查设备的 PonWrt 提交、机型、LuCI 包版本及运行依赖。快速包更新三个文件：在线更新后端、rpcd 权限文件和现有的“系统 → 备份/升级”页面。设备原有固件版本号继续用于在线固件更新。

1. 在 GitHub Actions 选择 **Fast plugin and LuCI update → Run workflow**。每次构建都从锁定的 LuCI 源码生成升级页，使用本仓库当前的补丁、更新脚本和 ACL。
2. 下载该次运行的 Artifact，在电脑上解压外层 ZIP，把 `ponwrt-fast-ui.tar.gz` 和 `sha256sums` 传到设备上同一个空目录，例如 `/tmp/ponwrt-ui`。
3. 在设备的 root shell 中执行下面的命令。第一步校验下载文件，`check` 检查固件和 LuCI 是否匹配。

```sh
cd /tmp/ponwrt-ui
sha256sum -c sha256sums &&
  tar -xzf ponwrt-fast-ui.tar.gz &&
  sh ponwrt-fast-ui/apply.sh check &&
  sh ponwrt-fast-ui/apply.sh install
```

完成后强制刷新 LuCI 页。安装会重启 rpcd，首次安装前的文件保存在 `/root/ponwrt-fast-ui/original`。重复更新沿用这份备份。若要恢复到首次快速更新之前的状态，运行：

```sh
sh /root/ponwrt-fast-ui/rollback.sh rollback
```

这是直接覆盖三个运行时文件的更新包。APK 包管理器仍显示基础固件的包版本。改动涉及内核、PON 驱动或新增系统依赖时，使用 **Build ponwrt firmware** 生成刷机镜像。
