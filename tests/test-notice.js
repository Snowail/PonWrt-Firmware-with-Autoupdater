'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const source = readFileSync(__dirname + '/../overlay/www/luci-static/resources/ponwrt/notice.js', 'utf8');
async function test() {
	let tick, record, visible, count = 0;
	const fs = { read: async path => {
		if (path === '/etc/ponwrt-version') return 'device=router\nbuilt=local\n';
		assert.equal(path, '/etc/ponwrt-update.state');
		if (!record) throw Error('No cached check');
		return record;
	} };
	const poll = { add(fn, seconds) { assert.equal(seconds, 60); tick = fn; } };
	const ui = { addNotification(title, body, style) {
		assert.match(title, /固件/);
		assert.equal(style, 'warning');
		assert.equal(body.children[1].attrs.href, '/admin/system/flash#ponwrt-update');
		count++;
		visible = body.children[0];
		return { remove() { visible = undefined; } };
	} };
	const notice = new Function('baseclass','fs','poll','ui','E','L','document', source)(
		{ extend: obj => obj }, fs, poll, ui, (tag, attrs, children) => ({ attrs, children }),
		{ url: (...parts) => '/' + parts.join('/') }, { createTextNode: s => s });
	notice.start();
	await new Promise(resolve => setImmediate(resolve));
	assert.equal(count, 0);
	record = 'router/local\n1234567890\nv2\nv2\n';
	await tick();
	await tick();
	assert.equal(count, 1);
	assert.match(visible, /v2/);
	record = record.replace('router/local', 'router/other');
	await tick();
	assert.equal(visible, undefined);
	record = 'router/local\n1234567891\n\nv1\n';
	await tick();
	assert.equal(count, 1);
}
test().catch(err => { console.error(err); process.exitCode = 1; });
