'use strict';
'require baseclass';
'require fs';
'require poll';
'require ui';

return baseclass.extend({
	start: function () {
		var banner, displayed;
		function refresh() {
			return Promise.all([fs.read('/etc/ponwrt-version'), fs.read('/etc/ponwrt-update.state')])
				.then(function (files) {
					var device = /^device=([^\r\n]+)$/m.exec(files[0]);
					var built = /^built=([^\r\n]+)$/m.exec(files[0]);
					var record = files[1].trimEnd().split('\n');
					var latest = (device && built && record[0] === device[1] + '/' + built[1]) ? record[2] : '';
					if (latest === displayed) return;
					if (banner) banner.remove();
					displayed = latest;
					if (latest) {
						banner = ui.addNotification('发现新的 PonWrt 固件', E('p', {}, [
							document.createTextNode(latest + '　'),
							E('a', { href: L.url('admin', 'system', 'flash') + '#ponwrt-update' }, '前往备份与更新')
						]), 'warning');
					}
				}).catch(function () { /* No successful check yet, or session expired. */ });
		}
		refresh().then(function () { poll.add(refresh, 60); });
	}
});
