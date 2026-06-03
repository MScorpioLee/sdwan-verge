import '../../domain/sdwan_profile.dart';

class MacosCommand {
  const MacosCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get display => [executable, ...arguments].join(' ');
}

class MacosCommands {
  static MacosCommand adminCheck() => const MacosCommand('id', ['-u']);

  static MacosCommand defaultRoute() =>
      const MacosCommand('route', ['-n', 'get', 'default']);

  static MacosCommand routeTable() =>
      const MacosCommand('netstat', ['-rn', '-f', 'inet']);

  static MacosCommand hardwarePorts() =>
      const MacosCommand('networksetup', ['-listallhardwareports']);

  static MacosCommand dnsServers(String serviceName) =>
      MacosCommand('networksetup', ['-getdnsservers', serviceName]);

  static List<MacosCommand> enableAcceleration(SdwanProfile profile) => [
    _administrator(
      'route -n add -net 0.0.0.0 -netmask 128.0.0.0 ${profile.cpeIp}',
    ),
    _administrator(
      'route -n add -net 128.0.0.0 -netmask 128.0.0.0 ${profile.cpeIp}',
    ),
    ...flushDns(),
  ];

  static List<MacosCommand> disableAcceleration() => [
    _administrator('route -n delete -net 0.0.0.0 -netmask 128.0.0.0'),
    _administrator('route -n delete -net 128.0.0.0 -netmask 128.0.0.0'),
    ...flushDns(),
  ];

  static List<MacosCommand> setDns(
    String serviceName,
    SdwanProfile profile,
  ) => [
    _administrator(
      'networksetup -setdnsservers "${_escapeShellDoubleQuotes(serviceName)}" '
      '${profile.primaryDns} ${profile.secondaryDns}',
    ),
    ...flushDns(),
  ];

  static List<MacosCommand> restoreDns(String serviceName) => [
    _administrator(
      'networksetup -setdnsservers "${_escapeShellDoubleQuotes(serviceName)}" Empty',
    ),
    ...flushDns(),
  ];

  static List<MacosCommand> flushDns() => const [
    MacosCommand('dscacheutil', ['-flushcache']),
    MacosCommand('killall', ['-HUP', 'mDNSResponder']),
  ];

  static MacosCommand _administrator(String shellCommand) {
    final escaped = shellCommand
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    return MacosCommand('osascript', [
      '-e',
      'do shell script "$escaped" with administrator privileges',
    ]);
  }

  static String _escapeShellDoubleQuotes(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
