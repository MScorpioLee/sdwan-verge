import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/domain/openvpn_profile.dart';
import 'package:sdwan_client/services/profile_import_export_service.dart';

void main() {
  test('imports ovpn content as editable openvpn profile', () {
    const content = 'proto tcp\nremote 192.168.1.140 10189\nauth-user-pass\n';

    final result = ProfileImportExportService().importOvpnContent(
      content,
      fileName: 'cpe.ovpn',
    );

    expect(result.name, 'cpe');
    expect(result.openVpn.protocol, OpenVpnProtocol.tcpClient);
    expect(result.openVpn.authUserPass, isTrue);
  });

  test('exports profile without credentials', () {
    final profile = ProfileImportExportService().importOvpnContent(
      'proto udp4\nremote 192.168.1.140 10189\nauth-user-pass\n',
      fileName: 'cpe.ovpn',
    );

    final exported = ProfileImportExportService().exportOvpnContent(profile);

    expect(exported, contains('auth-user-pass'));
    expect(exported, isNot(contains('password')));
  });
}
