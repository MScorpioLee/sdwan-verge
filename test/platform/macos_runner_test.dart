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
}
