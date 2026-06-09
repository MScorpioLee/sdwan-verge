import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Android app has internet permission for custom latency probes', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"'),
    );
  });

  test('Android method channel exposes native latency probes', () {
    final activity = read(
      'android/app/src/main/kotlin/com/example/sdwan_client/MainActivity.kt',
    );

    expect(activity, contains('"probeLatency"'));
    expect(activity, contains('probeLatency(call.arguments, result)'));
    expect(activity, contains('HttpURLConnection'));
    expect(activity, contains('"latencyMs"'));
  });
}
