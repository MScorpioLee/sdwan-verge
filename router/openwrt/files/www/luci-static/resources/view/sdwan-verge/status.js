'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

var corePath = '/usr/libexec/sdwan-verge/sdwan-verge-core';

function parseStatus(response) {
        try {
                return JSON.parse(response.stdout || '{}');
        } catch (error) {
                return {
                        enabled: false,
                        active: false,
                        mode: 'half_route',
                        gateway: '',
                        syncDns: false,
                        routes: {
                                lower: false,
                                upper: false
                        },
                        dnsServers: [],
                        logFile: '',
                        error: String(error)
                };
        }
}

function textOrDash(value) {
        return value ? String(value) : '-';
}

function modeLabel(mode) {
        return mode === 'tun' ? 'TUN' : 'Half Route';
}

function routeCount(status) {
        var count = 0;

        if (status.routes && status.routes.lower) {
                count++;
        }

        if (status.routes && status.routes.upper) {
                count++;
        }

        return count;
}

function badge(text, active) {
        return E('span', {
                'class': active ? 'sdwan-badge sdwan-badge-ok' : 'sdwan-badge sdwan-badge-idle'
        }, text);
}

function metric(title, value, hint) {
        return E('div', { 'class': 'sdwan-metric' }, [
                E('div', { 'class': 'sdwan-metric-title' }, title),
                E('div', { 'class': 'sdwan-metric-value' }, value),
                E('div', { 'class': 'sdwan-metric-hint' }, hint || '')
        ]);
}

function panel(title, children) {
        return E('div', { 'class': 'sdwan-card' }, [
                E('div', { 'class': 'sdwan-card-title' }, title),
                E('div', { 'class': 'sdwan-card-body' }, children)
        ]);
}

function actionButton(label, action, style) {
        return E('button', {
                'class': 'btn cbi-button sdwan-action ' + (style || 'cbi-button-action'),
                'click': function(ev) {
                        ev.preventDefault();
                        return runCore(action);
                }
        }, label);
}

function runCore(action) {
        return fs.exec(corePath, [action]).then(function(response) {
                ui.addNotification(null, E('pre', {}, response.stdout || _('Command completed')), 'info');
                window.setTimeout(function() {
                        window.location.reload();
                }, 600);
        }).catch(function(error) {
                ui.addNotification(null, E('pre', {}, error.message || String(error)), 'danger');
        });
}

function renderLogs(response) {
        var lines = (response.stdout || '').split('\n').filter(function(line) {
                return line.trim().length > 0;
        }).slice(-8).reverse();

        if (!lines.length) {
                return E('div', { 'class': 'sdwan-empty' }, _('暂无运行日志'));
        }

        return E('div', { 'class': 'sdwan-log-list' }, lines.map(function(line) {
                return E('div', { 'class': 'sdwan-log-item' }, [
                        E('span', { 'class': 'sdwan-log-dot' }),
                        E('span', {}, line)
                ]);
        }));
}

function renderDashboard(status, logsResponse, formNode) {
        var active = !!status.active;
        var mode = status.mode || 'half_route';
        var routes = routeCount(status);
        var dnsServers = status.dnsServers || [];
        var tunNotice = mode === 'tun'
                ? E('div', { 'class': 'sdwan-warning' }, _('TUN 模式为实验入口，当前 OpenWrt/iStoreOS 包尚未接入真实 TUN 后端，启动会被拒绝以避免黑洞流量。'))
                : '';

        return E('div', { 'class': 'sdwan-page' }, [
                E('style', {}, [
                        '.sdwan-page{color:#1f2937}.sdwan-oc-tabs{display:flex;gap:0;background:#fff;border-radius:4px;margin-bottom:14px;box-shadow:0 1px 3px rgba(15,23,42,.08);overflow:hidden}.sdwan-oc-tabs span{padding:14px 22px;border-right:1px solid #edf2f7;color:#596579}.sdwan-oc-tabs .active{background:#eaf1ff;color:#2563eb;border-bottom:3px solid #2563eb}.sdwan-title-card{background:#fff;border-radius:4px;padding:18px 20px;margin-bottom:12px;box-shadow:0 1px 3px rgba(15,23,42,.08)}.sdwan-title-card h2{margin:0;font-size:24px}.sdwan-desc{padding:14px 18px;background:#f7f9fc;border:1px solid #dce5f2;border-radius:4px;color:#394867;margin-bottom:12px}.sdwan-blue-strip{height:38px;display:flex;align-items:center;justify-content:center;border-radius:6px;background:linear-gradient(90deg,#1d4ed8,#3b82f6);color:#fff;margin-bottom:12px}.sdwan-panel-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.sdwan-card{background:#eef3f9;border:1px solid #d7e0ec;border-radius:6px;padding:14px;min-height:128px}.sdwan-card-title{font-weight:700;margin-bottom:12px}.sdwan-card-body{display:flex;flex-wrap:wrap;gap:10px}.sdwan-badge{display:inline-flex;align-items:center;border-radius:4px;padding:8px 12px;font-weight:700}.sdwan-badge-ok{color:#059669;background:#ecfdf5}.sdwan-badge-idle{color:#64748b;background:#fff}.sdwan-action{min-width:132px;height:42px;border-radius:5px}.sdwan-metric{background:#fff;border:1px solid #dce5f2;border-radius:6px;padding:12px;min-width:150px;flex:1}.sdwan-metric-title{color:#64748b}.sdwan-metric-value{font-size:18px;font-weight:800;margin-top:8px}.sdwan-metric-hint{font-size:12px;color:#7b8aa2;margin-top:6px}.sdwan-warning{width:100%;padding:10px 12px;background:#fff7ed;border:1px solid #fed7aa;border-radius:6px;color:#b45309}.sdwan-form-wrap{margin-top:12px}.sdwan-log-list{display:flex;flex-direction:column;gap:8px;width:100%}.sdwan-log-item{display:flex;gap:8px;align-items:flex-start;color:#42526b}.sdwan-log-dot{width:8px;height:8px;border-radius:99px;background:#2563eb;margin-top:6px;flex:none}.sdwan-empty{color:#7b8aa2}.sdwan-muted{color:#64748b}@media(max-width:900px){.sdwan-panel-grid{grid-template-columns:1fr}.sdwan-action{width:100%}}'
                ]),
                E('div', { 'class': 'sdwan-oc-tabs' }, [
                        E('span', { 'class': 'active' }, _('运行状态')),
                        E('span', {}, _('插件设置')),
                        E('span', {}, _('覆写设置')),
                        E('span', {}, _('一键生成')),
                        E('span', {}, _('规则附加')),
                        E('span', {}, _('配置订阅')),
                        E('span', {}, _('配置管理')),
                        E('span', {}, _('运行日志'))
                ]),
                E('div', { 'class': 'sdwan-title-card' }, [
                        E('h2', {}, 'SD-WAN Verge'),
                ]),
                E('div', { 'class': 'sdwan-desc' }, _('在 OpenWrt/iStoreOS 上管理 CPE 旁路由加速。Half Route 使用系统路由交给 CPE，TUN 为后续实验模式入口。')),
                E('div', { 'class': 'sdwan-blue-strip' }, 'SD-WAN Verge Router Core'),
                E('div', { 'class': 'sdwan-panel-grid' }, [
                        panel(_('运行状态'), [
                                badge(active ? _('运行中') : _('未运行'), active),
                                metric(_('运行模式'), modeLabel(mode), mode === 'tun' ? _('实验入口') : _('推荐')),
                                metric(_('CPE 网关'), textOrDash(status.gateway), active ? _('正在接管 IPv4') : _('等待启动')),
                                tunNotice
                        ]),
                        panel(_('控制面板'), [
                                metric(_('半路由'), routes + '/2', _('0.0.0.0/1 与 128.0.0.0/1')),
                                metric(_('DNS 同步'), status.syncDns ? _('启用') : _('停用'), dnsServers.join(', ') || '-'),
                                metric(_('配置状态'), status.enabled ? _('开机启用') : _('手动启用'), _('UCI 配置')),
                        ]),
                        panel(_('快捷操作'), [
                                actionButton(_('开启加速'), 'start', 'cbi-button-apply'),
                                actionButton(_('关闭连接'), 'stop', 'cbi-button-reset'),
                                actionButton(_('重启服务'), 'restart', 'cbi-button-reload'),
                                actionButton(_('运行诊断'), 'doctor', 'cbi-button-action'),
                                actionButton(_('查看日志'), 'logs', 'cbi-button-action')
                        ]),
                        panel(_('实时统计'), [
                                metric(_('IPv4 路由'), active ? _('已接管') : _('未接管'), _('仅 IPv4')),
                                metric(_('LAN 通信'), _('不接管'), _('局域网更具体路由优先')),
                                metric(_('DNS 服务器'), dnsServers.length ? String(dnsServers.length) : '0', dnsServers.join(', ') || _('未设置'))
                        ]),
                        panel(_('运行日志'), [
                                renderLogs(logsResponse)
                        ]),
                        panel(_('插件设置'), [
                                E('div', { 'class': 'sdwan-form-wrap' }, formNode)
                        ])
                ])
        ]);
}

return view.extend({
        load: function() {
                return Promise.all([
                        uci.load('sdwan_verge'),
                        fs.exec(corePath, ['status']).catch(function(error) {
                                return {
                                        stdout: '{}',
                                        stderr: error.message || String(error)
                                };
                        }),
                        fs.exec(corePath, ['logs']).catch(function(error) {
                                return {
                                        stdout: '',
                                        stderr: error.message || String(error)
                                };
                        })
                ]);
        },

        render: function(data) {
                var status = parseStatus(data[1]);
                var logsResponse = data[2];
                var map = new form.Map('sdwan_verge', '', '');
                var section = map.section(form.NamedSection, 'main', 'settings', _('插件设置'));
                section.anonymous = true;

                var mode = section.option(form.ListValue, 'mode', _('运行模式'));
                mode.default = 'half_route';
                mode.rmempty = false;
                mode.value('half_route', _('Half Route'));
                mode.value('tun', _('TUN'));
                mode.description = _('Half Route 当前可用；TUN 模式为实验入口，后续接入真实后端。');

                var enabled = section.option(form.Flag, 'enabled', _('开机启用'));
                enabled.default = '0';
                enabled.rmempty = false;

                var gateway = section.option(form.Value, 'cpe_gateway', _('CPE 网关'));
                gateway.datatype = 'ip4addr';
                gateway.placeholder = '192.168.1.140';
                gateway.rmempty = false;

                var syncDns = section.option(form.Flag, 'sync_dns', _('同步 dnsmasq DNS'));
                syncDns.default = '1';
                syncDns.rmempty = false;

                var dns = section.option(form.DynamicList, 'dns_server', _('DNS 服务器'));
                dns.datatype = 'ip4addr';
                dns.placeholder = '192.168.1.140';

                return map.render().then(function(formNode) {
                        return renderDashboard(status, logsResponse, formNode);
                });
        }
});
