import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('macOS status item exposes restore toggle acceleration and quit', () {
    final appDelegate = read('macos/Runner/AppDelegate.swift');

    expect(appDelegate, contains('toggleAccelerationFromStatusMenu'));
    expect(appDelegate, contains('statusToggleItem'));
    expect(appDelegate, contains('显示主窗口'));
    expect(appDelegate, contains('关闭加速'));
    expect(appDelegate, contains('退出'));
  });

  test('macOS status item uses different icons for running and stopped', () {
    final appDelegate = read('macos/Runner/AppDelegate.swift');

    expect(appDelegate, contains('updateStatusItemAppearance'));
    expect(appDelegate, contains('bolt.circle.fill'));
    expect(appDelegate, contains('bolt.circle'));
  });

  test('macOS stops acceleration before quitting the app', () {
    final appDelegate = read('macos/Runner/AppDelegate.swift');

    expect(appDelegate, contains('applicationShouldTerminate'));
    expect(appDelegate, contains('stopAccelerationBeforeExit'));
    expect(appDelegate, contains('runInstalledHelper'));
    expect(appDelegate, contains('stopHelper(statusMenuArguments())'));
    expect(appDelegate, contains('stopAccelerationBeforeExit()'));
    expect(appDelegate, contains('NSApp.terminate(nil)'));
  });

  test('macOS runner starts and stops a real OpenVPN process', () {
    final appDelegate = read('macos/Runner/AppDelegate.swift');

    expect(appDelegate, contains('mode(from: arguments) == "openvpn"'));
    expect(appDelegate, contains('private func startOpenVpn(arguments:'));
    expect(appDelegate, contains('private func stopOpenVpn(arguments:'));
    expect(appDelegate, contains('private func openVpnConfigText('));
    expect(appDelegate, contains('lines.append("client")'));
    expect(appDelegate, contains('isIgnoredOpenVpnDirectiveOnDarwin'));
    expect(appDelegate, contains('openVpnConfigQuote'));
    expect(appDelegate, contains('openvpnInlineBlocks'));
    expect(appDelegate, contains('findOpenVpnBinary()'));
    expect(appDelegate, contains('--writepid'));
    expect(appDelegate, contains('--config'));
    expect(appDelegate, contains('"openvpnRemoteHost"'));
    expect(appDelegate, contains('"OpenVPN"'));
    expect(appDelegate, isNot(contains('openVpnUnsupportedStatus')));
  });

  test('macOS runner can install OpenVPN from inside the app', () {
    final appDelegate = read('macos/Runner/AppDelegate.swift');

    expect(appDelegate, contains('private func installOpenVpnRuntime('));
    expect(appDelegate, contains('install openvpn'));
    expect(appDelegate, contains('findHomebrewBinary()'));
    expect(appDelegate, contains('"permission": "needsHelperInstall"'));
    expect(appDelegate, contains('请先安装 Homebrew'));
  });

  test('macOS package script reseals app after embedding helper', () {
    final script = read('scripts/package_releases.sh');

    final copyHelper = script.indexOf(
      r'cp "$helper_path" "$app_path/Contents/Resources/sdwan-macos-helper"',
    );
    final signHelper = script.indexOf(
      r'codesign --force --sign - "$app_path/Contents/Resources/sdwan-macos-helper"',
    );
    final signApp = script.indexOf(
      r'codesign --force --deep --sign - "$app_path"',
    );
    final verifyApp = script.indexOf(
      r'codesign --verify --deep --strict "$app_path"',
    );
    final createDmg = script.indexOf('hdiutil create');

    expect(copyHelper, isNonNegative);
    expect(signHelper, greaterThan(copyHelper));
    expect(signApp, greaterThan(signHelper));
    expect(verifyApp, greaterThan(signApp));
    expect(createDmg, greaterThan(verifyApp));
  });
}
