import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/command_runner.dart';
import 'package:sdwan_client/platform/linux/linux_network_gateway.dart';

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
  test('readStatus combines route, interface, source ip, and DNS output', () async {
    final runner = FakeCommandRunner();
    runner.responses['id -u'] = const CommandResult(
      exitCode: 0,
      stdout: '1000\n',
      stderr: '',
    );
    runner.responses['ip route show'] = const CommandResult(
      exitCode: 0,
      stdout: '''
default via 192.168.1.1 dev eth0 proto dhcp
0.0.0.0/1 via 192.168.1.140 dev eth0
128.0.0.0/1 via 192.168.1.140 dev eth0
''',
      stderr: '',
    );
    runner.responses['ip route get 1.1.1.1'] = const CommandResult(
      exitCode: 0,
      stdout: '1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.88 uid 1000\n',
      stderr: '',
    );
    runner.responses['resolvectl dns'] = const CommandResult(
      exitCode: 0,
      stdout: '''
Global:
Link 2 (eth0)
         DNS Servers: 223.5.5.5 114.114.114.114
''',
      stderr: '',
    );

    final status = await LinuxNetworkGateway(
      runner: runner,
    ).readStatus(SdwanProfile.defaults());

    expect(status.platformName, 'Linux');
    expect(status.capability, PlatformCapability.full);
    expect(status.isAdmin, isFalse);
    expect(status.accelerationEnabled, isTrue);
    expect(status.activeInterfaceName, 'eth0');
    expect(status.activeInterfaceIp, '192.168.1.88');
    expect(status.dnsMode, DnsMode.static);
    expect(status.dnsServers, ['223.5.5.5', '114.114.114.114']);
  });
}
