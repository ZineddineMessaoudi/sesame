import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/history_repository.dart';
import '../data/models/gate_event.dart';

/// État de l'écran historique.
///
/// [events] et [error] coexistent volontairement : un échec réseau n'efface
/// jamais ce qui est déjà affiché, c'est tout l'intérêt de l'offline-first (§5).
class HistoryState {
  const HistoryState({required this.events, this.loading = false, this.error});

  final List<GateEvent> events;
  final bool loading;

  /// Message prêt à afficher, `null` si la dernière récupération a réussi.
  final String? error;

  bool get isEmpty => events.isEmpty && !loading && error == null;
}

class HistoryViewModel extends Notifier<HistoryState> {
  @override
  HistoryState build() {
    final cached = ref.watch(historyRepositoryProvider).cached;
    // Différé après le build : `state` n'existe pas encore à cet instant.
    Future.microtask(refresh);
    // Le cache s'affiche immédiatement : l'écran n'est jamais vide si on a
    // déjà consulté l'historique une fois, même hors ligne.
    return HistoryState(events: cached, loading: true);
  }

  Future<void> refresh() async {
    state = HistoryState(events: state.events, loading: true);
    try {
      final events = await ref.read(historyRepositoryProvider).fetch();
      if (!ref.mounted) return;
      state = HistoryState(events: events);
    } on HistoryException catch (e) {
      if (!ref.mounted) return;
      // On garde les évènements déjà affichés et on signale l'échec à côté.
      state = HistoryState(events: state.events, error: e.message);
    }
  }
}

final historyViewModelProvider =
    NotifierProvider<HistoryViewModel, HistoryState>(HistoryViewModel.new);
