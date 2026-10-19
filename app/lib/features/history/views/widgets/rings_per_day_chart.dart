import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/models/gate_event.dart';

/// Sonneries par jour sur les [days] derniers jours.
///
/// On ne compte que les sonneries : les changements d'état sont bien plus
/// nombreux et noieraient la seule information utile à l'utilisateur, à savoir
/// combien de visiteurs se sont présentés.
class RingsPerDayChart extends StatelessWidget {
  const RingsPerDayChart({
    super.key,
    required this.events,
    this.days = 7,
    this.clock = DateTime.now,
  });

  final List<GateEvent> events;
  final int days;
  final DateTime Function() clock; // injectable pour les tests

  static const _jours = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  /// Nombre de sonneries par jour, du plus ancien au plus récent.
  List<({DateTime day, int count})> _countPerDay() {
    final today = DateUtils.dateOnly(clock().toLocal());
    return [
      for (var i = days - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          count: events
              .where(
                (e) =>
                    e.type == GateEventType.ring &&
                    DateUtils.isSameDay(
                      e.ts.toLocal(),
                      today.subtract(Duration(days: i)),
                    ),
              )
              .length,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = _countPerDay();
    final total = data.fold(0, (sum, d) => sum + d.count);
    // Échelle minimale à 1 : sans elle, une semaine sans sonnerie donnerait un
    // graphique écrasé et illisible.
    final maxCount = data.fold(0, (m, d) => d.count > m ? d.count : m);

    return Semantics(
      // Le graphique n'est pas lisible par un lecteur d'écran : on en donne
      // l'essentiel en texte (§11).
      label: 'Graphique des sonneries : $total sur les $days derniers jours',
      excludeSemantics: true,
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: (maxCount < 1 ? 1 : maxCount).toDouble(),
            minY: 0,
            barGroups: [
              for (final (index, d) in data.indexed)
                BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: d.count.toDouble(),
                      color: colors.primary,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= data.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _jours[data[index].day.weekday - 1],
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
