import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/gate/data/gate_repository.dart';
import 'package:sesame/features/gate/data/models/gate_command.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';
import 'package:sesame/features/gate/viewmodels/gate_command_view_model.dart';
import 'package:sesame/features/gate/views/widgets/gate_command_panel.dart';

void main() {
  final commands = <String>[];

  Future<void> pumpPanel(
    WidgetTester tester, {
    GateStatus? status = GateStatus.closed,
    CommandUiState state = const CommandIdle(),
  }) {
    commands.clear();
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GateCommandPanel(
            gateStatus: status,
            commandState: state,
            onCommand: (a) => commands.add('command ${a.name}'),
            onRetry: (a) => commands.add('retry ${a.name}'),
          ),
        ),
      ),
    );
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
          )
          .onPressed !=
      null;

  testWidgets('portail fermé : Ouvrir actif, Fermer inactif', (tester) async {
    await pumpPanel(tester);

    expect(enabled(tester, 'Ouvrir le portail'), isTrue);
    expect(enabled(tester, 'Fermer le portail'), isFalse);

    await tester.tap(find.text('Ouvrir le portail'));
    expect(commands, ['command open']);
  });

  testWidgets('état inconnu : aucune commande possible', (tester) async {
    await pumpPanel(tester, status: null);

    expect(enabled(tester, 'Ouvrir le portail'), isFalse);
    expect(enabled(tester, 'Fermer le portail'), isFalse);
  });

  testWidgets('en attente : boutons inactifs et « Ouverture demandée… »', (
    tester,
  ) async {
    await pumpPanel(tester, state: const CommandSending(GateAction.open));

    expect(enabled(tester, 'Ouvrir le portail'), isFalse);
    expect(find.text('Ouverture demandée…'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('pas de réponse : message et Réessayer', (tester) async {
    await pumpPanel(
      tester,
      state: const CommandFinished(GateAction.open, CommandOutcome.noResponse),
    );

    expect(find.text('Pas de réponse du portail.'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    expect(commands, ['retry open']);
  });

  testWidgets('succès : pas de bouton Réessayer', (tester) async {
    await pumpPanel(
      tester,
      status: GateStatus.opening,
      state: const CommandFinished(GateAction.open, CommandOutcome.executed),
    );

    expect(find.text('Commande reçue par le portail.'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });
}
