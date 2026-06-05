import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Windows close button keeps app alive for tray restore', () {
    final mainCpp = read('windows/runner/main.cpp');

    expect(mainCpp, contains('window.SetQuitOnClose(false);'));
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
}
