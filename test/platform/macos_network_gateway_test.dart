import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/network_status.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/command_runner.dart';
import 'package:sdwan_client/platform/macos/macos_network_gateway.dart';

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
  test('readStatus combines routes, service, and DNS output', () async {
    final runner = FakeCommandRunner();
    runner.responses['id -u'] = const CommandResult(
      exitCode: 0,
      stdout: '501\n',
      stderr: '',
    );
    runner.responses['netstat -rn -f inet'] = const CommandResult(
      exitCode: 0,
      stdout: '''
Destination        Gateway            Flags
0/1                192.168.1.140      UGSc
128.0/1            192.168.1.140      UGSc
''',
      stderr: '',
    );
    runner.responses['route -n get default'] = const CommandResult(
      exitCode: 0,
      stdout: 'interface: en0\n',
      stderr: '',
    );
    runner.responses['networksetup -listallhardwareports'] =
        const CommandResult(
          exitCode: 0,
          stdout: '''
Hardware Port: Wi-Fi
Device: en0
Ethernet Address: 00:11:22:33:44:55
''',
          stderr: '',
        );
    runner.responses['networksetup -getdnsservers Wi-Fi'] =
        const CommandResult(
          exitCode: 0,
          stdout: '223.5.5.5\n114.114.114.114\n',
          stderr: '',
        );

    final status = await MacosNetworkGateway(
      runner: runner,
    ).readStatus(SdwanProfile.defaults());

    expect(status.platformName, 'macOS');
    expect(status.capability, PlatformCapability.full);
    expect(status.isAdmin, isFalse);
    expect(status.accelerationEnabled, isTrue);
    expect(status.activeInterfaceName, 'Wi-Fi');
    expect(status.dnsMode, DnsMode.static);
    expect(status.dnsServers, ['223.5.5.5', '114.114.114.114']);
  });
}
