import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connectivity/connection_notifier.dart';

import '../data/gate_repository.dart';
import '../data/models/device_status.dart';
import '../data/models/gate_snapshot.dart';
import '../data/models/gate_state.dart';

/// Ce que l'écran du portail affiche. `null` = pas encore reçu depuis le lancement.
class GateViewState {
  const GateViewState({
    this.snapshot,
    this.device,
    this.isLive = false,
    this.isConnected = false,
  });

  /// Dernier état connu : du cache Hive au démarrage, puis de MQTT.
  final GateSnapshot? snapshot;
  final DeviceStatus? device;

  /// Connexion `online` et ESP32 en ligne : tout changement nous parvient en direct,
  /// donc l'état affiché est à jour même s'il n'a pas bougé depuis des heures.
  final bool isLive;

  /// Session MQTT ouverte : sans elle, le dernier statut reçu de l'ESP32 ne prouve rien.
  final bool isConnected;

  /// Statut de l'équipement à afficher : inconnu tant qu'on n'est pas connecté,
  /// plutôt qu'un « en ligne » périmé.
  DeviceStatus? get visibleDevice => isConnected ? device : null;

  GateState? get gate => snapshot?.state;

  /// Dernière fois où l'état affiché était confirmé (pertinent quand `!isLive`).
  DateTime? get confirmedAt => snapshot?.receivedAt;

  /// Aucun état reçu : l'écran affiche un chargement plutôt qu'un état inventé.
  bool get isLoading => gate == null;

  GateViewState copyWith({
    GateSnapshot? snapshot,
    DeviceStatus? device,
    bool? isLive,
    bool? isConnected,
  }) => GateViewState(
    snapshot: snapshot ?? this.snapshot,
    device: device ?? this.device,
    isLive: isLive ?? this.isLive,
    isConnected: isConnected ?? this.isConnected,
  );
}

/// ViewModel de l'écran du portail : ne connaît que le repository, jamais MQTT.
class GateViewModel extends Notifier<GateViewState> {
  void _updateLive() {
    final connected = ref.read(connectionProvider) == ConnectionQuality.online;
    final live = connected && state.device == DeviceStatus.online;
    if (connected != state.isConnected) {
      state = state.copyWith(isConnected: connected);
    }
    if (live == state.isLive) return;
    // Fin du direct : on date l'état de cet instant (approximation : le LWT de
    // l'ESP32 arrive ~20 s après sa coupure réelle).
    final confirmed = live
        ? null
        : ref.read(gateRepositoryProvider).confirmNow();
    state = state.copyWith(isLive: live, snapshot: confirmed);
  }

  @override
  GateViewState build() {
    final repository = ref.watch(gateRepositoryProvider);
    final subs = [
      repository.watchGateState().listen(
        (snapshot) => state = state.copyWith(snapshot: snapshot),
      ),
      repository.watchDeviceStatus().listen((device) {
        state = state.copyWith(device: device);
        _updateLive();
      }),
    ];
    ref.listen(connectionProvider, (_, _) => _updateLive());
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
    });
    // Abonné avant de se connecter : les valeurs retenues, envoyées dès la connexion, ne sont pas perdues.
    unawaited(repository.connect());
    // Hydratation : l'écran part du cache, jamais d'un écran vide quand on a déjà su.
    return GateViewState(
      snapshot: repository.lastKnown,
      isConnected: ref.read(connectionProvider) == ConnectionQuality.online,
    );
  }
}

final gateViewModelProvider = NotifierProvider<GateViewModel, GateViewState>(
  GateViewModel.new,
);
