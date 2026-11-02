'use strict';
const assert = require('node:assert/strict');
const source = require('node:fs').readFileSync(process.argv[2], 'utf8');

async function test(readonly, failStart) {
    let enabled = false, running = false, toggle, status, option, refresh;
    const actions = [], notifications = [];
    function E(tag, attrs, children) {
        const node = { ...attrs, children, textContent: typeof children === 'string' ? children : '',
            events: {}, addEventListener(name, handler) { this.events[name] = handler; } };
        if (tag === 'input') toggle = node;
        if (tag === 'span') status = node;
        return node;
    }
    class Map {
        section() {
            const map = this;
            function makeOption(tab, type, name) {
                const result = { map };
                if (name === '_ponwrt_service') option = result;
                return result;
            }
            return { tab() {}, taboption: makeOption, option() { return {}; } };
        }
        render() { return option.renderWidget(); }
    }
    const fs = { async exec(path, args) {
        assert.equal(path, '/etc/init.d/samba4');
        const action = args[0];
        if (action === 'enabled') return { code: enabled ? 0 : 1 };
        if (action === 'running') return { code: running ? 0 : 1 };
        actions.push(action);
        if (action === 'enable') enabled = true;
        if (action === 'disable') enabled = false;
        if (action === 'start') {
            if (failStart) return { code: 1, stderr: 'fixture startup failure' };
            running = true;
        }
        if (action === 'stop') running = false;
        return { code: 0 };
    } };
    const page = new Function('view', 'fs', 'form', 'uci', 'widgets', 'poll', 'ui', 'E', 'L', '_', source)(
        { extend: x => x }, fs, { Map }, {}, {},
        { add(fn) { refresh = fn; }, remove() {} },
        { addNotification(title, node) { notifications.push(node); } }, E,
        { hasViewPermission: () => !readonly }, text => text);
    await page.render([null, null, {}, {}, {}, { code: 0, stdout: 'Samba test' }]);
    await new Promise(setImmediate);
    assert.equal(toggle.checked, false);
    assert.equal(toggle.disabled, readonly);
    assert.equal(status.textContent, '未运行');
    toggle.checked = true;
    await toggle.events.change();
    if (readonly) {
        assert.deepEqual(actions, []);
    } else if (failStart) {
        assert.deepEqual(actions, ['enable', 'start', 'disable']);
        assert.equal(enabled, false);
        assert.equal(toggle.checked, false);
        assert.equal(notifications.length, 1);
    } else {
        assert.equal(status.textContent, '运行中');
        assert.equal(enabled, true);
        running = false;
        await refresh();
        assert.equal(status.textContent, '未运行');
        assert.equal(toggle.checked, true);
        toggle.checked = false;
        await toggle.events.change();
        assert.deepEqual(actions, ['enable', 'start', 'disable', 'stop']);
        assert.equal(enabled, false);
    }
}
Promise.all([test(false, false), test(false, true), test(true, false)])
    .then(() => console.log('PASS: Samba enable/start, disable/stop, polling, startup rollback and read-only view'))
    .catch(error => { console.error(error); process.exitCode = 1; });
