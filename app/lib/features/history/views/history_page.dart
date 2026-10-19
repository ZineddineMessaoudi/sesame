import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gate/data/models/gate_state.dart';
import '../../gate/views/widgets/freshness_label.dart' show formatAge;
import '../data/models/gate_event.dart';
import '../viewmodels/history_view_model.dart';
import 'widgets/rings_per_day_chart.dart';

/// Écran historique : observe le ViewModel et ne décide de rien lui-même.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyViewModelProvider);
    final viewModel = ref.read(historyViewModelProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            onPressed: state.loading ? null : viewModel.refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: viewModel.refresh,
          child: Column(
            children: [
              if (state.loading) const LinearProgressIndicator(),
              // L'erreur s'affiche au-dessus de la liste, qui reste visible :
              // le cache garde sa valeur même quand le serveur ne répond pas.
              if (state.error != null) _ErrorBanner(message: state.error!),
              Expanded(
                child: state.isEmpty
                    ? const _Empty()
                    : _Content(events: state.events),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.events});

  final List<GateEvent> events;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Toujours défilable, sinon le geste de rafraîchissement ne part pas
      // quand la liste est courte.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: events.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: RingsPerDayChart(events: events),
          );
        }
        return _EventTile(event: events[index - 1]);
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final GateEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Icône *et* libellé : l'information ne repose jamais sur la couleur (§11).
    final (icon, label, color) = switch (event.type) {
      GateEventType.ring => (
        Icons.notifications_active,
        'Quelqu\'un a sonné',
        colors.tertiary,
      ),
      GateEventType.state => switch (event.status) {
        GateStatus.open => (Icons.lock_open, 'Portail ouvert', colors.primary),
        GateStatus.closed => (Icons.lock, 'Portail fermé', colors.primary),
        GateStatus.opening => (
          Icons.arrow_upward,
          'Ouverture en cours',
          colors.secondary,
        ),
        GateStatus.closing => (
          Icons.arrow_downward,
          'Fermeture en cours',
          colors.secondary,
        ),
        null => (Icons.help_outline, 'État inconnu', colors.outline),
      },
    };

    final age = DateTime.now().difference(event.ts);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text('Il y a ${formatAge(age)}'),
      dense: false,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                '$message Historique affiché depuis le cache.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView et non Center : le geste de rafraîchissement doit rester
      // possible sur un écran vide.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.history,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        const Center(child: Text('Aucun évènement enregistré.')),
      ],
    );
  }
}
