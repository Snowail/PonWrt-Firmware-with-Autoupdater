'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
	load: function () {
		return Promise.all([
			fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ])
				.catch(function () { return { stdout: '{}' }; }),
			L.resolveDefault(fs.read('/etc/ponwrt-update.proxy'), '')
		]);
	},

	render: function (data) {
		var res = (data && data[0]) || {};
		var proxy = ((data && data[1]) || '').trim();
		var PU = {};
		try { PU = JSON.parse(res.stdout || '{}'); } catch (e) { PU = {}; }

		/* NamedSection 需要有对应的数据段，否则只渲染标题、不会渲染选项 */
		var mapdata = { main: {} };
		var m = new form.JSONMap(mapdata, '固件更新');
		var s = m.section(form.NamedSection, 'main', 'main', '固件更新',
			'检查本仓库的最新发布，或直接下载并刷写');

		var o = s.option(form.DummyValue, 'cur', '当前版本');
		o.cfgvalue = function () {
			return (PU.device || '未知') + ' / ' + (PU.cur_built || '未知');
		};

		o = s.option(form.DummyValue, 'latest', '最新版本');
		o.cfgvalue = function () { return PU.latest || '—'; };

		o = s.option(form.DummyValue, 'status', '状态');
		o.cfgvalue = function () {
			if (PU.error) return '检查失败：' + PU.error;
			return PU.update ? '发现新版本' : '已是最新';
		};

		o = s.option(form.DummyValue, 'proxy_cur', 'GitHub 代理');
		o.cfgvalue = function () { return proxy || '直连'; };

		o = s.option(form.Button, 'check', '检查更新');
		o.inputstyle = 'action';
		o.inputtitle = '立即检查';
		o.onclick = function () {
			ui.showModal('正在检查…', [ E('p', { 'class': 'spinning' }, '') ]);
			return fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ]).then(function (r) {
				ui.hideModal();
				ui.addNotification(null, E('pre', {}, r.stdout || ''), 'info');
			});
		};

		o = s.option(form.Button, 'flash', '刷写固件');
		o.inputstyle = 'negative important';
		o.inputtitle = '下载并刷写';
		o.onclick = function () {
			if (!confirm('将下载最新固件并立即刷写，期间不要断电。继续？'))
				return;
			ui.showModal('正在下载…', [ E('p', { 'class': 'spinning' }, '') ]);
			return fs.exec('/usr/bin/ponwrt-update-check', [ '--flash' ]).then(function (r) {
				ui.hideModal();
				ui.addNotification(null, E('pre', {}, (r.stdout || '') + (r.stderr || '')), 'info');
			});
		};

		o = s.option(form.Button, 'setproxy', '代理设置');
		o.inputstyle = 'action';
		o.inputtitle = '设置代理';
		o.onclick = function () {
			var inp = E('input', { 'type': 'text', 'style': 'width:100%',
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
		};

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
