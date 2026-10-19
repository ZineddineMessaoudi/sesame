import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../features/gate/data/models/gate_snapshot.dart';
import 'encryption_key_store.dart';
import 'hive_registrar.g.dart';

/// Boxes Hive chiffrées : la source de vérité locale de l'app (§5).
/// Le réseau alimente le repository, qui écrit ici ; l'UI ne lit jamais le réseau.
class LocalStorage {
  const LocalStorage({required this.gateState});

  final Box<GateSnapshot> gateState;

  static Future<LocalStorage> open({EncryptionKeyStore? keyStore}) async {
    await Hive.initFlutter();
    Hive.registerAdapters();
    final cipher = HiveAesCipher(
      await (keyStore ?? EncryptionKeyStore()).loadOrCreate(),
    );
    return LocalStorage(
      gateState: await _openBox<GateSnapshot>('gate_state', cipher),
    );
  }

  /// Une box illisible (clé perdue après une restauration, fichier corrompu) est
  /// recréée vide : ce n'est qu'un cache, le broker renverra l'état courant.
  static Future<Box<T>> _openBox<T>(String name, HiveCipher cipher) async {
    try {
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
    } on Object catch (e) {
      debugPrint('Hive : box $name illisible ($e), recréée vide');
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox<T>(name, encryptionCipher: cipher);
    }
  }
}

/// Surchargé dans `main.dart` une fois les boxes ouvertes (ouverture asynchrone).
final localStorageProvider = Provider<LocalStorage>(
  (ref) => throw UnimplementedError('localStorageProvider doit être surchargé'),
);
