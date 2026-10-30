#!/usr/bin/env python3
"""给 LuCI 的「系统 → 备份/升级」页面打补丁：在原有功能之外增加「固件更新」区块。

用法: patch-flash.py <path/to/view/system/flash.js>

补丁内容：
  1. load() 里追加一次 /usr/bin/ponwrt-update-check --json 的调用；
  2. render() 多接收一个参数 pu；
  3. 在 form 里插入一个「固件更新」section（当前版本 / 最新版本 / 状态 / 检查 / 下载并刷写）。
原有的备份、恢复、mtdblock、刷写、sysupgrade.conf 五个区块完全保留。
"""
import sys

BLOCK = r"""
/* ponwrt updater: 由仓库 overlay 注入 */
const PU=(function(){try{return JSON.parse((pu&&pu.stdout)||'{}')}catch(e){return{}}})();
s=m.section(form.NamedSection,'pu','pu',_('Firmware update'),_('Check the latest release of this repository, or download and flash it directly.'));
o=s.option(form.DummyValue,'pu_cur',_('Current version'));o.cfgvalue=function(){return (PU.device||'unknown')+' / '+(PU.cur_built||'unknown')};
o=s.option(form.DummyValue,'pu_latest',_('Latest version'));o.cfgvalue=function(){return PU.latest||'-'};
o=s.option(form.DummyValue,'pu_state',_('Status'));o.cfgvalue=function(){if(PU.error)return _('Check failed')+': '+PU.error;return PU.update?_('New version available'):_('Up to date')};
o=s.option(form.Button,'pu_check',_('Check for updates'));o.inputstyle='action';o.inputtitle=_('Check now');o.onclick=function(){ui.showModal(_('Checking...'),[E('p',{'class':'spinning'},'')]);return fs.exec('/usr/bin/ponwrt-update-check',['--json']).then(function(r){ui.hideModal();ui.addNotification(null,E('pre',{},r.stdout||''),'info');});};
o=s.option(form.Button,'pu_flash',_('Download and flash'));o.inputstyle='negative important';o.inputtitle=_('Download and flash');o.onclick=function(){if(!confirm(_('Download the latest firmware and flash it now? Do not power off.')))return;ui.showModal(_('Downloading...'),[E('p',{'class':'spinning'},'')]);return fs.exec('/usr/bin/ponwrt-update-check',['--flash']).then(function(r){ui.hideModal();ui.addNotification(null,E('pre',{},(r.stdout||'')+(r.stderr||'')),'info');});};
"""


def main(path):
    src = open(path, encoding='utf-8').read()
    if 'ponwrt-update-check' in src:
        print('already patched')
        return 0

    a = "fs.trimmed('/proc/mounts')];return Promise.all(tasks);}"
    b = ("fs.trimmed('/proc/mounts'),"
         "fs.exec('/usr/bin/ponwrt-update-check',['--json'])"
         ".catch(function(){return{code:1,stdout:'{}'}})];return Promise.all(tasks);}")
    if a not in src:
        print('FAIL: load() anchor not found')
        return 1
    src = src.replace(a, b, 1)

    c = "render([p_fstat,hostname,procmtd,procpart,procmounts]){"
    d = "render([p_fstat,hostname,procmtd,procpart,procmounts,pu]){"
    if c not in src:
        print('FAIL: render() anchor not found')
        return 1
    src = src.replace(c, d, 1)

    e = "m.readonly=isReadonlyView;"
    if e not in src:
        print('FAIL: form anchor not found')
        return 1
    src = src.replace(e, e + BLOCK, 1)

    open(path, 'w', encoding='utf-8').write(src)
    print('patched')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
