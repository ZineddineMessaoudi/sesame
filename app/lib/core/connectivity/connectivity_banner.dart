import 'package:flutter/material.dart';

import 'connection_notifier.dart';

/// Bandeau non bloquant (§5) : l'écran reste utilisable, avec le dernier état connu.
/// Invisible quand tout va bien.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key, required this.quality});

  final ConnectionQuality quality;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = switch (quality) {
      ConnectionQuality.online => null,
      ConnectionQuality.degraded => (
        Icons.sync_problem,
        'Connexion au portail en cours…',
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      ConnectionQuality.offline => (
        Icons.cloud_off,
        'Hors ligne : dernier état connu affiché.',
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: content == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion:
                  true, // annoncé par le lecteur d'écran à chaque changement
              child: Container(
                width: double.infinity,
                color: content.$3,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // Icône + texte : l'information ne repose jamais sur la couleur seule (§11).
                    Icon(content.$1, color: content.$4),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        content.$2,
                        style: TextStyle(color: content.$4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
