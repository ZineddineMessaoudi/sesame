import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/data_freshness.dart';

/// « En direct » ou « Mis à jour il y a … » (Age of Data, §5).
///
/// Stateful uniquement pour se redessiner chaque seconde : l'âge avance même
/// quand aucune donnée n'arrive (c'est justement le cas hors ligne).
class FreshnessLabel extends StatefulWidget {
  const FreshnessLabel({
    super.key,
    required this.isLive,
    required this.confirmedAt,
    this.clock = DateTime.now,
  });

  final bool isLive;
  final DateTime? confirmedAt;
  final DateTime Function() clock; // injectable pour les tests

  @override
  State<FreshnessLabel> createState() => _FreshnessLabelState();
}

class _FreshnessLabelState extends State<FreshnessLabel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.isLive) setState(() {}); // en direct, rien à recompter
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmedAt = widget.confirmedAt;
    if (confirmedAt == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final age = widget.clock().difference(confirmedAt);
    final (icon, text, color) = widget.isLive
        ? (Icons.sensors, 'En direct', colors.primary)
        : switch (DataFreshness.ofAge(age)) {
            DataFreshness.live => (
              Icons.check_circle_outline,
              'Mis à jour il y a ${formatAge(age)}',
              colors.primary,
            ),
            DataFreshness.stale => (
              Icons.schedule,
              'Mis à jour il y a ${formatAge(age)}',
              colors.tertiary,
            ),
            DataFreshness.expired => (
              Icons.warning_amber,
              'Mis à jour il y a ${formatAge(age)} : l\'état a pu changer',
              colors.error,
            ),
          };

    // Pas de liveRegion : le texte change chaque seconde, le lecteur d'écran
    // l'annoncerait en boucle. Il est lu quand l'utilisateur arrive dessus.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// « 12 s », « 3 min », « 2 h », « 4 j » : arrondi vers le bas, sans fausse précision.
String formatAge(Duration age) {
  if (age.isNegative) return '0 s'; // horloge du téléphone recalée en arrière
  if (age.inMinutes < 1) return '${age.inSeconds} s';
  if (age.inHours < 1) return '${age.inMinutes} min';
  if (age.inDays < 1) return '${age.inHours} h';
  return '${age.inDays} j';
}
