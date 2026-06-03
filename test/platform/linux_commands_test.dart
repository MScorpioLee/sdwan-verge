import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/linux/linux_commands.dart';

void main() {
  test('builds pkexec route commands and resolver flush command', () {
    final commands = LinuxCommands.enableAcceleration(SdwanProfile.defaults());

    expect(commands.map((command) => command.display), [
      'pkexec sh -c ip route replace 0.0.0.0/1 via 192.168.1.140',
      'pkexec sh -c ip route replace 128.0.0.0/1 via 192.168.1.140',
      'resolvectl flush-caches',
    ]);
  });

  test('builds resolvectl dns commands', () {
    final setCommands = LinuxCommands.setDns('eth0', SdwanProfile.defaults());
    final restoreCommands = LinuxCommands.restoreDns('eth0');

    expect(setCommands.map((command) => command.display), [
      'pkexec resolvectl dns eth0 223.5.5.5 114.114.114.114',
      'resolvectl flush-caches',
    ]);
    expect(restoreCommands.map((command) => command.display), [
      'pkexec resolvectl revert eth0',
      'resolvectl flush-caches',
    ]);
  });
}
