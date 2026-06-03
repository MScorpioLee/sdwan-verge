import '../../domain/network_status.dart';

class MacosDnsInfo {
  const MacosDnsInfo({required this.mode, required this.servers});

  final DnsMode mode;
  final List<String> servers;
}

class MacosParsers {
  static String? defaultInterface(String routeGetOutput) {
    for (final rawLine in routeGetOutput.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('interface:')) {
        return line.split(':').last.trim();
      }
    }
    return null;
  }

  static String? serviceNameForDevice(String hardwarePortsOutput, String device) {
    String? currentPort;
    for (final rawLine in hardwarePortsOutput.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('Hardware Port:')) {
        currentPort = line.split(':').skip(1).join(':').trim();
        continue;
      }
      if (line.startsWith('Device:')) {
        final currentDevice = line.split(':').last.trim();
        if (currentDevice == device) {
          return currentPort;
        }
      }
    }
    return null;
  }

  static MacosDnsInfo dnsInfo(String output) {
    final servers = <String>[];
    final ipPattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
    for (final match in ipPattern.allMatches(output)) {
      servers.add(match.group(0)!);
    }
    if (servers.isNotEmpty) {
      return MacosDnsInfo(mode: DnsMode.static, servers: servers);
    }
    if (output.toLowerCase().contains('there aren')) {
      return const MacosDnsInfo(mode: DnsMode.dhcp, servers: []);
    }
    return const MacosDnsInfo(mode: DnsMode.unknown, servers: []);
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
      if (columns.length < 2 || columns[1] != cpeIp) {
        continue;
      }
      if (columns[0] == '0/1' || columns[0] == '0.0.0.0/1') {
        hasLowerHalf = true;
      }
      if (columns[0] == '128.0/1' || columns[0] == '128.0.0.0/1') {
        hasUpperHalf = true;
      }
    }
    return hasLowerHalf && hasUpperHalf;
  }
}
