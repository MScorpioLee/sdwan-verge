import '../../domain/network_status.dart';

class ParsedDnsInfo {
  const ParsedDnsInfo({
    required this.mode,
    required this.servers,
  });

  final DnsMode mode;
  final List<String> servers;
}

class WindowsParsers {
  static String? defaultRouteInterfaceIp(String routePrint) {
    for (final line in routePrint.split('\n')) {
      final columns = _columns(line);
      if (columns.length >= 5 &&
          columns[0] == '0.0.0.0' &&
          columns[1] == '0.0.0.0') {
        return columns[3];
      }
    }
    return null;
  }

  static bool hasAccelerationRoutes(String routePrint, String cpeIp) {
    var hasLowerHalf = false;
    var hasUpperHalf = false;
    for (final line in routePrint.split('\n')) {
      final columns = _columns(line);
      if (columns.length < 4) {
        continue;
      }
      final destination = columns[0];
      final netmask = columns[1];
      final gateway = columns[2];
      if (gateway != cpeIp || netmask != '128.0.0.0') {
        continue;
      }
      if (destination == '0.0.0.0') {
        hasLowerHalf = true;
      }
      if (destination == '128.0.0.0') {
        hasUpperHalf = true;
      }
    }
    return hasLowerHalf && hasUpperHalf;
  }

  static String? interfaceNameForIp(String netshConfig, String ip) {
    String? currentInterface;
    for (final rawLine in netshConfig.split('\n')) {
      final line = rawLine.trim();
      final match =
          RegExp(r'^Configuration for interface "?(.+?)"?$').firstMatch(line);
      if (match != null) {
        currentInterface = match.group(1);
        continue;
      }
      if (currentInterface != null && line.contains('IP Address:')) {
        final value = line.split(':').last.trim();
        if (value == ip) {
          return currentInterface;
        }
      }
      if (line.isEmpty) {
        currentInterface = null;
      }
    }
    return null;
  }

  static ParsedDnsInfo dnsInfo(String output) {
    final servers = <String>[];
    var mode = DnsMode.unknown;
    final ipPattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.contains('DHCP')) {
        mode = DnsMode.dhcp;
      }
      if (line.contains('Statically Configured DNS Servers')) {
        mode = DnsMode.static;
      }
      for (final match in ipPattern.allMatches(line)) {
        servers.add(match.group(0)!);
      }
    }

    return ParsedDnsInfo(mode: mode, servers: servers);
  }

  static List<String> _columns(String line) {
    return line
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
  }
}
