import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/doorbell/data/models/doorbell_ring.dart';
import 'package:sesame/features/doorbell/views/widgets/doorbell_alert.dart';

void main() {
  final receivedAt = DateTime.utc(2026, 10, 19, 22, 30);
  final ring = DoorbellRing(
    ringId: 'ring-1',
    reportedAt: null,
    receivedAt: receivedAt,
  );

  Future<void> pumpAlert(
    WidgetTester tester, {
    required Duration age,
    VoidCallback? onDismiss,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoorbellAlert(
            ring: ring,
            onDismiss: onDismiss ?? () {},
            clock: () => receivedAt.add(age),
          ),
        ),
      ),
    );
  }

  /// Démonte le widget : son minuteur d'une seconde doit être annulé,
  /// sinon le test échoue sur un timer encore actif.
  Future<void> dispose(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('annonce la sonnerie et son âge', (tester) async {
    await pumpAlert(tester, age: const Duration(seconds: 42));

    expect(find.text('Quelqu\'un a sonné'), findsOneWidget);
    expect(find.text('Il y a 42 s'), findsOneWidget);
    // Icône en plus du texte : pas d'information portée par la seule couleur (§11).
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);

    await dispose(tester);
  });

  testWidgets('l\'âge passe en minutes au-delà d\'une minute', (tester) async {
    await pumpAlert(tester, age: const Duration(minutes: 3, seconds: 20));

    expect(find.text('Il y a 3 min'), findsOneWidget);

    await dispose(tester);
  });

  testWidgets('le bouton Masquer prévient l\'appelant', (tester) async {
    var dismissed = false;
    await pumpAlert(
      tester,
      age: Duration.zero,
      onDismiss: () => dismissed = true,
    );

    await tester.tap(find.byIcon(Icons.close));

    expect(dismissed, isTrue);
    await dispose(tester);
  });
}
