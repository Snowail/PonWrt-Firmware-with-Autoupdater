#!/usr/bin/env python3
"""给 LuCI 的「系统 → 备份/升级」页面打补丁：增加「固件更新」区块。

用法: patch-flash.py <path/to/view/system/flash.js>

兼容两种版式：
  * 设备上 luci-mod-system 的压缩版（`load(){...}`, `m.readonly=isReadonlyView;`）
  * 源码树里未压缩版（多行、带空格：`m.readonly = isReadonlyView;`）

做法全部用正则锚点，不依赖具体空白：
  1. `return Promise.all(tasks);` 前插入一次 update-check 调用；
  2. `render([...])` 的参数表末尾追加 `pu`；
  3. `m.readonly = isReadonlyView;` 后插入表单区块。
原有备份 / 恢复 / mtdblock / 刷写 / sysupgrade.conf 五块保持不变。
"""
import re
import sys

BLOCK = r"""
/* ponwrt updater: 由仓库 overlay 注入 */
const PU = (function () { try { return JSON.parse((pu && pu.stdout) || '{}'); } catch (e) { return {}; } })();
s = m.section(form.NamedSection, 'pu', 'pu', _('Firmware update'),
	_('Check the latest release of this repository, or download and flash it directly.'));
o = s.option(form.DummyValue, 'pu_cur', _('Current version'));
o.cfgvalue = function () { return (PU.device || 'unknown') + ' / ' + (PU.cur_built || 'unknown'); };
o = s.option(form.DummyValue, 'pu_latest', _('Latest version'));
o.cfgvalue = function () { return PU.latest || '-'; };
o = s.option(form.DummyValue, 'pu_state', _('Status'));
o.cfgvalue = function () {
	if (PU.error) return _('Check failed') + ': ' + PU.error;
	return PU.update ? _('New version available') : _('Up to date');
};
o = s.option(form.Button, 'pu_check', _('Check for updates'));
o.inputstyle = 'action'; o.inputtitle = _('Check now');
o.onclick = function () {
	ui.showModal(_('Checking...'), [E('p', { 'class': 'spinning' }, '')]);
	return fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ]).then(function (r) {
		ui.hideModal();
		ui.addNotification(null, E('pre', {}, r.stdout || ''), 'info');
	});
};
o = s.option(form.Button, 'pu_flash', _('Download and flash'));
o.inputstyle = 'negative important'; o.inputtitle = _('Download and flash');
o.onclick = function () {
	if (!confirm(_('Download the latest firmware and flash it now? Do not power off.'))) return;
	ui.showModal(_('Downloading...'), [E('p', { 'class': 'spinning' }, '')]);
	return fs.exec('/usr/bin/ponwrt-update-check', [ '--flash' ]).then(function (r) {
		ui.hideModal();
		ui.addNotification(null, E('pre', {}, (r.stdout || '') + (r.stderr || '')), 'info');
	});
};
o = s.option(form.DummyValue, 'pu_proxy_cur', _('GitHub proxy'));
o.cfgvalue = function () { return PU.proxy || _('direct'); };
o = s.option(form.Button, 'pu_proxy', _('Proxy settings'));
o.inputstyle = 'action'; o.inputtitle = _('Set proxy');
o.onclick = function () {
	var inp = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%',
		'placeholder': 'http://10.0.0.5:7897', 'value': PU.proxy || '' });
	ui.showModal(_('GitHub proxy'), [
		E('p', {}, _('Empty means direct connection. Example: http://10.0.0.5:7897')),
		inp,
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]),
			' ',
			E('button', { 'class': 'btn cbi-button-action important', 'click': function () {
				var v = inp.value.trim();
				return fs.write('/etc/ponwrt-update.proxy', v + '\n').then(function () {
					ui.hideModal();
					ui.addNotification(null, E('p', {}, _('Saved')), 'info');
				});
			} }, [ _('Save') ])
		])
	]);
};
"""

FETCH_SNIPPET = ("tasks.push(fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ])"
                 ".catch(function () { return { code: 1, stdout: '{}' }; }));\n\t\t")


def main(path):
    src = open(path, encoding='utf-8').read()
    if 'ponwrt-update-check' in src:
        print('already patched')
        return 0

    # 1) load(): 在 return Promise.all(tasks); 之前 push 一次检查
    if 'return Promise.all(tasks);' not in src:
        print('FAIL: Promise.all anchor not found')
        return 1
    src = src.replace('return Promise.all(tasks);',
                      FETCH_SNIPPET + 'return Promise.all(tasks);', 1)

    # 2) render([...]) -> render([..., pu])
    m = re.search(r'render\(\s*\[([^\]]*)\]\s*\)', src)
    if not m:
        print('FAIL: render() anchor not found')
        return 1
    params = m.group(1).rstrip()
    new = 'render([%s, pu])' % params
    src = src[:m.start()] + new + src[m.end():]

    # 3) m.readonly = isReadonlyView; 之后插入区块
    m2 = re.search(r'm\.readonly\s*=\s*isReadonlyView\s*;', src)
    if not m2:
        print('FAIL: form anchor not found')
        return 1
    src = src[:m2.end()] + BLOCK + src[m2.end():]

    open(path, 'w', encoding='utf-8').write(src)
    print('patched')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
