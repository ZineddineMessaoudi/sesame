import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
