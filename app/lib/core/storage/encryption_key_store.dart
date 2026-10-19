import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive_ce.dart';

/// Clé AES-256 des boxes Hive (chiffrement au repos, §10).
///
/// Générée au premier lancement, puis gardée dans le Keychain (iOS) ou le
/// Keystore (Android) : jamais dans le code, jamais en clair sur le disque.
class EncryptionKeyStore {
  EncryptionKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // « this_device » : la clé ne part pas dans une sauvegarde iCloud.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _keyName = 'hive_encryption_key';

  final FlutterSecureStorage _storage;

  Future<List<int>> loadOrCreate() async {
    final stored = await _storage.read(key: _keyName);
    if (stored != null) return base64Decode(stored);
    final key = Hive.generateSecureKey(); // 32 octets aléatoires sûrs
    await _storage.write(key: _keyName, value: base64Encode(key));
    return key;
  }
}
