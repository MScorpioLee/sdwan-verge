import '../../domain/sdwan_profile.dart';

class LinuxCommand {
  const LinuxCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get display => [executable, ...arguments].join(' ');
}

class LinuxCommands {
  static LinuxCommand adminCheck() => const LinuxCommand('id', ['-u']);

  static LinuxCommand routeTable() => const LinuxCommand('ip', ['route', 'show']);

  static LinuxCommand defaultRoute() =>
      const LinuxCommand('ip', ['route', 'get', '1.1.1.1']);

  static LinuxCommand dnsStatus() => const LinuxCommand('resolvectl', ['dns']);

  static List<LinuxCommand> enableAcceleration(SdwanProfile profile) => [
    _pkexecShell('ip route replace 0.0.0.0/1 via ${profile.cpeIp}'),
    _pkexecShell('ip route replace 128.0.0.0/1 via ${profile.cpeIp}'),
    flushDns(),
  ];

  static List<LinuxCommand> disableAcceleration() => [
    _pkexecShell('ip route del 0.0.0.0/1'),
    _pkexecShell('ip route del 128.0.0.0/1'),
    flushDns(),
  ];

  static List<LinuxCommand> setDns(
    String interfaceName,
    SdwanProfile profile,
  ) => [
    LinuxCommand('pkexec', [
      'resolvectl',
      'dns',
      interfaceName,
      profile.primaryDns,
      profile.secondaryDns,
    ]),
    flushDns(),
  ];

  static List<LinuxCommand> restoreDns(String interfaceName) => [
    LinuxCommand('pkexec', ['resolvectl', 'revert', interfaceName]),
    flushDns(),
  ];

  static LinuxCommand flushDns() =>
      const LinuxCommand('resolvectl', ['flush-caches']);

  static LinuxCommand _pkexecShell(String command) =>
      LinuxCommand('pkexec', ['sh', '-c', command]);
}
