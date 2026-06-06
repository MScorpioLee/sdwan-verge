import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  String read(String relativePath) =>
      File('${root.path}/$relativePath').readAsStringSync();

  test('LuCI plugin page uses an iStoreOS control-panel layout', () {
    final view = read(
      'router/openwrt/files/www/luci-static/resources/view/sdwan-verge/status.js',
    );

    expect(view, contains('sdwan-oc-tabs'));
    expect(view, contains('sdwan-panel-grid'));
    expect(view, contains('运行状态'));
    expect(view, contains('控制面板'));
    expect(view, contains('快捷操作'));
    expect(view, contains('实时统计'));
    expect(view, contains('运行日志'));
    expect(view, contains('运行模式'));
    expect(view, contains('Half Route'));
    expect(view, contains('TUN'));
    expect(view, contains('TUN 模式'));
    expect(view, contains("actionButton(_('开启加速'), 'start'"));
    expect(view, contains("actionButton(_('关闭连接'), 'stop'"));
    expect(view, contains('map.render().then'));
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

  test('router core exposes mode selection without fake TUN startup', () {
    final config = read('router/openwrt/files/etc/config/sdwan_verge');
    final core = read(
      'router/openwrt/files/usr/libexec/sdwan-verge/sdwan-verge-core',
    );

    expect(config, contains("option mode 'half_route'"));
    expect(core, contains('MODE=half_route'));
    expect(core, contains('config_get MODE'));
    expect(core, contains('start_half_route'));
    expect(core, contains('start_tun'));
    expect(core, contains('TUN mode is not wired yet'));
  });
}
