import 'package:flutter/material.dart';

import '../../data/models/device_status.dart';
import '../../data/models/gate_state.dart';

/// Carte d'état du portail : widget « bête », il affiche ce qu'on lui donne.
/// L'état ne repose jamais sur la couleur seule : icône + texte (§11).
class GateStatusCard extends StatelessWidget {
  const GateStatusCard({super.key, required this.gate, required this.device});

  final GateState? gate;
  final DeviceStatus? device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gate = this.gate;
    final (icon, label) = gate == null
        ? (Icons.hourglass_empty, 'Connexion au portail…')
        : _describe(gate.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lu d'un seul tenant par TalkBack / VoiceOver, mis à jour à chaque changement.
            Semantics(
              liveRegion: true,
              label: 'État du portail : $label',
              excludeSemantics: true,
              child: Column(
                children: [
                  if (gate == null)
                    const SizedBox.square(
                      dimension: 64,
                      child: CircularProgressIndicator(),
                    )
                  else
                    Icon(icon, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DeviceStatusChip(device: device),
            if (device == DeviceStatus.offline && gate != null) ...[
              const SizedBox(height: 8),
              Text(
                'Dernier état connu : il peut avoir changé depuis.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static (IconData, String) _describe(GateStatus status) => switch (status) {
    GateStatus.closed => (Icons.lock_outline, 'Fermé'),
    GateStatus.open => (Icons.lock_open, 'Ouvert'),
    GateStatus.opening => (Icons.sync, 'Ouverture en cours…'),
    GateStatus.closing => (Icons.sync, 'Fermeture en cours…'),
  };
}

class _DeviceStatusChip extends StatelessWidget {
  const _DeviceStatusChip({required this.device});

  final DeviceStatus? device;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (device) {
      DeviceStatus.online => (
        Icons.wifi,
        'Équipement en ligne',
        colors.primary,
      ),
      DeviceStatus.offline => (
        Icons.wifi_off,
        'Équipement hors ligne',
        colors.error,
      ),
      null => (
        Icons.help_outline,
        'Statut de l\'équipement inconnu',
        colors.outline,
      ),
    };
    return Chip(
      avatar: Icon(icon, color: color),
      label: Text(label),
    );
  }
}
