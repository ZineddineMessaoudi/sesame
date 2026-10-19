import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../core/mqtt/mqtt_service.dart';
import '../../../core/storage/local_storage.dart';
import 'gate_repository.dart';
import 'models/gate_command.dart';

/// Ce qu'est devenue une commande sortie de la file d'attente.
class OutboxEntryOutcome {
  const OutboxEntryOutcome(this.command, this.outcome);

  final GateCommand command;
  final CommandOutcome outcome;
}

/// File des commandes émises hors ligne (§5).
///
/// Trois garanties non négociables :
/// - un renvoi réutilise **le même** [GateCommand] : même `cmdId`, même
///   `issuedAt`, même `expiresAt`. Le TTL ne repart jamais à zéro (§4) ;
/// - une commande périmée est **abandonnée**, jamais publiée en douce : un ordre
///   d'ouverture ne doit pas s'exécuter deux heures plus tard, le livreur parti ;
/// - l'ordre d'émission est respecté (FIFO).
class OutboxService {
  OutboxService(
    this._box,
    this._send, {
    Stream<MqttSessionState>? sessionStates,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    // Le flush se déclenche sur l'ouverture de session (`onConnected`, §5) et
    // nulle part ailleurs : un seul chemin pour la connexion initiale, la
    // reconnexion automatique et le retour au premier plan.
    _sessionSub = sessionStates?.listen((state) {
      if (state == MqttSessionState.connected) unawaited(flushQueue());
    });
  }

  final Box<GateCommand> _box;

  /// Injecté plutôt que le repository entier : la file n'a pas à connaître MQTT,
  /// et les tests fournissent une simple fonction.
  final Future<CommandOutcome> Function(GateCommand) _send;
  final DateTime Function() _clock;

  StreamSubscription<MqttSessionState>? _sessionSub;
  final _results = StreamController<OutboxEntryOutcome>.broadcast();
  bool _flushing = false;

  /// Sort des commandes rejouées sans action de l'utilisateur : c'est par là que
  /// « Expirée, non envoyée » remonte à l'écran.
  Stream<OutboxEntryOutcome> get results => _results.stream;

  /// Commandes en attente, dans leur ordre d'émission. Les clés auto-incrémentées
  /// de Hive donnent le FIFO sans champ d'ordre supplémentaire.
  List<GateCommand> get pending => _box.values.toList(growable: false);

  /// Met une commande en attente. Rien n'est publié ici.
  Future<void> enqueue(GateCommand command) => _box.add(command);

  /// Vide la file à l'ouverture de la session MQTT (`onConnected`, §5).
  ///
  /// L'expiration est réévaluée à chaque tour : un envoi lent peut périmer les
  /// commandes suivantes. S'arrête à la première qui ne part toujours pas — la
  /// connexion est retombée, et sauter par-dessus casserait l'ordre d'émission.
  Future<List<OutboxEntryOutcome>> flushQueue() async {
    // Une reconnexion peut en suivre une autre de près : deux flushs simultanés
    // publieraient la même commande deux fois.
    if (_flushing) return const [];
    _flushing = true;
    try {
      final results = <OutboxEntryOutcome>[];
      // Instantané des clés : la box est modifiée pendant le parcours.
      for (final key in _box.keys.toList(growable: false)) {
        final command = _box.get(key);
        if (command == null) continue;

        if (command.isExpiredAt(_clock())) {
          await _box.delete(key);
          results.add(_emit(command, CommandOutcome.expiredUnsent));
          continue;
        }

        final outcome = await _send(command);
        if (outcome == CommandOutcome.notSent) break;

        // Publiée : elle sort de la file quelle que soit la réponse de l'ESP32.
        // Même sans ack (`noResponse`), la rejouer créerait un doublon inutile ;
        // c'est `gate/state` qui tranchera l'affichage (§4).
        await _box.delete(key);
        results.add(_emit(command, outcome));
      }
      return results;
    } finally {
      _flushing = false;
    }
  }

  Future<void> dispose() async {
    await _sessionSub?.cancel();
    await _results.close();
  }

  OutboxEntryOutcome _emit(GateCommand command, CommandOutcome outcome) {
    final result = OutboxEntryOutcome(command, outcome);
    if (!_results.isClosed) _results.add(result);
    return result;
  }
}

final outboxServiceProvider = Provider<OutboxService>((ref) {
  final service = OutboxService(
    ref.watch(localStorageProvider).outbox,
    ref.watch(gateRepositoryProvider).sendCommand,
    sessionStates: ref.watch(mqttServiceProvider).sessionStates,
  );
  ref.onDispose(service.dispose);
  return service;
});
