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
    if (!_hasOpenVpnTrustMaterial(profile)) {
      errors.add('OpenVPN 配置缺少服务端 CA，请重新导入完整 .ovpn 或添加 ca/capath；不需要客户端证书');
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
    final parts = line.split(RegExp(r'\s+'));
    final key = parts.first.toLowerCase();
    if (_isBlockedOpenVpnDirective(key, parts)) {
      errors.add('OpenVPN 自定义配置不允许重复或危险指令：$key');
    }
  }
  return errors;
}

bool _isBlockedOpenVpnDirective(String key, List<String> parts) {
  if (_blockedOpenVpnDirectivePrefixes.contains(key)) {
    return true;
  }
  if (key == 'script-security') {
    final level = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return level == null || level < 0 || level > 3;
  }
  return false;
}

bool _hasOpenVpnTrustMaterial(SdwanProfile profile) {
  final blocks = profile.openVpn.inlineBlocks;
  if ((blocks['ca'] ?? '').trim().isNotEmpty) {
    return true;
  }
  for (final raw in profile.openVpn.customDirectives) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    final key = line.split(RegExp(r'\s+')).first.toLowerCase();
    if (key == 'ca' || key == 'capath' || key == 'peer-fingerprint') {
      return true;
    }
  }
  return false;
}
