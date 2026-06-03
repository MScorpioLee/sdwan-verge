import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/sdwan_profile.dart';
import 'package:sdwan_client/platform/macos/macos_commands.dart';

void main() {
  test('builds administrator route commands and cache flush commands', () {
    final commands = MacosCommands.enableAcceleration(SdwanProfile.defaults());

    expect(commands.map((command) => command.display), [
      'osascript -e do shell script "route -n add -net 0.0.0.0 -netmask 128.0.0.0 192.168.1.140" with administrator privileges',
      'osascript -e do shell script "route -n add -net 128.0.0.0 -netmask 128.0.0.0 192.168.1.140" with administrator privileges',
      'dscacheutil -flushcache',
      'killall -HUP mDNSResponder',
    ]);
  });

  test('builds DNS command for selected network service', () {
    final commands = MacosCommands.setDns('Wi-Fi', SdwanProfile.defaults());

    expect(commands.map((command) => command.display), [
      'osascript -e do shell script "networksetup -setdnsservers \\"Wi-Fi\\" 223.5.5.5 114.114.114.114" with administrator privileges',
      'dscacheutil -flushcache',
      'killall -HUP mDNSResponder',
    ]);
  });
}
