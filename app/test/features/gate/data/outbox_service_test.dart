import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';
import 'package:sesame/features/gate/data/gate_repository.dart';
import 'package:sesame/features/gate/data/models/gate_command.dart';
import 'package:sesame/features/gate/data/outbox_service.dart';

import '../../../helpers/hive_box.dart';

void main() {
  late Box<GateCommand> box;
  late OutboxService outbox;
  late List<GateCommand> published;
  late DateTime now;
  late CommandOutcome reply;

  /// Commande émise il y a [age] : au-delà du TTL de 60 s, elle est périmée.
  GateCommand command(String id, {Duration age = Duration.zero}) =>
      GateCommand.create(
        cmdId: id,
        action: GateAction.open,
        now: now.subtract(age),
      );

  setUp(() async {
    now = DateTime.utc(2026, 10, 19, 22);
    published = [];
    reply = CommandOutcome.executed;
    box = await openTestBox<GateCommand>();
    outbox = OutboxService(box, (c) async {
      published.add(c);
      return reply;
    }, clock: () => now);
  });

  tearDown(() => outbox.dispose());

  test('une commande mise en attente est persistée', () async {
    await outbox.enqueue(command('cmd-1'));

    expect(outbox.pending.single.cmdId, 'cmd-1');
    expect(published, isEmpty); // enqueue ne publie rien
  });

  test('flushQueue publie dans l\'ordre d\'émission (FIFO)', () async {
    for (final id in ['cmd-1', 'cmd-2', 'cmd-3']) {
      await outbox.enqueue(command(id));
    }

    await outbox.flushQueue();

    expect(published.map((c) => c.cmdId), ['cmd-1', 'cmd-2', 'cmd-3']);
    expect(outbox.pending, isEmpty);
  });

  test('une commande périmée est abandonnée, jamais publiée', () async {
    await outbox.enqueue(
      command('cmd-vieille', age: const Duration(seconds: 61)),
    );

    final results = await outbox.flushQueue();

    expect(published, isEmpty);
    expect(results.single.outcome, CommandOutcome.expiredUnsent);
    expect(outbox.pending, isEmpty);
  });

  test('une périmée n\'empêche pas la suivante de partir', () async {
    await outbox.enqueue(
      command('cmd-vieille', age: const Duration(seconds: 61)),
    );
    await outbox.enqueue(command('cmd-fraiche'));

    final results = await outbox.flushQueue();

    expect(published.single.cmdId, 'cmd-fraiche');
    expect(results.map((r) => r.outcome), [
      CommandOutcome.expiredUnsent,
      CommandOutcome.executed,
    ]);
  });

  test('un renvoi garde le même cmdId et le même TTL (§4)', () async {
    final original = command('cmd-1');
    await outbox.enqueue(original);

    now = now.add(const Duration(seconds: 30)); // reconnexion 30 s plus tard
    await outbox.flushQueue();

    final resent = published.single;
    expect(resent.cmdId, original.cmdId);
    expect(resent.issuedAt, original.issuedAt);
    // Le point crucial : l'échéance n'a pas été repoussée.
    expect(resent.expiresAt, original.expiresAt);
  });

  test('toujours hors ligne : la file est conservée dans l\'ordre', () async {
    reply = CommandOutcome.notSent;
    await outbox.enqueue(command('cmd-1'));
    await outbox.enqueue(command('cmd-2'));

    await outbox.flushQueue();

    // On s'arrête à la première qui ne part pas : publier cmd-2 avant cmd-1
    // casserait l'ordre d'émission.
    expect(published.map((c) => c.cmdId), ['cmd-1']);
    expect(outbox.pending.map((c) => c.cmdId), ['cmd-1', 'cmd-2']);
  });

  test('sans ack, la commande sort quand même de la file', () async {
    reply = CommandOutcome.noResponse;
    await outbox.enqueue(command('cmd-1'));

    await outbox.flushQueue();

    // Elle a bien été publiée : la rejouer ne ferait qu'un doublon,
    // c'est gate/state qui tranchera l'affichage.
    expect(outbox.pending, isEmpty);
  });

  test('une commande rejouée est annoncée sur results', () async {
    await outbox.enqueue(
      command('cmd-vieille', age: const Duration(seconds: 61)),
    );
    final announced = outbox.results.first;

    await outbox.flushQueue();

    expect((await announced).outcome, CommandOutcome.expiredUnsent);
  });

  group('déclenchement sur la session MQTT', () {
    late StreamController<MqttSessionState> sessions;
    late OutboxService service;

    OutboxService build({Future<CommandOutcome> Function(GateCommand)? send}) =>
        service = OutboxService(
          box,
          send ??
              (c) async {
                published.add(c);
                return reply;
              },
          sessionStates: sessions.stream,
          clock: () => now,
        );

    setUp(() => sessions = StreamController<MqttSessionState>());
    tearDown(() async {
      await service.dispose();
      await sessions.close();
    });

    test('la file part à l\'ouverture de la session', () async {
      build();
      await service.enqueue(command('cmd-1'));

      sessions.add(MqttSessionState.connected);
      await pumpEventQueue();

      expect(published.map((c) => c.cmdId), ['cmd-1']);
    });

    test('ni connecting ni disconnected ne déclenchent le flush', () async {
      build();
      await service.enqueue(command('cmd-1'));

      sessions
        ..add(MqttSessionState.connecting)
        ..add(MqttSessionState.disconnected);
      await pumpEventQueue();

      expect(published, isEmpty);
      expect(service.pending, hasLength(1));
    });

    test('deux connexions rapprochées ne publient pas deux fois', () async {
      // Envoi bloqué : la seconde connexion tombe pendant le premier flush.
      final inFlight = Completer<CommandOutcome>();
      build(
        send: (c) {
          published.add(c);
          return inFlight.future;
        },
      );
      await service.enqueue(command('cmd-1'));

      sessions.add(MqttSessionState.connected);
      await pumpEventQueue();
      sessions.add(MqttSessionState.connected);
      await pumpEventQueue();
      inFlight.complete(CommandOutcome.executed);
      await pumpEventQueue();

      expect(published, hasLength(1));
    });
  });
}
