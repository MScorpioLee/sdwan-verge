import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('iOS method channel exposes native latency probes', () {
    final appDelegate = read('ios/Runner/AppDelegate.swift');

    expect(appDelegate, contains('"probeLatency"'));
    expect(appDelegate, contains('probeLatency(arguments: call.arguments'));
    expect(appDelegate, contains('URLSessionConfiguration.ephemeral'));
    expect(appDelegate, contains('"latencyMs"'));
  });
}
