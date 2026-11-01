// Exercise the generated page through the LuCI view entry points, without a router.
'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const source = readFileSync(process.argv[2], 'utf8');

async function test(metadata, expected) {
	const rows = new Map();
	const buttons = new Map();
	function E(tag, attrs, children) {
		const element = { textContent: typeof children === 'string' ? children : '', ...attrs };
		if (tag === 'td') element.content = children;
		if (tag === 'tr') rows.set(children[0].content, children[1].content);
		if (tag === 'button') buttons.set(children[0], element);
		return element;
	}
	const section = { option: () => ({ subsection: section }) };
	class JSONMap {
		section() { return section; }
		render() { return Promise.resolve({ appendChild(box) { assert.equal(box.id, 'ponwrt-update'); } }); }
	}
	let calls = 0;
	let online = false;
	const fs = {
		stat: async () => ({}),
		trimmed: async () => '',
		read: async path => {
			if (path === '/etc/ponwrt-update.proxy') return '';
			assert.equal(path, '/etc/ponwrt-version');
			if (metadata instanceof Error) throw metadata;
			return metadata;
		},
		exec: async (cmd, args) => {
			calls++;
			assert.equal(cmd, '/usr/bin/ponwrt-update-check');
			assert.deepEqual(args, ['--json']);
			if (!online) throw new Error('RPC timeout');
			return { code: 0, stdout: JSON.stringify({ latest: 'v2', update: 1 }) };
		}
	};
	const L = { hasViewPermission: () => true, resolveDefault: p => p, bind: fn => fn };
	const view = new Function('view', 'rpc', 'fs', 'form', 'L', 'E', '_', source)(
		{ extend: v => v }, { declare: () => () => {} }, fs, { JSONMap }, L, E, s => s);
	await view.render(await view.load());
	await new Promise(resolve => setImmediate(resolve));
	const value = key => rows.get(key).textContent;
	assert.equal(calls, 0);
	assert.match(value('当前版本'), expected);
	const local = value('当前版本');
	assert.equal(value('状态'), '尚未检查');
	await buttons.get('立即检查').click();
	assert.equal(calls, 1);
	assert.match(value('状态'), /RPC timeout/);
	assert.equal(value('当前版本'), local);
	assert.equal(buttons.get('立即检查').disabled, false);
	online = true;
	await buttons.get('立即检查').click();
	assert.equal(value('最新版本'), 'v2');
	assert.equal(value('状态'), '发现新版本');
	assert.equal(value('当前版本'), local);
}
Promise.all([
	test('device=nokia_xg-040g-md-ubi\ntarget=an7581\nbuilt=20261031-184422\n', /^nokia_xg-040g-md-ubi \/ 20261031-184422$/),
	test('device=only\n', /缺少 device 或 built/),
	test(new Error('Permission denied'), /Permission denied/)
]).catch(err => { console.error(err); process.exitCode = 1; });
