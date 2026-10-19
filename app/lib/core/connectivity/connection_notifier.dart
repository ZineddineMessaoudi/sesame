import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stream_transform/stream_transform.dart';

import '../mqtt/mqtt_service.dart';
import 'network_monitor.dart';

/// Qualité de connexion affichée à l'utilisateur (§5).
enum ConnectionQuality {
  /// Réseau présent et session MQTT ouverte : les données arrivent en direct.
  online,

  /// Réseau présent mais broker injoignable (connexion en cours, Internet coupé
  /// derrière le Wi-Fi, broker en panne).
  degraded,

  /// Aucune interface réseau.
  offline,
}

/// Combine `connectivity_plus` et l'état de la session MQTT.
class ConnectionNotifier extends Notifier<ConnectionQuality> {
  /// Les changements de réseau arrivent en rafales (bascule Wi-Fi / mobile) :
  /// lissés sur 1 s, en gardant toujours la dernière valeur (trailing).
  static const throttle = Duration(seconds: 1);

  bool? _hasNetwork; // null tant que la première vérification n'est pas faite

  @override
  ConnectionQuality build() {
    final mqtt = ref.watch(mqttServiceProvider);
    final network = ref.watch(networkMonitorProvider);

    final subs = [
      mqtt.sessionStates.listen((_) => state = _compute(mqtt.sessionState)),
      network.changes.throttle(throttle, trailing: true).listen((hasNetwork) {
        final regained = _hasNetwork == false && hasNetwork;
        _hasNetwork = hasNetwork;
        // Le réseau revient : on se reconnecte tout de suite au lieu d'attendre le backoff.
        if (regained) mqtt.retryNow();
        state = _compute(mqtt.sessionState);
      }),
    ];
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
    });

    unawaited(
      network.check().then((hasNetwork) {
        if (!ref.mounted || _hasNetwork != null) return;
        _hasNetwork = hasNetwork;
        state = _compute(mqtt.sessionState);
      }),
    );
    return _compute(mqtt.sessionState);
  }

  ConnectionQuality _compute(MqttSessionState session) {
    if (_hasNetwork == false) return ConnectionQuality.offline;
    return session == MqttSessionState.connected
        ? ConnectionQuality.online
        : ConnectionQuality.degraded;
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionQuality>(
      ConnectionNotifier.new,
    );
