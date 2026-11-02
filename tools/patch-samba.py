#!/usr/bin/env python3
"""Add service controls to the existing Samba page with narrowly scoped ACLs."""
import json
import re
import sys
from pathlib import Path

BEGIN = "/* PONWRT_SAMBA_SERVICE_BEGIN */"
END = "/* PONWRT_SAMBA_SERVICE_END */"
WIDGET = r"""
/* PONWRT_SAMBA_SERVICE_BEGIN */
        o = s.taboption('general', form.DummyValue, '_ponwrt_service', '服务控制');
        o.renderWidget = function() {
            var busy = false, revision = 0, enabled = false;
            var readonly = !L.hasViewPermission();
            var status = E('span', {}, '读取中…');
            var toggle = E('input', { type: 'checkbox', disabled: true });
            function command(action) {
                return fs.exec('/etc/init.d/samba4', [ action ]).then(function(result) {
                    if (result.code !== 0)
                        throw new Error(result.stderr || result.stdout || '服务操作失败：' + action);
                });
            }
            function refresh() {
                if (busy) return Promise.resolve();
                var request = ++revision;
                return Promise.all([
                    fs.exec('/etc/init.d/samba4', [ 'enabled' ]),
                    fs.exec('/etc/init.d/samba4', [ 'running' ])
                ]).then(function(results) {
                    if (request !== revision || busy) return;
                    if (results.some(function(r) { return r.code !== 0 && r.code !== 1; }))
                        throw new Error('无法读取服务状态');
                    enabled = results[0].code === 0;
                    toggle.checked = enabled;
                    toggle.disabled = readonly;
                    status.textContent = results[1].code === 0 ? '运行中' : '未运行';
                }).catch(function(error) {
                    if (request !== revision || busy) return;
                    toggle.disabled = true;
                    status.textContent = '状态读取失败：' + error.message;
                });
            }
            toggle.addEventListener('change', function() {
                if (readonly || busy) return Promise.resolve();
                var wanted = toggle.checked, previous = enabled;
                busy = true;
                revision++;
                toggle.disabled = true;
                status.textContent = wanted ? '正在启动…' : '正在停止…';
                return command(wanted ? 'enable' : 'disable')
                    .then(function() { return command(wanted ? 'start' : 'stop'); })
                    .catch(function(error) {
                        // Restore the previous boot policy when startup fails.
                        var rollback = wanted && !previous ? command('disable') : Promise.resolve();
                        return rollback.catch(function(restoreError) {
                            error.message += '；恢复自启状态失败：' + restoreError.message;
                        }).then(function() {
                            ui.addNotification(null, E('p', {}, error.message), 'error');
                        });
                    }).finally(function() {
                        busy = false;
                        return refresh();
                    });
            });
            if (this.map._ponwrtSambaPoll) poll.remove(this.map._ponwrtSambaPoll);
            this.map._ponwrtSambaPoll = refresh;
            poll.add(refresh, 5);
            refresh();
            return E('div', {}, [
                E('label', {}, [ toggle, ' 启用服务并开机自启' ]),
                E('div', { style: 'margin-top: .5em' }, [ '运行状态：', status ])
            ]);
        };
/* PONWRT_SAMBA_SERVICE_END */
"""


def patch(page, acl):
    page, acl = Path(page), Path(acl)
    source = page.read_text(encoding="utf-8")
    source = re.sub(r"\n?" + re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "", source, flags=re.S)
    for dependency in ("poll", "ui"):
        directive = f"'require {dependency}';"
        if directive not in source:
            source = source.replace("'require fs';", "'require fs';\n" + directive, 1)
    anchor = re.search(r"\bo\s*=\s*s\.taboption\('general',\s*widgets\.NetworkSelect", source)
    if not anchor or "'require fs';" not in source:
        raise ValueError("Samba page anchors changed")
    source = source[:anchor.start()] + WIDGET + source[anchor.start():]
    rules = json.loads(acl.read_text(encoding="utf-8"))
    group = rules["luci-app-samba4"]
    for permission, actions in (("read", ("enabled", "running")),
                                ("write", ("enable", "disable", "start", "stop"))):
        entry = group.setdefault(permission, {})
        methods = entry.setdefault("ubus", {}).setdefault("file", [])
        if "exec" not in methods:
            methods.append("exec")
        files = entry.setdefault("file", {})
        for action in actions:
            files[f"/etc/init.d/samba4 {action}"] = ["exec"]
    page.write_text(source, encoding="utf-8")
    acl.write_text(json.dumps(rules, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")


if __name__ == "__main__":
    patch(*sys.argv[1:])
