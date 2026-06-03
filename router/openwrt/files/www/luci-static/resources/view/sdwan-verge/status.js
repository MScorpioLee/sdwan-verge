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
                        gateway: '',
                        syncDns: false,
                        routes: {
                                lower: false,
                                upper: false
                        },
                        dnsServers: [],
                        error: String(error)
                };
        }
}

function formatStatus(status) {
        var routeText = [
                '0.0.0.0/1: ' + (status.routes && status.routes.lower ? _('present') : _('missing')),
                '128.0.0.0/1: ' + (status.routes && status.routes.upper ? _('present') : _('missing'))
        ].join('\n');

        return [
                _('Active') + ': ' + (status.active ? _('yes') : _('no')),
                _('Enabled') + ': ' + (status.enabled ? _('yes') : _('no')),
                _('CPE gateway') + ': ' + (status.gateway || '-'),
                _('DNS sync') + ': ' + (status.syncDns ? _('enabled') : _('disabled')),
                _('Routes') + ':\n' + routeText,
                _('DNS') + ': ' + ((status.dnsServers || []).join(', ') || '-')
        ].join('\n');
}

function runCore(action) {
        return fs.exec(corePath, [action]).then(function(response) {
                ui.addNotification(null, E('pre', {}, response.stdout || _('Command completed')), 'info');
        }).catch(function(error) {
                ui.addNotification(null, E('pre', {}, error.message || String(error)), 'danger');
        });
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
                        })
                ]);
        },

        render: function(data) {
                var status = parseStatus(data[1]);
                var map = new form.Map(
                        'sdwan_verge',
                        _('SD-WAN Verge'),
                        _('Apply BAT-derived SD-WAN routes and optional dnsmasq DNS on this OpenWrt/iStoreOS router.')
                );
                var section = map.section(form.NamedSection, 'main', 'settings', _('Router Core'));
                section.anonymous = true;

                var current = section.option(form.DummyValue, '_status', _('Current status'));
                current.rawhtml = false;
                current.cfgvalue = function() {
                        return formatStatus(status);
                };

                var enabled = section.option(form.Flag, 'enabled', _('Enable after reboot'));
                enabled.default = '0';
                enabled.rmempty = false;

                var gateway = section.option(form.Value, 'cpe_gateway', _('CPE gateway'));
                gateway.datatype = 'ip4addr';
                gateway.placeholder = '192.168.1.140';
                gateway.rmempty = false;

                var syncDns = section.option(form.Flag, 'sync_dns', _('Sync dnsmasq DNS'));
                syncDns.default = '1';
                syncDns.rmempty = false;

                var dns = section.option(form.DynamicList, 'dns_server', _('DNS servers'));
                dns.datatype = 'ip4addr';
                dns.placeholder = '223.5.5.5';

                var start = section.option(form.Button, '_start', _('Start'));
                start.inputstyle = 'apply';
                start.onclick = function() {
                        return runCore('start');
                };

                var stop = section.option(form.Button, '_stop', _('Stop'));
                stop.inputstyle = 'reset';
                stop.onclick = function() {
                        return runCore('stop');
                };

                var restart = section.option(form.Button, '_restart', _('Restart'));
                restart.inputstyle = 'reload';
                restart.onclick = function() {
                        return runCore('restart');
                };

                var doctor = section.option(form.Button, '_doctor', _('Doctor'));
                doctor.inputstyle = 'find';
                doctor.onclick = function() {
                        return runCore('doctor');
                };

                var logs = section.option(form.Button, '_logs', _('Logs'));
                logs.inputstyle = 'action';
                logs.onclick = function() {
                        return runCore('logs');
                };

                return map.render();
        }
});
