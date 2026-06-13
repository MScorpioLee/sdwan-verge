import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readInstaller() =>
      File('windows/installer/sdwan-verge.iss').readAsStringSync();
  String read(String path) => File(path).readAsStringSync();

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

  test('Windows build prepares bundled OpenVPN before packaging', () {
    final script = read('scripts/prepare_windows_openvpn_runtime.ps1');
    final quickWorkflow = read('.github/workflows/windows-quick-build.yml');
    final releaseWorkflow = read('.github/workflows/release.yml');

    expect(script, contains('"2.7.4-I001"'));
    expect(script, contains('SDWAN_OPENVPN_MSI_PATH'));
    expect(script, contains('SecurityProtocolType]::Tls12'));
    expect(script, contains(r'OpenVPN-$Version-amd64.msi'));
    expect(script, contains('windows\\third_party\\openvpn\\windows-x64'));
    expect(script, contains('msiexec.exe'));
    expect(script, contains('bin\\openvpn.exe'));
    expect(script, contains(r'installer\OpenVPN-$Version-amd64.msi'));
    expect(quickWorkflow, contains('prepare_windows_openvpn_runtime.ps1'));
    expect(releaseWorkflow, contains('prepare_windows_openvpn_runtime.ps1'));
    expect(quickWorkflow, contains('ExecutionPolicy Bypass'));
    expect(releaseWorkflow, contains('ExecutionPolicy Bypass'));
    expect(quickWorkflow, contains("'scripts/prepare_windows_openvpn_runtime.ps1'"));
    expect(
      quickWorkflow.indexOf('prepare_windows_openvpn_runtime.ps1'),
      lessThan(quickWorkflow.indexOf('flutter build windows --release')),
    );
    expect(
      releaseWorkflow.indexOf('prepare_windows_openvpn_runtime.ps1'),
      lessThan(releaseWorkflow.indexOf('flutter build windows --release')),
    );
  });
}
