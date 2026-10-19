import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../features/gate/data/models/gate_command.dart';
import '../../features/gate/data/models/gate_snapshot.dart';
import 'encryption_key_store.dart';
import 'hive_registrar.g.dart';

/// Boxes Hive chiffrées : la source de vérité locale de l'app (§5).
/// Le réseau alimente le repository, qui écrit ici ; l'UI ne lit jamais le réseau.
class LocalStorage {
  const LocalStorage({required this.gateState, required this.outbox});

  final Box<GateSnapshot> gateState;

  /// Commandes émises hors ligne, en attente d'une session MQTT (§5).
  /// Chiffrée comme les autres : un ordre d'ouverture ne traîne pas en clair.
  final Box<GateCommand> outbox;

  static Future<LocalStorage> open({EncryptionKeyStore? keyStore}) async {
    await Hive.initFlutter();
    Hive.registerAdapters();
    final cipher = HiveAesCipher(
      await (keyStore ?? EncryptionKeyStore()).loadOrCreate(),
    );
    return LocalStorage(
      gateState: await _openBox<GateSnapshot>('gate_state', cipher),
      outbox: await _openBox<GateCommand>('outbox', cipher),
    );
  }

  /// Une box illisible (clé perdue après une restauration, fichier corrompu) est
  /// recréée vide. Pour `gate_state` ce n'est qu'un cache, le broker renverra
  /// l'état courant ; pour `outbox`, perdre des commandes est le bon échec :
  /// on n'envoie jamais un ordre d'ouverture qu'on ne sait plus relire.
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
