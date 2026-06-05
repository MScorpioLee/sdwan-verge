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

  test('Linux runner uses one app instance and reuses the existing window', () {
    final runner = read('linux/runner/my_application.cc');

    expect(runner, isNot(contains('G_APPLICATION_NON_UNIQUE')));
    expect(runner, contains('g_application_get_is_remote'));
    expect(runner, contains('if (self->window != nullptr)'));
    expect(runner, contains('show_main_window(self);'));
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

  test('Linux runner exposes half-route backend commands', () {
    final runner = read('linux/runner/my_application.cc');

    expect(runner, contains('Linux Half Route'));
    expect(runner, contains('ip route replace 0.0.0.0/1 via'));
    expect(runner, contains('ip route replace 128.0.0.0/1 via'));
    expect(runner, contains('ip route del 0.0.0.0/1'));
    expect(runner, contains('/proc/net/dev'));
    expect(runner, contains('ss -tunp -4'));
    expect(runner, contains('is_public_ipv4_endpoint'));
  });

  test('Linux runner has a shutdown hook to stop acceleration before exit', () {
    final runner = read('linux/runner/my_application.cc');

    expect(runner, contains('stop_acceleration_before_exit'));
    expect(runner, contains('my_application_shutdown'));
    expect(runner, contains('tray_quit_cb'));
  });
}
