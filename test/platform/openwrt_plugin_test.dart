import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  String read(String relativePath) =>
      File('${root.path}/$relativePath').readAsStringSync();

  test('LuCI plugin page uses an iStoreOS control-panel layout', () {
    final view = read(
      'router/openwrt/files/www/luci-static/resources/view/sdwan-verge/dashboard.js',
    );
    final menu = read(
      'router/openwrt/files/usr/share/luci/menu.d/luci-app-sdwan-verge.json',
    );

    expect(view, contains('sdwan-panel-grid'));
    expect(view, contains('运行状态'));
    expect(view, contains('控制面板'));
    expect(view, contains('快捷操作'));
    expect(view, contains('流量检测'));
    expect(view, contains('常用网站检测'));
    expect(view, contains('运行日志'));
    expect(view, contains('运行模式'));
    expect(view, contains('Half Route'));
    expect(view, contains('TUN'));
    expect(view, contains('TUN 模式'));
    expect(view, contains('formatRate'));
    expect(view, contains('formatLatency'));
    expect(view, contains('Claude'));
    expect(view, contains('Amazon'));
    expect(view, contains('卸载插件'));
    expect(view, contains("runCore('uninstall')"));
    expect(view, contains("actionButton(_('开启加速'), 'start'"));
    expect(view, contains("actionButton(_('关闭连接'), 'stop'"));
    expect(view, contains('map.render().then'));
    expect(view, isNot(contains('sdwan-oc-tabs')));
    expect(view, isNot(contains('覆写设置')));
    expect(view, isNot(contains('一键生成')));
    expect(view, isNot(contains('配置订阅')));
    expect(menu, contains('sdwan-verge/dashboard'));
    expect(menu, isNot(contains('sdwan-verge/status')));
  });

  test('OpenWrt plugin can be packaged as an all-arch ipk in CI', () {
    final script = read('scripts/package_openwrt_ipk.sh');
    final workflow = read('.github/workflows/release.yml');

    expect(script, contains('luci-app-sdwan-verge'));
    expect(script, contains('Architecture: all'));
    expect(script, contains('control.tar.gz'));
    expect(script, contains('data.tar.gz'));
    expect(script, contains('debian-binary'));
    expect(script, contains('outer_members = ["debian-binary", "data.tar.gz", "control.tar.gz"]'));
    expect(script, contains('tarfile.USTAR_FORMAT'));
    expect(script, contains('postinst'));
    expect(script, contains('postrm'));
    expect(script, contains('/tmp/luci-indexcache*'));
    expect(script, isNot(contains('!<arch>')));
    expect(script, isNot(contains('/etc/init.d/rpcd restart')));

    expect(workflow, contains('- openwrt'));
    expect(workflow, contains('name: sdwan-verge-openwrt'));
    expect(workflow, contains('bash scripts/package_openwrt_ipk.sh'));
    expect(workflow, contains('luci-app-sdwan-verge_*.ipk'));
  });

  test('router core exposes TUN checks, traffic stats, and site tests', () {
    final config = read('router/openwrt/files/etc/config/sdwan_verge');
    final core = read(
      'router/openwrt/files/usr/libexec/sdwan-verge/sdwan-verge-core',
    );
    final makefile = read('router/openwrt/Makefile');
    final readme = read('router/openwrt/README.md');

    expect(config, contains("option mode 'half_route'"));
    expect(config, contains("option tun_interface 'sdwan-tun0'"));
    expect(config, contains("option tun_backend '/usr/libexec/sdwan-verge/sdwan-verge-tun'"));
    expect(config, contains("list test_site 'Google|https://www.google.com/generate_204'"));
    expect(config, contains("list test_site 'Claude|https://claude.ai/'"));
    expect(config, contains("list test_site 'Amazon|https://www.amazon.com/'"));
    expect(core, contains('MODE=half_route'));
    expect(core, contains('config_get MODE'));
    expect(core, contains('config_get TUN_INTERFACE'));
    expect(core, contains('config_get TUN_BACKEND'));
    expect(core, contains('start_half_route'));
    expect(core, contains('start_tun'));
    expect(core, contains('tun_available'));
    expect(core, contains('traffic_json'));
    expect(core, contains('sites_json'));
    expect(core, contains('curl -4'));
    expect(core, contains('COMMANDS:'));
    expect(core, contains('opkg remove luci-app-sdwan-verge'));
    expect(core, isNot(contains('TUN mode is not wired yet')));
    expect(makefile, contains('+curl'));
    expect(readme, contains('常用网站检测'));
    expect(readme, contains('真实 TUN backend'));
  });
}
