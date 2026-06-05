import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Linux runner hides the window to tray on close', () {
    final runner = read('linux/runner/my_application.cc');

    expect(runner, contains('delete-event'));
    expect(runner, contains('gtk_widget_hide'));
    expect(runner, contains('return TRUE'));
  });

  test('Linux tray exposes restore toggle acceleration and quit', () {
    final runner = read('linux/runner/my_application.cc');

    expect(runner, contains('gtk_status_icon_new'));
    expect(runner, contains('GTK_STATUS_ICON'));
    expect(runner, contains('tray_toggle_item'));
    expect(runner, contains('关闭加速'));
    expect(runner, contains('退出'));
  });

  test('Linux tray switches icon by acceleration state', () {
    final runner = read('linux/runner/my_application.cc');

    expect(runner, contains('tray-active.png'));
    expect(runner, contains('tray-idle.png'));
    expect(File('linux/runner/resources/tray-active.png').existsSync(), isTrue);
    expect(File('linux/runner/resources/tray-idle.png').existsSync(), isTrue);
  });
}
