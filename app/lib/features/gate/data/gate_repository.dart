import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/mqtt/mqtt_service.dart';
import '../../../core/mqtt/mqtt_topics.dart';
import 'models/device_status.dart';
import 'models/gate_state.dart';

/// Accès aux données du portail (Model du MVVM) : traduit les messages MQTT
/// bruts en objets métier. Seule couche de la feature qui connaît MQTT.
class GateRepository {
  GateRepository(this._mqtt, this._topics) {
    _mqtt
      ..subscribe(_topics.gateState)
      ..subscribe(_topics.deviceStatus);
    _sub = _mqtt.messages.listen(_onMessage);
  }

  final MqttService _mqtt;
  final MqttTopics _topics;
  late final StreamSubscription<MqttInboundMessage> _sub;

  final _gateStates = StreamController<GateState>.broadcast();
  final _deviceStatuses = StreamController<DeviceStatus>.broadcast();

  int? _lastSeq;

  Stream<GateState> watchGateState() => _gateStates.stream;
  Stream<DeviceStatus> watchDeviceStatus() => _deviceStatuses.stream;

  /// Démarre la connexion MQTT (idempotent) : les valeurs retenues arrivent ensuite.
  Future<void> connect() => _mqtt.start();

  Future<void> dispose() async {
    await _sub.cancel();
    await _gateStates.close();
    await _deviceStatuses.close();
  }

  void _onMessage(MqttInboundMessage message) {
    if (message.topic == _topics.gateState) {
      _onGateState(message);
    } else if (message.topic == _topics.deviceStatus) {
      _onDeviceStatus(message);
    }
  }

  void _onGateState(MqttInboundMessage message) {
    final state = GateState.tryParse(message.payload);
    if (state == null) {
      debugPrint('Portail : payload ignoré (${message.payload})');
      return;
    }
    // Un message retenu est l'état courant selon le broker : on l'accepte toujours,
    // même si son seq est plus petit (ESP32 redémarré pendant que l'app était déconnectée).
    // En direct, un seq déjà vu est un doublon QoS 1 ou un message en retard : ignoré.
    final last = _lastSeq;
    if (!message.retained && last != null && state.seq <= last) return;
    _lastSeq = state.seq;
    _gateStates.add(state);
  }

  void _onDeviceStatus(MqttInboundMessage message) {
    final status = DeviceStatus.tryParse(message.payload);
    if (status == null) {
      debugPrint('Équipement : payload ignoré (${message.payload})');
      return;
    }
    // L'ESP32 vient (re)démarrer : son seq repart à 0, l'ancienne référence ne vaut plus rien.
    if (status == DeviceStatus.online) _lastSeq = null;
    _deviceStatuses.add(status);
  }
}

final gateRepositoryProvider = Provider<GateRepository>((ref) {
  final repository = GateRepository(
    ref.watch(mqttServiceProvider),
    MqttTopics(ref.watch(appConfigProvider).siteId),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
