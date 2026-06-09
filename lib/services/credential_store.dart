import 'package:flutter/services.dart';

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
