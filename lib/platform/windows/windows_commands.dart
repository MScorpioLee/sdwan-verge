import '../../domain/sdwan_profile.dart';

class WindowsCommand {
  const WindowsCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get display => [executable, ...arguments].join(' ');

  @override
  bool operator ==(Object other) {
    return other is WindowsCommand &&
        other.executable == executable &&
        _listEquals(other.arguments, arguments);
  }

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));

  @override
  String toString() => display;
}

class WindowsCommands {
  static WindowsCommand adminCheck() => const WindowsCommand('net', ['session']);

  static WindowsCommand routePrint() =>
      const WindowsCommand('route', ['print', '-4']);

  static WindowsCommand netshConfig() => const WindowsCommand(
        'netsh',
        ['interface', 'ip', 'show', 'config'],
      );

  static WindowsCommand dnsServers(String interfaceName) => WindowsCommand(
        'netsh',
        ['interface', 'ip', 'show', 'dnsservers', interfaceName],
      );

  static List<WindowsCommand> enableAcceleration(SdwanProfile profile) => [
        WindowsCommand('route', ['add', '0.0.0.0/1', profile.cpeIp, '-p']),
        WindowsCommand('route', ['add', '128.0.0.0/1', profile.cpeIp, '-p']),
        const WindowsCommand('ipconfig', ['/flushdns']),
      ];

  static List<WindowsCommand> disableAcceleration() => const [
        WindowsCommand('route', ['delete', '0.0.0.0/1']),
        WindowsCommand('route', ['delete', '128.0.0.0/1']),
        WindowsCommand('ipconfig', ['/flushdns']),
      ];

  static List<WindowsCommand> setDns(
    String interfaceName,
    SdwanProfile profile,
  ) =>
      [
        WindowsCommand('netsh', [
          'interface',
          'ip',
          'set',
          'dnsserver',
          interfaceName,
          'static',
          profile.primaryDns,
          'primary',
        ]),
        WindowsCommand('netsh', [
          'interface',
          'ip',
          'add',
          'dnsserver',
          interfaceName,
          profile.secondaryDns,
          'index=2',
        ]),
        const WindowsCommand('ipconfig', ['/flushdns']),
      ];

  static List<WindowsCommand> restoreDns(String interfaceName) => [
        WindowsCommand('netsh', [
          'interface',
          'ip',
          'set',
          'dnsserver',
          interfaceName,
          'dhcp',
        ]),
        const WindowsCommand('ipconfig', ['/flushdns']),
      ];
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
