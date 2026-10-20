import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the bearer token in the platform keychain/keystore.
class TokenStorage {
  TokenStorage._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'vita_token';
  static const _refreshKey = 'vita_refresh_token';

  static Future<String?> read() => _storage.read(key: _key);

  static Future<void> write(String token) =>
      _storage.write(key: _key, value: token);

  static Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  static Future<void> writeSession(String token, String refreshToken) async {
    await _storage.write(key: _key, value: token);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _refreshKey);
  }
}
