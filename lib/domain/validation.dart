import 'acceleration_mode.dart';
import 'sdwan_profile.dart';

bool isValidIpv4(String value) {
  final parts = value.trim().split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) {
      return false;
    }
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) {
      return false;
    }
  }
  return true;
}

List<String> validateProfile(SdwanProfile profile) {
  final errors = <String>[];
  if (!isValidIpv4(profile.cpeIp)) {
    errors.add('CPE 网关地址格式不正确');
  }
  if (!isValidIpv4(profile.primaryDns)) {
    errors.add('主 DNS 地址格式不正确');
  }
  if (!isValidIpv4(profile.secondaryDns)) {
    errors.add('备用 DNS 地址格式不正确');
  }
  if (profile.mode == AccelerationMode.openVpn) {
    if (profile.openVpn.remoteHost.trim().isEmpty) {
      errors.add('OpenVPN 服务器地址不能为空');
    }
    if (profile.openVpn.remotePort < 1 || profile.openVpn.remotePort > 65535) {
      errors.add('OpenVPN 端口必须在 1-65535 之间');
    }
    errors.addAll(validateOpenVpnDirectives(profile.openVpn.customDirectives));
  }
  return errors;
}

const _blockedOpenVpnDirectivePrefixes = {
  'proto',
  'remote',
  'auth-user-pass',
  'redirect-gateway',
  'script-security',
  'up',
  'down',
  'route-up',
  'client-connect',
};

List<String> validateOpenVpnDirectives(List<String> directives) {
  final errors = <String>[];
  for (final raw in directives) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    final key = line.split(RegExp(r'\s+')).first.toLowerCase();
    if (_blockedOpenVpnDirectivePrefixes.contains(key)) {
      errors.add('OpenVPN 自定义配置不允许重复或危险指令：$key');
    }
  }
  return errors;
}
