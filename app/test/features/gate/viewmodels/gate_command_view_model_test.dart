import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/features/auth/data/biometric_repository.dart';
import 'package:sesame/features/gate/data/gate_repository.dart';
import 'package:sesame/features/gate/data/models/gate_command.dart';
import 'package:sesame/features/gate/data/outbox_service.dart';
import 'package:sesame/features/gate/viewmodels/gate_command_view_model.dart';

class MockGateRepository extends Mock implements GateRepository {}

class MockBiometricRepository extends Mock implements BiometricRepository {}

class MockOutboxService extends Mock implements OutboxService {}

void main() {
  late MockGateRepository gate;
  late MockBiometricRepository biometric;
  late MockOutboxService outbox;
  late ProviderContainer container;
  var ids = 0;

  GateCommand commandFor(GateAction action) => GateCommand.create(
    cmdId: 'cmd-${ids++}',
    action: action,
    now: DateTime.utc(2026),
  );

  setUpAll(() {
    registerFallbackValue(GateAction.open);
    registerFallbackValue(commandFor(GateAction.open));
  });

  setUp(() {
    gate = MockGateRepository();
    biometric = MockBiometricRepository();
    when(
      () => gate.newCommand(any()),
    ).thenAnswer((i) => commandFor(i.positionalArguments.first as GateAction));
    when(() => gate.sendCommand(any()))
        .thenAnswer((_) async => CommandOutcome.executed);
    when(() => biometric.confirm(any()))
        .thenAnswer((_) async => IdentityCheck.confirmed);
    outbox = MockOutboxService();
    when(() => outbox.results).thenAnswer((_) => const Stream.empty());
    when(() => outbox.enqueue(any())).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        gateRepositoryProvider.overrideWithValue(gate),
        biometricRepositoryProvider.overrideWithValue(biometric),
        outboxServiceProvider.overrideWithValue(outbox),
      ],
    );
    addTearDown(container.dispose);
  });

  GateCommandViewModel viewModel() =>
      container.read(gateCommandViewModelProvider.notifier);
  CommandUiState state() => container.read(gateCommandViewModelProvider);

  test('ouvrir : biométrie, puis commande, puis résultat', () async {
    await viewModel().request(GateAction.open);

    verifyInOrder([
      () => biometric.confirm(any()),
      () => gate.newCommand(GateAction.open),
      () => gate.sendCommand(any()),
    ]);
    expect(
      state(),
      isA<CommandFinished>().having(
        (s) => s.outcome,
        'outcome',
        CommandOutcome.executed,
      ),
    );
  });

  test('biométrie refusée : aucune commande envoyée', () async {
    when(() => biometric.confirm(any()))
        .thenAnswer((_) async => IdentityCheck.cancelled);

    await viewModel().request(GateAction.open);

    verifyNever(() => gate.newCommand(any()));
    verifyNever(() => gate.sendCommand(any()));
    expect(state(), isA<CommandIdentityRefused>());
  });

  test('hors ligne : la commande est mise en attente, pas perdue', () async {
    when(() => gate.sendCommand(any()))
        .thenAnswer((_) async => CommandOutcome.notSent);

    await viewModel().request(GateAction.close);

    // C'est bien la commande publiée qui est mise en file, avec son cmdId
    // et son TTL d'origine : le renvoi ne repartira pas de zéro (§4).
    final queued = verify(() => outbox.enqueue(captureAny())).captured.single;
    expect((queued as GateCommand).cmdId, isNotEmpty);
    expect(
      state(),
      isA<CommandFinished>().having(
        (s) => s.outcome,
        'outcome',
        CommandOutcome.queued,
      ),
    );
  });

  test('fermer ne demande pas la biométrie', () async {
    await viewModel().request(GateAction.close);

    verifyNever(() => biometric.confirm(any()));
    verify(() => gate.sendCommand(any())).called(1);
  });

  test('affiche « demandée » pendant l\'attente de l\'ack', () async {
    final ack = Completer<CommandOutcome>();
    when(() => gate.sendCommand(any())).thenAnswer((_) => ack.future);

    final pending = viewModel().request(GateAction.close);
    await pumpEventQueue();
    expect(state(), isA<CommandSending>());

    ack.complete(CommandOutcome.noResponse);
    await pending;
    expect(
      state(),
      isA<CommandFinished>().having(
        (s) => s.outcome,
        'outcome',
        CommandOutcome.noResponse,
      ),
    );
  });

  test('un double appui n\'envoie qu\'une commande', () async {
    final ack = Completer<CommandOutcome>();
    when(() => gate.sendCommand(any())).thenAnswer((_) => ack.future);

    final first = viewModel().request(GateAction.close);
    await pumpEventQueue();
    await viewModel().request(GateAction.close);
    ack.complete(CommandOutcome.executed);
    await first;

    verify(() => gate.sendCommand(any())).called(1);
  });

  test(
    'réessayer crée une nouvelle commande et redemande la biométrie',
    () async {
      when(() => gate.sendCommand(any()))
          .thenAnswer((_) async => CommandOutcome.noResponse);
      final sent = <String>[];
      when(() => gate.sendCommand(any())).thenAnswer((i) async {
        sent.add((i.positionalArguments.first as GateCommand).cmdId);
        return CommandOutcome.noResponse;
      });

      await viewModel().request(GateAction.open);
      await viewModel().retry(GateAction.open);

      verify(() => biometric.confirm(any())).called(2);
      expect(sent, hasLength(2));
      expect(sent.toSet(), hasLength(2)); // deux cmdId différents
    },
  );
}
