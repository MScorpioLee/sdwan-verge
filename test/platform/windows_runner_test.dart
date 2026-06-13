import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Windows close button keeps app alive for tray restore', () {
    final mainCpp = read('windows/runner/main.cpp');

    expect(mainCpp, contains('window.SetQuitOnClose(false);'));
  });

  test('Windows runner restores the existing instance on second launch', () {
    final mainCpp = read('windows/runner/main.cpp');
    final win32Window = read('windows/runner/win32_window.cpp');

    expect(mainCpp, contains('kSingleInstanceMutexName'));
    expect(mainCpp, contains('CreateMutexW'));
    expect(mainCpp, contains('ERROR_ALREADY_EXISTS'));
    expect(
      mainCpp,
      contains('PostMessage(HWND_BROADCAST, ShowMainWindowMessage(), 0, 0)'),
    );
    expect(win32Window, contains('ShowMainWindowMessage'));
    expect(win32Window, contains('RestoreFromTray();'));
  });

  test('Windows runner explicitly applies app icons to the window', () {
    final win32Window = read('windows/runner/win32_window.cpp');

    expect(win32Window, contains('WM_SETICON'));
    expect(win32Window, contains('ICON_SMALL'));
    expect(win32Window, contains('ICON_BIG'));
  });

  test('Windows runner provides tray hide, restore, and exit actions', () {
    final win32Window = read('windows/runner/win32_window.cpp');

    expect(win32Window, contains('Shell_NotifyIcon'));
    expect(win32Window, contains('NIM_ADD'));
    expect(win32Window, contains('NIM_DELETE'));
    expect(win32Window, contains('WM_CLOSE'));
    expect(win32Window, contains('TrackPopupMenu'));
    expect(win32Window, contains('kTrayMenuToggleAcceleration'));
    expect(win32Window, contains('关闭加速'));
    expect(win32Window, contains('退出'));
  });

  test('Windows tray switches icon by acceleration state', () {
    final resourceHeader = read('windows/runner/resource.h');
    final resources = read('windows/runner/Runner.rc');
    final win32Window = read('windows/runner/win32_window.cpp');

    expect(resourceHeader, contains('IDI_TRAY_ACTIVE'));
    expect(resourceHeader, contains('IDI_TRAY_IDLE'));
    expect(resources, contains('resources\\\\tray_active.ico'));
    expect(resources, contains('resources\\\\tray_idle.ico'));
    expect(win32Window, contains('TrayIconResource'));
  });

  test('Windows runner compiles UTF-8 tray labels correctly', () {
    final cmake = read('windows/runner/CMakeLists.txt');

    expect(cmake, contains('/utf-8'));
  });

  test('Windows runner includes file streams for OpenVPN pid reads', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('#include <fstream>'));
    expect(flutterWindow, contains('std::ifstream file(OpenVpnPidPath())'));
  });

  test('Windows OpenVPN config paths use forward slashes', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(
      flutterWindow,
      contains(r"std::replace(value.begin(), value.end(), '\\', '/')"),
    );
    expect(flutterWindow, contains('OpenVpnConfigQuote(WideToUtf8'));
  });

  test('Windows runner can prefer bundled OpenVPN runtime', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('BundledOpenVpnPath'));
    expect(
      flutterWindow,
      contains(r'RunnerDir() + L"\\openvpn\\bin\\openvpn.exe"'),
    );
    expect(
      flutterWindow.indexOf('BundledOpenVpnPath()'),
      lessThan(flutterWindow.indexOf('CSIDL_PROGRAM_FILES')),
    );
  });

  test('Windows runner can install bundled OpenVPN TUN dependencies', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('FindBundledOpenVpnInstaller'));
    expect(flutterWindow, contains('OpenVPN-*.msi'));
    expect(flutterWindow, contains('OpenVpnDriverReady'));
    expect(flutterWindow, contains('OpenVpnDependenciesReady'));
    expect(flutterWindow, contains('InstallOpenVpnDependencies'));
    expect(flutterWindow, contains('msiexec.exe'));
    expect(flutterWindow, contains('/i'));
    expect(flutterWindow, contains('/qn'));
    expect(flutterWindow, contains('OpenVPN TUN 驱动未安装'));
    expect(
      flutterWindow.indexOf('InstallOpenVpnDependencies'),
      lessThan(flutterWindow.indexOf('RunHelperElevated(L"install")')),
    );
  });

  test('Windows CMake installs bundled OpenVPN runtime when present', () {
    final cmake = read('windows/CMakeLists.txt');

    expect(cmake, contains('BUNDLED_OPENVPN_DIR'));
    expect(
      cmake,
      contains('windows-x64'),
    );
    expect(cmake, contains('bin/openvpn.exe'));
    expect(
      cmake,
      contains(r'DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/openvpn"'),
    );
  });

  test('Windows OpenVPN config ignores unsupported runtime directives', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('key == "proto"'));
    expect(flutterWindow, contains('key == "block-outside-dns"'));
    expect(flutterWindow, contains('key == "pull-filter"'));
    expect(flutterWindow, contains('key == "route-nopull"'));
    expect(
      flutterWindow,
      contains('The Windows test machine has OpenVPN 2.3.x'),
    );
    expect(flutterWindow, contains('config << "route-nopull\\n";'));
  });

  test('Windows OpenVPN runtime protocol is compatible with OpenVPN 2.3', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('OpenVpnRuntimeProtocol'));
    expect(flutterWindow, contains('protocol == "udp4"'));
    expect(flutterWindow, contains('return "udp"'));
    expect(
      flutterWindow,
      contains('config << "proto " << OpenVpnRuntimeProtocol'),
    );
    expect(
      flutterWindow,
      isNot(contains('config << "proto " << StringArg(args, "openvpnProtocol"')),
    );
  });

  test('Windows OpenVPN status exposes config and log errors', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('OpenVpnConfigHasTlsTrust'));
    expect(flutterWindow, contains('OpenVPN 配置缺少服务端 CA'));
    expect(flutterWindow, contains('不需要客户端证书'));
    expect(flutterWindow, contains('OpenVpnLastError'));
    expect(flutterWindow, contains('Options error:'));
  });

  test('Windows OpenVPN status parses tunnel traffic counters', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('OpenVpnTrafficStats'));
    expect(flutterWindow, contains('TUN/TAP read bytes'));
    expect(flutterWindow, contains('TUN/TAP write bytes'));
    expect(flutterWindow, contains('g_openvpn_last_tx_bytes'));
    expect(flutterWindow, contains('txRate'));
    expect(flutterWindow, contains('rxRate'));
  });

  test('Windows OpenVPN connections read netstat instead of returning empty', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('OpenVpnConnections'));
    expect(flutterWindow, contains('netstat -ano -p tcp'));
    expect(flutterWindow, contains('netstat -ano -p udp'));
    expect(flutterWindow, contains('DnsCacheDomainsByIp'));
    expect(
      flutterWindow,
      isNot(
        contains('result->Success(flutter::EncodableValue(flutter::EncodableList{}));'),
      ),
    );
  });

  test('Windows OpenVPN connection diagnostics are cached', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('kOpenVpnConnectionsCacheMs'));
    expect(flutterWindow, contains('g_openvpn_cached_connections_text'));
    expect(flutterWindow, contains('g_openvpn_connections_cache_tick'));
  });

  test('Windows connection diagnostics do not flash console windows', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');
    final runCommandCapture = flutterWindow.substring(
      flutterWindow.indexOf('std::string RunCommandCapture'),
      flutterWindow.indexOf('bool RunHelperElevated'),
    );

    expect(runCommandCapture, contains('CREATE_NO_WINDOW'));
    expect(runCommandCapture, isNot(contains('_popen')));
  });

  test(
    'Windows runner stops acceleration before tray exit and destroy fallback',
    () {
      final win32Window = read('windows/runner/win32_window.cpp');
      final flutterWindow = read('windows/runner/flutter_window.cpp');

      expect(win32Window, contains('RunExitHandler'));
      expect(win32Window, contains('tray_exit_handler_'));
      expect(flutterWindow, contains('StopAccelerationBeforeExit'));
      expect(
        flutterWindow,
        contains('RunHelper(HelperArgs(L"stop", g_last_cpe_host))'),
      );
    },
  );

  test('Windows runner starts and stops a real OpenVPN process', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');

    expect(flutterWindow, contains('ModeFromArgs'));
    expect(flutterWindow, contains('StartOpenVpn'));
    expect(flutterWindow, contains('StopOpenVpn'));
    expect(flutterWindow, contains('OpenVpnConfigText'));
    expect(flutterWindow, contains('config << "client\\n"'));
    expect(flutterWindow, contains('OpenVpnConfigQuote'));
    expect(flutterWindow, contains('FindOpenVpnBinary'));
    expect(flutterWindow, contains('openvpnInlineBlocks'));
    expect(flutterWindow, contains('--writepid'));
    expect(flutterWindow, contains('--config'));
    expect(
      flutterWindow.indexOf('--log'),
      lessThan(flutterWindow.indexOf('--config')),
    );
    expect(flutterWindow, contains('"openvpnRemoteHost"'));
    expect(flutterWindow, contains('"OpenVPN"'));
    expect(flutterWindow, isNot(contains('OpenVpnUnsupportedStatus')));
  });

  test('Windows OpenVPN start reuses a running process', () {
    final flutterWindow = read('windows/runner/flutter_window.cpp');
    final startOpenVpn = flutterWindow.substring(
      flutterWindow.indexOf('flutter::EncodableValue StartOpenVpn'),
      flutterWindow.indexOf('flutter::EncodableValue StopOpenVpn'),
    );

    expect(startOpenVpn, contains('OpenVpnPidRunning()'));
    expect(
      startOpenVpn.indexOf('OpenVpnPidRunning()'),
      lessThan(startOpenVpn.indexOf('StartOpenVpnElevated')),
    );
  });
}
