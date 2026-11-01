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
var _ponwrtOrigRender = m.render.bind(m);
m.render = function () {
	var current = E('span', {}, '读取中…');
	var latest = E('span', {}, '—');
	var status = E('span', {}, '尚未检查');
	var proxyCell = E('span', {}, '读取中…');
	var proxy = '';
	var manualCheck = false;
	var savedInterval;
	var scheduleHint = E('span', {}, '');
	var choices = { daily: '每天', weekly: '每周', monthly: '每 30 天', off: '关闭' };
	var interval = E('select', { 'disabled': true, 'aria-label': '固件检查频率', 'change': function () {
		var value = interval.value;
		interval.disabled = true;
		return fs.write('/etc/ponwrt-update.interval', value + '\n').then(function () {
			savedInterval = value;
			scheduleHint.textContent = ' 已保存';
		}).catch(function (err) {
			interval.value = savedInterval;
			scheduleHint.textContent = ' 保存失败：' + err.message;
		}).finally(function () { interval.disabled = isReadonlyView; });
	} }, Object.keys(choices).map(function (key) {
		return E('option', { value: key, selected: key === 'weekly' || null }, choices[key]);
	}));
	var cells = [
		[ '当前版本', current ], [ '最新版本', latest ],
		[ '状态', status ], [ 'GitHub 代理', proxyCell ],
		[ '固件检查频率', E('div', {}, [ interval, scheduleHint ]) ]
	];
	var btnCheck = E('button', { 'class': 'cbi-button cbi-button-action', 'click': function () {
		manualCheck = true;
		btnCheck.disabled = true;
		btnFlash.disabled = true;
		status.textContent = '正在检查…';
		latest.textContent = '—';
		return fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ]).then(function (r) {
			if (r.code !== 0) throw new Error(r.stderr || '更新检查程序执行失败');
			var result = JSON.parse(r.stdout);
			if (result.error) throw new Error(result.error);
			if (!result.latest || (result.update !== 0 && result.update !== 1))
				throw new Error('更新检查返回的数据不完整');
			latest.textContent = result.latest;
			status.textContent = result.update ? '发现新版本' : '已是最新';
			btnFlash.disabled = isReadonlyView || !result.update;
		}).catch(function (err) {
			status.textContent = '检查失败：' + err.message;
		}).finally(function () { btnCheck.disabled = false; });
	} }, [ '立即检查' ]);
	var btnFlash = E('button', { 'disabled': true, 'class': 'cbi-button cbi-button-negative', 'style': 'margin-left:.5em', 'click': function () {
		if (!confirm('将下载最新固件并立即刷写，期间不要断电。继续？')) return;
		ui.showModal('正在下载…', [ E('p', { 'class': 'spinning' }, '') ]);
		return fs.exec('/usr/bin/ponwrt-update-check', [ '--flash' ]).then(function (r) {
			ui.addNotification(null, E('pre', {}, (r.stdout || '') + (r.stderr || '')), 'info');
		}).catch(function (err) {
			ui.addNotification(null, E('p', {}, err.message), 'error');
		}).finally(function () { ui.hideModal(); });
	} }, [ '下载并刷写' ]);
	var btnProxy = E('button', { 'disabled': isReadonlyView || null, 'class': 'cbi-button', 'style': 'margin-left:.5em', 'click': function () {
		var inp = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%',
			'placeholder': 'http://10.0.0.5:7897', 'value': proxy });
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
		node.appendChild(box);
		fs.read('/etc/ponwrt-update.interval').then(function (text) {
			savedInterval = text.trim();
			if (!Object.prototype.hasOwnProperty.call(choices, savedInterval)) throw new Error('无效设置');
			interval.value = savedInterval;
			interval.disabled = isReadonlyView;
		}).catch(function (err) {
			scheduleHint.textContent = err.name === 'NotFoundError' ? ' 当前固件未内置定时检查' : ' 读取失败：' + err.message;
		});
		fs.read('/etc/ponwrt-version').then(function (text) {
			var device = /^device=([^\r\n]+)$/m.exec(text);
			var built = /^built=([^\r\n]+)$/m.exec(text);
			if (!device || !built) throw new Error('缺少 device 或 built 字段');
			current.textContent = device[1] + ' / ' + built[1];
			fs.read('/etc/ponwrt-update.state').then(function (text) {
				var record = text.trimEnd().split('\n');
				if (manualCheck || record.length !== 4 || record[0] !== device[1] + '/' + built[1]) return;
				latest.textContent = record[3];
				status.textContent = (record[2] ? '发现新版本' : '已是最新') +
					'（上次检查：' + new Date(Number(record[1]) * 1000).toLocaleString() + '）';
				btnFlash.disabled = isReadonlyView || !record[2];
			}).catch(function () { /* No cached result on older images or before the first check. */ });
		}).catch(function (err) {
			current.textContent = '无法读取 /etc/ponwrt-version：' + err.message;
		});
		fs.read('/etc/ponwrt-update.proxy').then(function (text) {
			proxy = text.trim();
			proxyCell.textContent = proxy || '直连';
		}).catch(function (err) {
			proxyCell.textContent = err.name === 'NotFoundError' ? '直连' : '读取代理失败：' + err.message;
		});
		return node;
	};
	var r = _ponwrtOrigRender();
	return (r && typeof r.then === 'function') ? r.then(attach) : attach(r);
};
""" + END + "\n"

def undo(src):
    src = re.sub(r'\n' + re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n?', '', src, flags=re.S)
    src = re.sub(r"(?m)^[ \t]*tasks\.push\(fs\.exec\('/usr/bin/ponwrt-update-check'[^\n]*?\n", '', src)
    src = re.sub(r'render\(\[([^\]]*?),\s*pu\]\)', r'render([\1])', src)
    return src


def patch(src):
    src = undo(src)
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
