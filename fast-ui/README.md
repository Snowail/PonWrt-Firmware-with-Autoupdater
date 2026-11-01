# 在测试机验证“备份与更新”页面

快速通道仅替换 Nokia XG-040G-MD UBI 测试机的 LuCI 页面 `flash.js`，复用已安装的更新后端和权限文件。已验证的基线为[完整构建 #17](https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/actions/runs/41230731864)。以后正式发布时，完整固件使用同一个页面补丁。新增软件包等上游版本更新时再随完整固件编译。

1. 在 GitHub Actions 选择 **Test backup and update page → Run workflow**，下载 Artifact 并在电脑上解压 ZIP。
2. 把 `ponwrt-fast-ui.tar.gz` 和 `sha256sums` 放到设备同一个空目录，例如 `/tmp/ponwrt-ui`。已经安装上一版快速包的测试机可以直接使用新版。
3. 在设备的 root shell 中执行以下命令。

```sh
cd /tmp/ponwrt-ui
sha256sum -c sha256sums &&
  tar -xzf ponwrt-fast-ui.tar.gz &&
  sh ponwrt-fast-ui/apply.sh check &&
  sh ponwrt-fast-ui/apply.sh install
```

强制刷新“系统 → 备份/升级”。即使设备无法访问 GitHub，原有表单也应正常打开，“当前版本”应与 `cat /etc/ponwrt-version` 的 `device` 和 `built` 一致。初始状态为“尚未检查”。点击“立即检查”后应显示结果或错误，当前版本应继续可见。

定时检查和登录横幅需要包含新版后端的完整固件。#17 上的页面测试包只预览频率控件，保存频率和接收横幅需在新版完整固件上验证。

首次页面测试会保存当时的页面，重复安装沿用该备份。用以下命令恢复到本轮页面测试前的状态，然后强制刷新。

```sh
sh /root/ponwrt-page-test/rollback.sh rollback
```

如果还要撤销上一代三文件快速包，在恢复本轮页面后再运行旧包的 `sh /root/ponwrt-fast-ui/rollback.sh rollback`。
