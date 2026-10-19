import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mqtt/mqtt_service.dart';

/// Sobriété énergétique (§5) : pas de connexion MQTT quand l'app est en arrière-plan.
///
/// Les sonneries et changements d'état arrivent alors par push FCM, envoyés par
/// Node-RED qui reste connecté en permanence (étape 7).
class AppLifecycleService {
  AppLifecycleService(this._mqtt) {
    _listener = AppLifecycleListener(
      // `paused` et non `inactive` : une boîte de dialogue système (biométrie,
      // volet de notifications) rend l'app inactive sans qu'elle quitte l'écran.
      onPause: _mqtt.stop,
      // start() est idempotent : sans effet si la connexion est déjà là.
      // Au retour, le broker renvoie les valeurs retenues : l'état est resynchronisé.
      onResume: _mqtt.start,
    );
  }

  final MqttService _mqtt;
  late final AppLifecycleListener _listener;

  void dispose() => _listener.dispose();
}

/// Écouté par `SesameApp` pour vivre aussi longtemps que l'app.
final appLifecycleServiceProvider = Provider<AppLifecycleService>((ref) {
  final service = AppLifecycleService(ref.watch(mqttServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});
