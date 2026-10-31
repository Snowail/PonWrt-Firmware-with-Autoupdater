#!/usr/bin/env python3
"""给 LuCI 的「系统 → 备份/升级」页面打补丁：底部追加「固件更新」面板。

用法:
  patch-flash.py <path/to/flash.js>          打补丁（重复执行会先撤销）
  patch-flash.py <path/to/flash.js> --undo   撤销

设计说明:
  上次用 form.NamedSection 注入区块，结果只渲染出标题——CBI 的 NamedSection
  依赖真实数据段，JSONMap 里补空对象也不行。
  这里改成不碰 CBI：直接构造 DOM，包一层 m.render()，把面板 append 到页面末尾。
  原有的备份 / 恢复 / mtdblock / 刷写 / sysupgrade.conf 五块完全不动。
"""
import re
import sys

BEGIN = '/* ponwrt updater ==== 由 tools/patch-flash.py 注入，勿手改 ==== */'
END = '/* ponwrt updater ==== end ==== */'

BLOCK = BEGIN + r"""
var PU = (function () { try { return JSON.parse((pu && pu.stdout) || '{}'); } catch (e) { return {}; } })();
var _ponwrtOrigRender = m.render.bind(m);
m.render = function () {
	var cells = [
		[ '当前版本', (PU.device || '未知') + ' / ' + (PU.cur_built || '未知') ],
		[ '最新版本', PU.latest || '-' ],
		[ '状态', PU.error ? ('检查失败：' + PU.error) : (PU.update ? '发现新版本' : '已是最新') ],
		[ 'GitHub 代理', PU.proxy || '直连' ]
	];
	var btnCheck = E('button', { 'class': 'cbi-button cbi-button-action', 'click': function () {
		ui.showModal('正在检查…', [ E('p', { 'class': 'spinning' }, '') ]);
		return fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ]).then(function (r) {
			ui.hideModal();
			ui.addNotification(null, E('pre', {}, r.stdout || ''), 'info');
		});
	} }, [ '立即检查' ]);
	var btnFlash = E('button', { 'class': 'cbi-button cbi-button-negative', 'style': 'margin-left:.5em', 'click': function () {
		if (!confirm('将下载最新固件并立即刷写，期间不要断电。继续？')) return;
		ui.showModal('正在下载…', [ E('p', { 'class': 'spinning' }, '') ]);
		return fs.exec('/usr/bin/ponwrt-update-check', [ '--flash' ]).then(function (r) {
			ui.hideModal();
			ui.addNotification(null, E('pre', {}, (r.stdout || '') + (r.stderr || '')), 'info');
		});
	} }, [ '下载并刷写' ]);
	var btnProxy = E('button', { 'class': 'cbi-button', 'style': 'margin-left:.5em', 'click': function () {
		var inp = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%',
			'placeholder': 'http://10.0.0.5:7897', 'value': PU.proxy || '' });
		ui.showModal('GitHub 代理', [
			E('p', {}, '留空表示直连。例如：http://10.0.0.5:7897'),
			inp,
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, [ '取消' ]),
				' ',
				E('button', { 'class': 'btn cbi-button-action important', 'click': function () {
					return fs.write('/etc/ponwrt-update.proxy', inp.value.trim() + '\n')
						.then(function () { ui.hideModal(); window.location.reload(); });
				} }, [ '保存' ])
			])
		]);
	} }, [ '设置代理' ]);
	var box = E('div', { 'class': 'cbi-section', 'id': 'ponwrt-update' }, [
		E('h3', {}, '在线更新检查'),
		E('div', { 'class': 'cbi-section-descr' }, '检查本仓库的最新发布，或直接下载并刷写'),
		E('table', { 'class': 'table' }, cells.map(function (c) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'width': '33%' }, c[0]),
				E('td', { 'class': 'td' }, c[1])
			]);
		})),
		E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:1em' }, [ btnCheck, btnFlash, btnProxy ])
	]);
	var attach = function (node) {
		if (node && node.appendChild)
			node.appendChild(box);
		return node;
	};
	var r = _ponwrtOrigRender();
	return (r && typeof r.then === 'function') ? r.then(attach) : attach(r);
};
""" + END + "\n"

FETCH = ("tasks.push(fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ])"
         ".catch(function () { return { code: 1, stdout: '{}' }; }));\n\t\t")


def undo(src):
    src = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n?', '', src, flags=re.S)
    src = re.sub(r"tasks\.push\(fs\.exec\('/usr/bin/ponwrt-update-check'[^\n]*?\n", '', src)
    src = re.sub(r'render\(\[([^\]]*?),\s*pu\]\)', r'render([\1])', src)
    return src


def patch(src):
    src = undo(src)
    if 'return Promise.all(tasks);' not in src:
        raise SystemExit('FAIL: Promise.all anchor not found')
    src = src.replace('return Promise.all(tasks);', FETCH + 'return Promise.all(tasks);', 1)

    m = re.search(r'render\(\s*\[([^\]]*)\]\s*\)', src)
    if not m:
        raise SystemExit('FAIL: render() anchor not found')
    src = src[:m.start()] + 'render([%s, pu])' % m.group(1).rstrip() + src[m.end():]

    m2 = re.search(r'm\.readonly\s*=\s*isReadonlyView\s*;', src)
    if not m2:
        raise SystemExit('FAIL: form anchor not found')
    return src[:m2.end()] + '\n' + BLOCK + src[m2.end():]


def main(path, undo_only=False):
    src = open(path, encoding='utf-8').read()
    src = undo(src) if undo_only else patch(src)
    open(path, 'w', encoding='utf-8').write(src)
    print('undone' if undo_only else 'patched')
    return 0


if __name__ == '__main__':
    undo_only = '--undo' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    sys.exit(main(args[0], undo_only))
