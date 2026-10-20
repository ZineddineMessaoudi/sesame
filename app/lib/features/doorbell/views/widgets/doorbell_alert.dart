import 'dart:async';

import 'package:flutter/material.dart';

import '../../../gate/views/widgets/freshness_label.dart' show formatAge;
import '../../data/models/doorbell_ring.dart';

/// Bandeau affiché quand quelqu'un vient de sonner.
///
/// Stateful uniquement pour se redessiner chaque seconde : l'âge de la sonnerie
/// avance même si plus rien n'arrive, comme pour [FreshnessLabel].
class DoorbellAlert extends StatefulWidget {
  const DoorbellAlert({
    super.key,
    required this.ring,
    required this.onDismiss,
    this.onView,
    this.clock = DateTime.now,
  });

  final DoorbellRing ring;
  final VoidCallback onDismiss;

  /// Ouvre la caméra. Facultatif : sans caméra, l'alerte reste utile seule.
  final VoidCallback? onView;
  final DateTime Function() clock; // injectable pour les tests

  @override
  State<DoorbellAlert> createState() => _DoorbellAlertState();
}

class _DoorbellAlertState extends State<DoorbellAlert> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // receivedAt (horloge du téléphone) et non reportedAt : l'ESP32 peut ne pas
    // avoir l'heure, et l'âge affiché ne doit pas dépendre de son horloge.
    final age = widget.clock().difference(widget.ring.receivedAt);

    return Card(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Icône *et* texte : l'information ne repose jamais sur la couleur seule (§11).
            Icon(Icons.notifications_active, color: colors.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              // liveRegion : une nouvelle sonnerie est annoncée par le lecteur d'écran.
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quelqu\'un a sonné',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: colors.onTertiaryContainer),
                    ),
                    Text(
                      'Il y a ${formatAge(age)}',
                      style: TextStyle(color: colors.onTertiaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.onView case final onView?)
              IconButton(
                onPressed: onView,
                icon: const Icon(Icons.videocam),
                color: colors.onTertiaryContainer,
                tooltip: 'Voir qui est là',
              ),
            // IconButton : 48 dp de cible tactile par défaut (§11).
            IconButton(
              onPressed: widget.onDismiss,
              icon: const Icon(Icons.close),
              color: colors.onTertiaryContainer,
              tooltip: 'Masquer la sonnerie',
            ),
          ],
        ),
      ),
    );
  }
}
