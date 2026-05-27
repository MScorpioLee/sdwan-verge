import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/command_runner.dart';
import 'package:sdwan_client/platform/windows/windows_network_gateway.dart';

class FakeCommandRunner implements CommandRunner {
  final calls = <String>[];
  final Map<String, CommandResult> responses = {};

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final key = [executable, ...arguments].join(' ');
    calls.add(key);
    return responses[key] ??
        const CommandResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('enable acceleration runs route commands and flushes DNS', () async {
    final runner = FakeCommandRunner();
    final gateway = WindowsNetworkGateway(runner: runner);

    final result = await gateway.enableAcceleration(SdwanProfile.defaults());

    expect(result.success, isTrue);
    expect(runner.calls, [
      'route add 0.0.0.0/1 192.168.1.140 -p',
      'route add 128.0.0.0/1 192.168.1.140 -p',
      'ipconfig /flushdns',
    ]);
  });

  test('stops command sequence on failure', () async {
    final runner = FakeCommandRunner();
    runner.responses['route add 0.0.0.0/1 192.168.1.140 -p'] =
        const CommandResult(exitCode: 1, stdout: '', stderr: 'failed');
    final gateway = WindowsNetworkGateway(runner: runner);

    final result = await gateway.enableAcceleration(SdwanProfile.defaults());

    expect(result.success, isFalse);
    expect(result.command, 'route add 0.0.0.0/1 192.168.1.140 -p');
    expect(runner.calls, ['route add 0.0.0.0/1 192.168.1.140 -p']);
  });

  test('readStatus combines route, interface, and DNS output', () async {
    final runner = FakeCommandRunner();
    runner.responses['net session'] =
        const CommandResult(exitCode: 0, stdout: '', stderr: '');
    runner.responses['route print -4'] = const CommandResult(
      exitCode: 0,
      stderr: '',
      stdout: '''
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0    192.168.1.1   192.168.1.88     25
          0.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
        128.0.0.0        128.0.0.0  192.168.1.140   192.168.1.88     26
''',
    );
    runner.responses['netsh interface ip show config'] = const CommandResult(
      exitCode: 0,
      stderr: '',
      stdout: '''
Configuration for interface "Ethernet"
    IP Address:                           192.168.1.88
''',
    );
    runner.responses['netsh interface ip show dnsservers Ethernet'] =
        const CommandResult(
      exitCode: 0,
      stderr: '',
      stdout: '''
Configuration for interface "Ethernet"
    Statically Configured DNS Servers:    223.5.5.5
                                           114.114.114.114
''',
    );
    final gateway = WindowsNetworkGateway(runner: runner);

    final status = await gateway.readStatus(SdwanProfile.defaults());

    expect(status.platformName, 'Windows');
    expect(status.capability, PlatformCapability.full);
    expect(status.isAdmin, isTrue);
    expect(status.accelerationEnabled, isTrue);
    expect(status.activeInterfaceName, 'Ethernet');
    expect(status.activeInterfaceIp, '192.168.1.88');
    expect(status.dnsMode, DnsMode.static);
    expect(status.dnsServers, ['223.5.5.5', '114.114.114.114']);
  });

  test('ensureAdminOrRelaunch starts elevated copy and exits current process',
      () async {
    final runner = FakeCommandRunner();
    runner.responses['net session'] =
        const CommandResult(exitCode: 1, stdout: '', stderr: 'access denied');
    var exitCode = -1;
    final gateway = WindowsNetworkGateway(
      runner: runner,
      executablePath: 'C:\\app\\sdwan.exe',
      exitProcess: (code) => exitCode = code,
    );

    final result = await gateway.ensureAdminOrRelaunch();

    expect(result.success, isTrue);
    expect(exitCode, 0);
    expect(runner.calls, [
      'net session',
      'powershell -NoProfile -ExecutionPolicy Bypass -Command Start-Process -FilePath "C:\\app\\sdwan.exe" -Verb RunAs',
    ]);
  });
}
