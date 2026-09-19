import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the bearer token in the platform keychain/keystore.
class TokenStorage {
  TokenStorage._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'vita_token';

  static Future<String?> read() => _storage.read(key: _key);

  static Future<void> write(String token) =>
      _storage.write(key: _key, value: token);

  static Future<void> clear() => _storage.delete(key: _key);
}
