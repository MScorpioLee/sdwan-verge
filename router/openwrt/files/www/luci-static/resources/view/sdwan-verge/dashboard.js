'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

var corePath = '/usr/libexec/sdwan-verge/sdwan-verge-core';

function parseJson(response, fallback) {
        try {
                return JSON.parse(response.stdout || JSON.stringify(fallback));
        } catch (error) {
                fallback.error = String(error);
                return fallback;
        }
}

function parseStatus(response) {
        return parseJson(response, {
                enabled: false,
                active: false,
                mode: 'half_route',
                activeMode: 'half_route',
                gateway: '',
                syncDns: false,
                routes: { lower: false, upper: false },
                tun: { interface: 'sdwan-tun0', backend: '', device: false, backendReady: false, link: false },
                dnsServers: [],
                logFile: ''
        });
}

function parseTraffic(response) {
        return parseJson(response, {
                interface: '',
                rxBytes: 0,
                txBytes: 0,
                rxRate: 0,
                txRate: 0,
                active: false
        });
}

function parseSites(response) {
        var result = parseJson(response, []);
        return Array.isArray(result) ? result : [];
}

function textOrDash(value) {
        return value ? String(value) : '-';
}

function modeLabel(mode) {
        return mode === 'tun' ? 'TUN' : 'Half Route';
}

function formatBytes(value) {
        var bytes = Number(value || 0);
        var units = ['B', 'KB', 'MB', 'GB', 'TB'];
        var index = 0;

        while (bytes >= 1024 && index < units.length - 1) {
                bytes = bytes / 1024;
                index++;
        }

        return (index === 0 ? bytes.toFixed(0) : bytes.toFixed(1)) + ' ' + units[index];
}

function formatRate(value) {
        return formatBytes(value) + '/s';
}

function formatLatency(value) {
        var ms = Number(value || 0);
        if (!ms) {
                return '-';
        }
        return ms.toFixed(0) + ' ms';
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

function uninstallButton() {
        return E('button', {
                'class': 'btn cbi-button sdwan-action cbi-button-remove',
                'click': function(ev) {
                        ev.preventDefault();
                        if (!window.confirm(_('确定卸载 SD-WAN Verge 插件？会先关闭加速并恢复 DNS/路由。'))) {
                                return null;
                        }
                        return runCore('uninstall');
                }
        }, _('卸载插件'));
}

function runCore(action) {
        return fs.exec(corePath, [action]).then(function(response) {
                ui.addNotification(null, E('pre', {}, response.stdout || _('Command completed')), 'info');
                window.setTimeout(function() {
                        if (action === 'uninstall') {
                                window.location.href = '/cgi-bin/luci/admin/services';
                        } else {
                                window.location.reload();
                        }
                }, action === 'uninstall' ? 1200 : 600);
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

function renderSiteTests(sites) {
        if (!sites.length) {
                return E('div', { 'class': 'sdwan-empty' }, _('暂无检测结果'));
        }

        return E('div', { 'class': 'sdwan-site-list' }, sites.map(function(site) {
                var ok = !!site.ok;
                var title = site.name || site.url || '-';
                return E('div', { 'class': 'sdwan-site-row' }, [
                        E('div', { 'class': 'sdwan-site-main' }, [
                                E('strong', {}, title),
                                E('span', {}, site.url || '')
                        ]),
                        E('div', { 'class': ok ? 'sdwan-site-ok' : 'sdwan-site-bad' }, ok ? _('可用') : _('超时')),
                        E('div', { 'class': 'sdwan-site-latency' }, formatLatency(site.totalMs)),
                        E('div', { 'class': 'sdwan-muted' }, site.remoteIp || site.error || '')
                ]);
        }));
}

function renderDashboard(status, traffic, sites, logsResponse, formNode) {
        var active = !!status.active;
        var mode = status.mode || 'half_route';
        var routes = routeCount(status);
        var dnsServers = status.dnsServers || [];
        var tun = status.tun || {};
        var tunReady = !!(tun.device && tun.backendReady);
        var tunNotice = mode === 'tun'
                ? E('div', { 'class': tunReady ? 'sdwan-info' : 'sdwan-warning' }, tunReady
                        ? _('TUN 依赖已就绪，启动时会调用配置的真实 backend。')
                        : _('TUN 需要 kmod-tun 与真实 backend。依赖不完整时会拒绝启动，避免黑洞流量。'))
                : '';

        return E('div', { 'class': 'sdwan-page' }, [
                E('style', {}, [
                        '.sdwan-page{color:#1f2937}.sdwan-title-card{background:#fff;border-radius:4px;padding:18px 20px;margin-bottom:12px;box-shadow:0 1px 3px rgba(15,23,42,.08)}.sdwan-title-card h2{margin:0;font-size:24px}.sdwan-desc{padding:14px 18px;background:#f7f9fc;border:1px solid #dce5f2;border-radius:4px;color:#394867;margin-bottom:12px}.sdwan-blue-strip{height:38px;display:flex;align-items:center;justify-content:center;border-radius:6px;background:linear-gradient(90deg,#1d4ed8,#3b82f6);color:#fff;margin-bottom:12px}.sdwan-panel-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.sdwan-wide{grid-column:1/-1}.sdwan-card{background:#eef3f9;border:1px solid #d7e0ec;border-radius:6px;padding:14px;min-height:128px}.sdwan-card-title{font-weight:700;margin-bottom:12px}.sdwan-card-body{display:flex;flex-wrap:wrap;gap:10px}.sdwan-badge{display:inline-flex;align-items:center;border-radius:4px;padding:8px 12px;font-weight:700}.sdwan-badge-ok{color:#059669;background:#ecfdf5}.sdwan-badge-idle{color:#64748b;background:#fff}.sdwan-action{min-width:132px;height:42px;border-radius:5px}.sdwan-metric{background:#fff;border:1px solid #dce5f2;border-radius:6px;padding:12px;min-width:150px;flex:1}.sdwan-metric-title{color:#64748b}.sdwan-metric-value{font-size:18px;font-weight:800;margin-top:8px}.sdwan-metric-hint{font-size:12px;color:#7b8aa2;margin-top:6px}.sdwan-warning,.sdwan-info{width:100%;padding:10px 12px;border-radius:6px}.sdwan-warning{background:#fff7ed;border:1px solid #fed7aa;color:#b45309}.sdwan-info{background:#eff6ff;border:1px solid #bfdbfe;color:#1d4ed8}.sdwan-form-wrap{margin-top:12px}.sdwan-log-list{display:flex;flex-direction:column;gap:8px;width:100%}.sdwan-log-item{display:flex;gap:8px;align-items:flex-start;color:#42526b}.sdwan-log-dot{width:8px;height:8px;border-radius:99px;background:#2563eb;margin-top:6px;flex:none}.sdwan-site-list{display:flex;flex-direction:column;gap:8px;width:100%}.sdwan-site-row{display:grid;grid-template-columns:1fr 58px 82px 160px;gap:12px;align-items:center;background:#fff;border:1px solid #dce5f2;border-radius:6px;padding:10px 12px}.sdwan-site-main{display:flex;flex-direction:column;gap:2px}.sdwan-site-main span{color:#7b8aa2;font-size:12px}.sdwan-site-ok{color:#059669;font-weight:700}.sdwan-site-bad{color:#dc2626;font-weight:700}.sdwan-site-latency{font-weight:800}.sdwan-empty,.sdwan-muted{color:#7b8aa2}@media(max-width:900px){.sdwan-panel-grid{grid-template-columns:1fr}.sdwan-action{width:100%}.sdwan-site-row{grid-template-columns:1fr}.sdwan-wide{grid-column:auto}}'
                ]),
                E('div', { 'class': 'sdwan-title-card' }, [
                        E('h2', {}, 'SD-WAN Verge')
                ]),
                E('div', { 'class': 'sdwan-desc' }, _('在 OpenWrt/iStoreOS 上管理 CPE 旁路由加速。Half Route 使用系统路由交给 CPE；TUN 使用可配置真实 backend，插件负责依赖检查和状态展示。')),
                E('div', { 'class': 'sdwan-blue-strip' }, 'SD-WAN Verge Router Core'),
                E('div', { 'class': 'sdwan-panel-grid' }, [
                        panel(_('运行状态'), [
                                badge(active ? _('运行中') : _('未运行'), active),
                                metric(_('运行模式'), modeLabel(mode), status.activeMode ? _('当前: ') + modeLabel(status.activeMode) : _('等待启动')),
                                metric(_('CPE 网关'), textOrDash(status.gateway), active ? _('正在接管 IPv4') : _('等待启动')),
                                tunNotice
                        ]),
                        panel(_('控制面板'), [
                                metric(_('半路由'), routes + '/2', _('0.0.0.0/1 与 128.0.0.0/1')),
                                metric(_('TUN backend'), tun.backendReady ? _('已安装') : _('未安装'), tun.backend || '-'),
                                metric(_('TUN 设备'), tun.device ? _('可用') : _('缺少'), tun.interface || '-')
                        ]),
                        panel(_('快捷操作'), [
                                actionButton(_('开启加速'), 'start', 'cbi-button-apply'),
                                actionButton(_('关闭连接'), 'stop', 'cbi-button-reset'),
                                actionButton(_('重启服务'), 'restart', 'cbi-button-reload'),
                                actionButton(_('运行诊断'), 'doctor', 'cbi-button-action'),
                                actionButton(_('刷新检测'), 'sites', 'cbi-button-action'),
                                uninstallButton()
                        ]),
                        panel(_('流量检测'), [
                                metric(_('统计接口'), textOrDash(traffic.interface), _('仅统计加速出口')),
                                metric(_('上行速率'), formatRate(traffic.txRate), _('累计 ') + formatBytes(traffic.txBytes)),
                                metric(_('下行速率'), formatRate(traffic.rxRate), _('累计 ') + formatBytes(traffic.rxBytes)),
                                metric(_('DNS 同步'), status.syncDns ? _('启用') : _('停用'), dnsServers.join(', ') || '-')
                        ]),
                        E('div', { 'class': 'sdwan-wide' }, panel(_('常用网站检测'), [
                                renderSiteTests(sites)
                        ])),
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
                                return { stdout: '{}', stderr: error.message || String(error) };
                        }),
                        fs.exec(corePath, ['traffic']).catch(function(error) {
                                return { stdout: '{}', stderr: error.message || String(error) };
                        }),
                        fs.exec(corePath, ['sites']).catch(function(error) {
                                return { stdout: '[]', stderr: error.message || String(error) };
                        }),
                        fs.exec(corePath, ['logs']).catch(function(error) {
                                return { stdout: '', stderr: error.message || String(error) };
                        })
                ]);
        },

        render: function(data) {
                var status = parseStatus(data[1]);
                var traffic = parseTraffic(data[2]);
                var sites = parseSites(data[3]);
                var logsResponse = data[4];
                var map = new form.Map('sdwan_verge', '', '');
                var section = map.section(form.NamedSection, 'main', 'settings', _('插件设置'));
                section.anonymous = true;

                var mode = section.option(form.ListValue, 'mode', _('运行模式'));
                mode.default = 'half_route';
                mode.rmempty = false;
                mode.value('half_route', _('Half Route'));
                mode.value('tun', _('TUN'));
                mode.description = _('Half Route 当前稳定可用；TUN 模式会调用配置的真实 backend。');

                var enabled = section.option(form.Flag, 'enabled', _('开机启用'));
                enabled.default = '0';
                enabled.rmempty = false;

                var gateway = section.option(form.Value, 'cpe_gateway', _('CPE 网关'));
                gateway.datatype = 'ip4addr';
                gateway.placeholder = '192.168.1.140';
                gateway.rmempty = false;

                var tunInterface = section.option(form.Value, 'tun_interface', _('TUN 接口名'));
                tunInterface.placeholder = 'sdwan-tun0';
                tunInterface.rmempty = false;

                var tunBackend = section.option(form.Value, 'tun_backend', _('TUN backend 路径'));
                tunBackend.placeholder = '/usr/libexec/sdwan-verge/sdwan-verge-tun';
                tunBackend.rmempty = false;

                var syncDns = section.option(form.Flag, 'sync_dns', _('同步 dnsmasq DNS'));
                syncDns.default = '1';
                syncDns.rmempty = false;

                var dns = section.option(form.DynamicList, 'dns_server', _('DNS 服务器'));
                dns.datatype = 'ip4addr';
                dns.placeholder = '192.168.1.140';

                var testSite = section.option(form.DynamicList, 'test_site', _('常用网站检测'));
                testSite.placeholder = 'Claude|https://claude.ai/';
                testSite.description = _('格式: 名称|URL，例如 Amazon|https://www.amazon.com/');

                return map.render().then(function(formNode) {
                        return renderDashboard(status, traffic, sites, logsResponse, formNode);
                });
        }
});
