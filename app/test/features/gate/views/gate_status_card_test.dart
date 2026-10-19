import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/gate/data/models/device_status.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';
import 'package:sesame/features/gate/views/widgets/gate_status_card.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    GateState? gate,
    DeviceStatus? device,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GateStatusCard(gate: gate, device: device),
      ),
    ),
  );

  final closed = GateState(
    status: GateStatus.closed,
    reportedAt: DateTime.utc(2026),
    seq: 1,
  );

  testWidgets('affiche un chargement tant qu\'aucun état n\'est reçu', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Connexion au portail…'), findsOneWidget);
  });

  testWidgets(
    'affiche l\'état avec icône et texte, lu par le lecteur d\'écran',
    (tester) async {
      await pumpCard(tester, gate: closed, device: DeviceStatus.online);

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.bySemanticsLabel('État du portail : Fermé'), findsOneWidget);
      expect(find.text('Équipement en ligne'), findsOneWidget);
    },
  );

  final now = DateTime.utc(2026, 10, 19, 10);
  Future<void> pumpFresh(
    WidgetTester tester, {
    required bool live,
    required Duration age,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GateStatusCard(
          gate: closed,
          device: live ? DeviceStatus.online : DeviceStatus.offline,
          isLive: live,
          confirmedAt: now.subtract(age),
          clock: () => now,
        ),
      ),
    ),
  );

  testWidgets('en direct : « En direct », même si l\'état date de longtemps', (
    tester,
  ) async {
    await pumpFresh(tester, live: true, age: const Duration(hours: 3));

    expect(find.text('En direct'), findsOneWidget);
  });

  testWidgets('hors direct, récent : âge en secondes', (tester) async {
    await pumpFresh(tester, live: false, age: const Duration(seconds: 12));

    expect(find.text('Mis à jour il y a 12 s'), findsOneWidget);
    expect(find.text('Équipement hors ligne'), findsOneWidget);
  });

  testWidgets('hors direct, ancien : avertissement explicite (Expired)', (
    tester,
  ) async {
    await pumpFresh(tester, live: false, age: const Duration(minutes: 7));

    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(
      find.textContaining('il y a 7 min : l\'état a pu changer'),
      findsOneWidget,
    );
  });
}
