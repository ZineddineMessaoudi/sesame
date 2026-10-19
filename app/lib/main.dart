import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // mqtt_client ferme sa socket TLS sans attendre le résultat : quand le réseau
  // tombe, la `SocketException` qui en sort n'est rattrapée par personne. C'est
  // une coupure attendue (gérée par la reconnexion), pas un plantage : on la
  // journalise. Toute autre erreur garde le traitement par défaut.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is SocketException) {
      debugPrint(
        'Réseau : socket fermée (${error.osError?.message ?? error.message})',
      );
      return true;
    }
    return false;
  };

  // Validée avant tout le reste : sans config, inutile de démarrer (Firebase viendra ici).
  final config = AppConfig.fromEnvironment();
  // Boxes chiffrées ouvertes avant le premier écran : l'état en cache s'affiche tout de suite.
  final storage = await LocalStorage.open();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        localStorageProvider.overrideWithValue(storage),
      ],
      child: const SesameApp(),
    ),
  );
}
