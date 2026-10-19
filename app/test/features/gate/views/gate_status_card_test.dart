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

  testWidgets(
    'prévient que l\'état peut être dépassé si l\'équipement est hors ligne',
    (tester) async {
      await pumpCard(tester, gate: closed, device: DeviceStatus.offline);

      expect(find.text('Équipement hors ligne'), findsOneWidget);
      expect(find.textContaining('Dernier état connu'), findsOneWidget);
    },
  );
}
