import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const String _keyBroker = 'mqtt_broker';
  static const String _keyUsername = 'mqtt_username';
  static const String _keyPassword = 'mqtt_password';
  static const String _keyClientId = 'mqtt_client_id';
  static Future<void> saveMQTTcredentials({
    required String broker,
    required String username,
    required String password,
    String? clientId,
  }) async {
    await _storage.write(key: _keyBroker, value: broker);
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
    if (clientId != null) {
      await _storage.write(key: _keyClientId, value: clientId);
    }
  }

  static Future<Map<String, String?>> getMQTTcredentials() async {
    return {
      'broker': await _storage.read(key: _keyBroker),
      'username': await _storage.read(key: _keyUsername),
      'password': await _storage.read(key: _keyPassword),
      'clientId': await _storage.read(key: _keyClientId),
    };
  }

  static Future<void> clearMQTTcredentials() async {
    await _storage.delete(key: _keyBroker);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyClientId);
  }

  static Future<bool> hasCredentials() async {
    final broker = await _storage.read(key: _keyBroker);
    return broker != null && broker.isNotEmpty;
  }
}
