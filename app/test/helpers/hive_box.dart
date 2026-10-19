import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:sesame/core/storage/hive_registrar.g.dart';

var _initialized = false;
var _boxCount = 0;

/// Box Hive réelle dans un dossier temporaire : les tests passent par les vrais
/// adapters générés (sérialisation comprise), sans toucher au stockage de l'app.
Future<Box<T>> openTestBox<T>({HiveCipher? cipher, String? name}) async {
  if (!_initialized) {
    Hive.init(Directory.systemTemp.createTempSync('sesame_hive_').path);
    Hive.registerAdapters();
    _initialized = true;
  }
  return Hive.openBox<T>(
    name ?? 'box_${_boxCount++}',
    encryptionCipher: cipher,
  );
}
