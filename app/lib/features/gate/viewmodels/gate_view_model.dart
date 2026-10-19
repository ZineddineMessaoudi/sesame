import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gate_repository.dart';
import '../data/models/device_status.dart';
import '../data/models/gate_state.dart';

/// Ce que l'écran du portail affiche. `null` = pas encore reçu depuis le lancement.
class GateViewState {
  const GateViewState({this.gate, this.device});

  final GateState? gate;
  final DeviceStatus? device;

  /// Aucun état reçu : l'écran affiche un chargement plutôt qu'un état inventé.
  bool get isLoading => gate == null;

  GateViewState copyWith({GateState? gate, DeviceStatus? device}) =>
      GateViewState(gate: gate ?? this.gate, device: device ?? this.device);
}

/// ViewModel de l'écran du portail : ne connaît que le repository, jamais MQTT.
class GateViewModel extends Notifier<GateViewState> {
  @override
  GateViewState build() {
    final repository = ref.watch(gateRepositoryProvider);
    final subs = [
      repository.watchGateState().listen(
        (gate) => state = state.copyWith(gate: gate),
      ),
      repository.watchDeviceStatus().listen(
        (device) => state = state.copyWith(device: device),
      ),
    ];
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
    });
    // Abonné avant de se connecter : les valeurs retenues, envoyées dès la connexion, ne sont pas perdues.
    unawaited(repository.connect());
    return const GateViewState();
  }
}

final gateViewModelProvider = NotifierProvider<GateViewModel, GateViewState>(
  GateViewModel.new,
);
