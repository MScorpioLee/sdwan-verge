import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdwan_client/services/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test_credentials');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'readOpenVpnCredential') {
            return {'username': 'user', 'password': 'secret'};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('stores reads and deletes credential by reference', () async {
    final store = MethodChannelCredentialStore(channel: channel);

    await store.save(
      'profile-1',
      const OpenVpnCredential(username: 'user', password: 'secret'),
    );
    final credential = await store.read('profile-1');
    await store.delete('profile-1');

    expect(credential?.username, 'user');
    expect(credential?.password, 'secret');
    expect(calls.map((call) => call.method), [
      'saveOpenVpnCredential',
      'readOpenVpnCredential',
      'deleteOpenVpnCredential',
    ]);
  });

  test('shared preferences store persists credential by reference', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesCredentialStore();

    await store.save(
      'profile-2',
      const OpenVpnCredential(username: 'user01', password: 'secret'),
    );
    final credential = await store.read('profile-2');
    await store.delete('profile-2');

    expect(credential?.username, 'user01');
    expect(credential?.password, 'secret');
    expect(await store.read('profile-2'), isNull);
  });
}
