import '../../domain/network_status.dart';

class LinuxRouteInfo {
  const LinuxRouteInfo({this.interfaceName, this.sourceIp});

  final String? interfaceName;
  final String? sourceIp;
}

class LinuxDnsInfo {
  const LinuxDnsInfo({required this.mode, required this.servers});

  final DnsMode mode;
  final List<String> servers;
}

class LinuxParsers {
  static LinuxRouteInfo defaultRouteInfo(String output) {
    final columns = output
        .replaceAll('\n', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    String? interfaceName;
    String? sourceIp;
    for (var index = 0; index < columns.length; index++) {
      if (columns[index] == 'dev' && index + 1 < columns.length) {
        interfaceName = columns[index + 1];
      }
      if (columns[index] == 'src' && index + 1 < columns.length) {
        sourceIp = columns[index + 1];
      }
    }
    return LinuxRouteInfo(interfaceName: interfaceName, sourceIp: sourceIp);
  }

  static LinuxDnsInfo dnsInfo(String output, String interfaceName) {
    final lines = output.split('\n');
    final ipPattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
    final servers = <String>[];
    var insideTarget = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      final linkMatch = RegExp(r'^Link\s+\d+\s+\((.+)\)').firstMatch(line);
      if (linkMatch != null) {
        insideTarget = linkMatch.group(1) == interfaceName;
        continue;
      }
      if (!insideTarget) {
        continue;
      }
      for (final match in ipPattern.allMatches(line)) {
        servers.add(match.group(0)!);
      }
    }

    if (servers.isEmpty) {
      return const LinuxDnsInfo(mode: DnsMode.unknown, servers: []);
    }
    return LinuxDnsInfo(mode: DnsMode.static, servers: servers);
  }

  static bool hasAccelerationRoutes(String routeTable, String cpeIp) {
    var hasLowerHalf = false;
    var hasUpperHalf = false;
    for (final rawLine in routeTable.split('\n')) {
      final columns = rawLine
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (columns.length < 3 || !columns.contains(cpeIp)) {
        continue;
      }
      if (columns[0] == '0.0.0.0/1') {
        hasLowerHalf = true;
      }
      if (columns[0] == '128.0.0.0/1') {
        hasUpperHalf = true;
      }
    }
    return hasLowerHalf && hasUpperHalf;
  }
}
