import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OpenVpnCredential {
  const OpenVpnCredential({required this.username, required this.password});

  final String username;
  final String password;
}

abstract interface class CredentialStore {
  Future<void> save(String ref, OpenVpnCredential credential);
  Future<OpenVpnCredential?> read(String ref);
  Future<void> delete(String ref);
}

class MethodChannelCredentialStore implements CredentialStore {
  MethodChannelCredentialStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('sdwan_client/credentials');

  final MethodChannel _channel;

  @override
  Future<void> save(String ref, OpenVpnCredential credential) async {
    await _channel.invokeMethod<void>('saveOpenVpnCredential', {
      'ref': ref,
      'username': credential.username,
      'password': credential.password,
    });
  }

  @override
  Future<OpenVpnCredential?> read(String ref) async {
    final result = await _channel.invokeMethod<Object?>(
      'readOpenVpnCredential',
      {'ref': ref},
    );
    if (result is! Map) {
      return null;
    }
    return OpenVpnCredential(
      username: result['username']?.toString() ?? '',
      password: result['password']?.toString() ?? '',
    );
  }

  @override
  Future<void> delete(String ref) async {
    await _channel.invokeMethod<void>('deleteOpenVpnCredential', {'ref': ref});
  }
}

class SharedPreferencesCredentialStore implements CredentialStore {
  const SharedPreferencesCredentialStore();

  @override
  Future<void> save(String ref, OpenVpnCredential credential) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(ref, 'username'), credential.username);
    await prefs.setString(_key(ref, 'password'), credential.password);
  }

  @override
  Future<OpenVpnCredential?> read(String ref) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_key(ref, 'username'));
    final password = prefs.getString(_key(ref, 'password'));
    if (username == null && password == null) {
      return null;
    }
    return OpenVpnCredential(username: username ?? '', password: password ?? '');
  }

  @override
  Future<void> delete(String ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(ref, 'username'));
    await prefs.remove(_key(ref, 'password'));
  }

  String _key(String ref, String field) => 'sdwan.openvpn.$ref.$field';
}
