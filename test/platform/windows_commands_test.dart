import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/windows/windows_commands.dart';

void main() {
  final profile = SdwanProfile.defaults();

  test('builds route add commands from profile CPE', () {
    final commands = WindowsCommands.enableAcceleration(profile);

    expect(commands, [
      const WindowsCommand('route', [
        'add',
        '0.0.0.0/1',
        '192.168.1.140',
        '-p',
      ]),
      const WindowsCommand('route', [
        'add',
        '128.0.0.0/1',
        '192.168.1.140',
        '-p',
      ]),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('builds route delete commands', () {
    final commands = WindowsCommands.disableAcceleration();

    expect(commands, [
      const WindowsCommand('route', ['delete', '0.0.0.0/1']),
      const WindowsCommand('route', ['delete', '128.0.0.0/1']),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('builds static DNS commands', () {
    final commands = WindowsCommands.setDns('Ethernet', profile);

    expect(commands, [
      const WindowsCommand('netsh', [
        'interface',
        'ip',
        'set',
        'dnsserver',
        'Ethernet',
        'static',
        '223.5.5.5',
        'primary',
      ]),
      const WindowsCommand('netsh', [
        'interface',
        'ip',
        'add',
        'dnsserver',
        'Ethernet',
        '114.114.114.114',
        'index=2',
      ]),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('builds restore DNS command', () {
    expect(WindowsCommands.restoreDns('Ethernet'), [
      const WindowsCommand('netsh', [
        'interface',
        'ip',
        'set',
        'dnsserver',
        'Ethernet',
        'dhcp',
      ]),
      const WindowsCommand('ipconfig', ['/flushdns']),
    ]);
  });

  test('formats command for logs', () {
    const command = WindowsCommand('route', ['delete', '0.0.0.0/1']);

    expect(command.display, 'route delete 0.0.0.0/1');
  });
}
