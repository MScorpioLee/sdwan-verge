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
  return errors;
}
