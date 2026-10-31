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

		var m = new form.JSONMap({}, _('Firmware update'));
		var s = m.section(form.NamedSection, 'main', 'main', _('Firmware update'));

		var o = s.option(form.DummyValue, 'cur', _('Current version'));
		o.cfgvalue = function () { return (PU.device || 'unknown') + ' / ' + (PU.cur_built || 'unknown'); };

		o = s.option(form.DummyValue, 'latest', _('Latest version'));
		o.cfgvalue = function () { return PU.latest || '-'; };

		o = s.option(form.DummyValue, 'status', _('Status'));
		o.cfgvalue = function () {
			if (PU.error) return _('Check failed') + ': ' + PU.error;
			return PU.update ? _('New version available') : _('Up to date');
		};

		o = s.option(form.DummyValue, 'proxy_cur', _('GitHub proxy'));
		o.cfgvalue = function () { return proxy || _('direct'); };

		o = s.option(form.Button, 'check', _('Check for updates'));
		o.inputstyle = 'action';
		o.inputtitle = _('Check now');
		o.onclick = function () {
			ui.showModal(_('Checking...'), [ E('p', { 'class': 'spinning' }, '') ]);
			return fs.exec('/usr/bin/ponwrt-update-check', [ '--json' ]).then(function (r) {
				ui.hideModal();
				ui.addNotification(null, E('pre', {}, r.stdout || ''), 'info');
			});
		};

		o = s.option(form.Button, 'flash', _('Download and flash'));
		o.inputstyle = 'negative important';
		o.inputtitle = _('Download and flash');
		o.onclick = function () {
			if (!confirm(_('Download the latest firmware and flash it now? Do not power off.')))
				return;
			ui.showModal(_('Downloading...'), [ E('p', { 'class': 'spinning' }, '') ]);
			return fs.exec('/usr/bin/ponwrt-update-check', [ '--flash' ]).then(function (r) {
				ui.hideModal();
				ui.addNotification(null, E('pre', {}, (r.stdout || '') + (r.stderr || '')), 'info');
			});
		};

		o = s.option(form.Button, 'setproxy', _('Proxy settings'));
		o.inputstyle = 'action';
		o.inputtitle = _('Set proxy');
		o.onclick = function () {
			var inp = E('input', { 'type': 'text', 'style': 'width:100%',
				'placeholder': 'http://10.0.0.5:7897', 'value': proxy });
			ui.showModal(_('GitHub proxy'), [
				E('p', {}, _('Empty means direct connection. Example: http://10.0.0.5:7897')),
				inp,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]),
					' ',
					E('button', { 'class': 'btn cbi-button-action important', 'click': function () {
						return fs.write('/etc/ponwrt-update.proxy', inp.value.trim() + '\n')
							.then(function () { ui.hideModal(); window.location.reload(); });
					} }, [ _('Save') ])
				])
			]);
		};

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
