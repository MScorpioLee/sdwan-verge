import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readPackageScript() =>
      File('scripts/package_releases.sh').readAsStringSync();

  test('macOS packaging does not mutate signed app bundle', () {
    final script = readPackageScript();

    expect(script, contains('Contents/Resources/sdwan-macos-helper'));
    expect(script, contains('codesign --verify --deep --strict'));
    expect(script, isNot(contains('build_macos_helper.sh')));
    expect(script, isNot(contains(r'cp "$helper_path"')));
    expect(script, isNot(contains(r'chmod 755 "$app_path')));
  });
}
