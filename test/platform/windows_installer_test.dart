import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readInstaller() =>
      File('windows/installer/sdwan-verge.iss').readAsStringSync();

  test(
    'Windows installer cleans running helper and driver before replacing files',
    () {
      final installer = readInstaller();

      expect(installer, contains('function PrepareToInstall'));
      expect(installer, contains("KillProcess('sdwan_client.exe')"));
      expect(installer, contains("RunExistingHelper('stop')"));
      expect(installer, contains("RunExistingHelper('uninstall')"));
      expect(installer, contains("StopService('SDWANVergeHelper')"));
      expect(installer, contains("StopService('WinDivert')"));
      expect(installer, contains("StopService('WinDivert64')"));
    },
  );

  test('Windows installer can defer locked file replacement to reboot', () {
    final installer = readInstaller();

    expect(installer, contains('restartreplace'));
    expect(installer, contains('CloseApplications=yes'));
    expect(installer, contains('RestartApplications=no'));
  });
}
