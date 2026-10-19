import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/mqtt/mqtt_service.dart';
import '../../../core/mqtt/mqtt_topics.dart';
import '../../../core/storage/local_storage.dart';
import 'models/device_status.dart';
import 'models/gate_ack.dart';
import 'models/gate_command.dart';
import 'models/gate_snapshot.dart';
import 'models/gate_state.dart';

/// Issue d'une commande, du point de vue de l'utilisateur.
enum CommandOutcome {
  /// Ack `accepted` ou `duplicate` : exécutée une fois (§4, `duplicate` = succès).
  executed,

  /// L'ESP32 l'a jugée périmée (TTL dépassé ou horloges trop décalées).
  rejectedExpired,

  /// L'ESP32 n'a pas l'heure : refus par défaut.
  rejectedNoTime,

  /// Pas d'ack dans le délai : on ne sait pas si elle a été exécutée ;
  /// l'état publié sur `gate/state` tranchera.
  noResponse,

  /// Pas de session MQTT : rien n'a été publié. Signal interne, c'est l'appelant
  /// qui décide d'abandonner ou de mettre en attente.
  notSent,

  /// Mise en attente dans l'outbox, faute de session MQTT : « En attente » (§5).
  queued,

  /// TTL écoulé pendant l'attente hors ligne : abandonnée sans jamais avoir été
  /// publiée, « Expirée, non envoyée ». Distinct de [rejectedExpired], où c'est
  /// l'ESP32 qui a refusé une commande bel et bien reçue (§5).
  expiredUnsent,
}

/// Accès aux données du portail (Model du MVVM) : traduit les messages MQTT
/// bruts en objets métier et les met en cache dans Hive (réseau -> repository
/// -> Hive -> Notifier -> UI, §5). Seule couche de la feature qui connaît MQTT et Hive.
class GateRepository {
  GateRepository(
    this._mqtt,
    this._topics,
    this._cache, {
    DateTime Function()? clock,
    String Function()? newId,
    this.ackTimeout = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4 {
    _mqtt
      ..subscribe(_topics.gateState)
      ..subscribe(_topics.deviceStatus)
      ..subscribe(_topics.gateAck);
    _sub = _mqtt.messages.listen(_onMessage);
  }

  final MqttService _mqtt;
  final MqttTopics _topics;
  final Box<GateSnapshot> _cache;
  static const _cacheKey = 'current';
  final DateTime Function()
  _clock; // injectable : les tests maîtrisent le temps
  final String Function() _newId;

  /// Délai d'attente de l'ack avant « Pas de réponse du portail » (§4).
  final Duration ackTimeout;
  late final StreamSubscription<MqttInboundMessage> _sub;

  final _gateStates = StreamController<GateSnapshot>.broadcast();
  final _deviceStatuses = StreamController<DeviceStatus>.broadcast();
  final _acks = StreamController<GateAck>.broadcast();

  int? _lastSeq;

  /// Dernier état connu, lu dans Hive : affiché dès le démarrage, même hors ligne.
  GateSnapshot? get lastKnown => _cache.get(_cacheKey);

  Stream<GateSnapshot> watchGateState() => _gateStates.stream;

  /// On perd le direct (réseau, broker ou ESP32) : l'état en cache était encore
  /// juste à cet instant. On le date de maintenant, pour que « Mis à jour il y a … »
  /// compte depuis la dernière confirmation et non depuis le dernier changement.
  GateSnapshot? confirmNow() {
    final current = lastKnown;
    if (current == null) return null;
    final confirmed = GateSnapshot(state: current.state, receivedAt: _clock());
    unawaited(_cache.put(_cacheKey, confirmed));
    return confirmed;
  }

  Stream<DeviceStatus> watchDeviceStatus() => _deviceStatuses.stream;

  /// Démarre la connexion MQTT (idempotent) : les valeurs retenues arrivent ensuite.
  Future<void> connect() => _mqtt.start();

  /// Nouvelle commande : nouveau `cmdId` et nouveau TTL. À n'appeler que pour une
  /// action de l'utilisateur (« Ouvrir », « Réessayer »), jamais pour un renvoi.
  GateCommand newCommand(GateAction action) =>
      GateCommand.create(cmdId: _newId(), action: action, now: _clock());

  /// Publie la commande et attend l'ack de l'ESP32 correspondant à son `cmdId`.
  Future<CommandOutcome> sendCommand(GateCommand command) async {
    // Écoute posée avant la publication : l'ack ne peut pas arriver « trop tôt ».
    final ack = _acks.stream
        .firstWhere((a) => a.cmdId == command.cmdId)
        .timeout(ackTimeout);
    if (!_mqtt.publish(_topics.gateCmd, command.toPayload())) {
      ack.ignore();
      return CommandOutcome.notSent;
    }
    try {
      return switch ((await ack).result) {
        AckResult.accepted || AckResult.duplicate => CommandOutcome.executed,
        AckResult.rejectedExpired => CommandOutcome.rejectedExpired,
        AckResult.rejectedNoTime => CommandOutcome.rejectedNoTime,
      };
    } on TimeoutException {
      return CommandOutcome.noResponse;
    } on StateError {
      return CommandOutcome.noResponse; // repository fermé pendant l'attente
    }
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _acks.close();
    await _gateStates.close();
    await _deviceStatuses.close();
  }

  void _onMessage(MqttInboundMessage message) {
    if (message.topic == _topics.gateState) {
      _onGateState(message);
    } else if (message.topic == _topics.deviceStatus) {
      _onDeviceStatus(message);
    } else if (message.topic == _topics.gateAck) {
      final ack = GateAck.tryParse(message.payload);
      if (ack != null) _acks.add(ack);
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
    final snapshot = GateSnapshot(state: state, receivedAt: _clock());
    // Écriture en mémoire immédiate, flush disque en arrière-plan : pas d'attente côté UI.
    unawaited(_cache.put(_cacheKey, snapshot));
    _gateStates.add(snapshot);
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
    ref.watch(localStorageProvider).gateState,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
