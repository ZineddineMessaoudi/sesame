import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuration injectée à la compilation via `--dart-define-from-file=env.json`.
///
/// Pourquoi `--dart-define` : aucun secret ni URL en dur dans le code ou Git (§10),
/// et une URL de backend différente par cible (émulateur, iPhone) sans toucher au code.
class AppConfig {
  const AppConfig({
    required this.mqttHost,
    required this.mqttPort,
    required this.mqttUsername,
    required this.mqttPassword,
    required this.siteId,
    required this.apiBaseUrl,
  });

  final String mqttHost;
  final int mqttPort;
  final String mqttUsername;
  final String mqttPassword;
  final String siteId;
  final Uri apiBaseUrl;

  /// Lit les valeurs compilées et échoue tout de suite si l'une manque :
  /// mieux vaut un message clair au démarrage qu'une connexion MQTT muette en démo.
  factory AppConfig.fromEnvironment() {
    // `String.fromEnvironment` doit recevoir des constantes : d'où cette table explicite.
    const values = {
      'MQTT_HOST': String.fromEnvironment('MQTT_HOST'),
      'MQTT_PORT': String.fromEnvironment('MQTT_PORT'),
      'MQTT_USERNAME': String.fromEnvironment('MQTT_USERNAME'),
      'MQTT_PASSWORD': String.fromEnvironment('MQTT_PASSWORD'),
      'SITE_ID': String.fromEnvironment('SITE_ID'),
      'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
    };

    final missing = [
      for (final e in values.entries)
        if (e.value.isEmpty) e.key,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Configuration manquante : ${missing.join(', ')}. '
        'Lancer avec --dart-define-from-file=env.json (modèle : env.example.json).',
      );
    }

    final port = int.tryParse(values['MQTT_PORT']!);
    if (port == null) {
      throw StateError('MQTT_PORT invalide : "${values['MQTT_PORT']}".');
    }

    return AppConfig(
      mqttHost: values['MQTT_HOST']!,
      mqttPort: port,
      mqttUsername: values['MQTT_USERNAME']!,
      mqttPassword: values['MQTT_PASSWORD']!,
      siteId: values['SITE_ID']!,
      apiBaseUrl: Uri.parse(values['API_BASE_URL']!),
    );
  }
}

/// Surchargé dans `main.dart` avec la config validée, et dans les tests avec une config factice.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider doit être surchargé'),
);
