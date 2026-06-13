import '../domain/sdwan_profile.dart';
import 'ovpn_generator.dart';
import 'ovpn_parser.dart';

class ProfileImportExportService {
  SdwanProfile importOvpnContent(String content, {required String fileName}) {
    final name = fileName.replaceAll(
      RegExp(r'\.ovpn$', caseSensitive: false),
      '',
    );
    return OvpnParser().parse(content, fallbackName: name).profile;
  }

  String exportOvpnContent(SdwanProfile profile) {
    return OvpnGenerator().generate(profile);
  }
}
