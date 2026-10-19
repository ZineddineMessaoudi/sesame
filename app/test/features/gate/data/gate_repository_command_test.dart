import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';
import 'package:sesame/core/mqtt/mqtt_topics.dart';
import 'package:sesame/features/gate/data/gate_repository.dart';
import 'package:sesame/features/gate/data/models/gate_command.dart';

import '../../../helpers/fake_mqtt.dart';

void main() {
  const topics = MqttTopics('site_test');
  late StreamController<MqttInboundMessage> inbound;
  late MockMqttService mqtt;
  late GateRepository repository;
  var ids = 0;

  setUp(() {
    (:mqtt, :inbound) = fakeMqtt();
    repository = GateRepository(
      mqtt,
      topics,
      clock: () => DateTime.utc(2026, 10, 19, 7, 30),
      newId: () => 'cmd-${ids++}',
      ackTimeout: const Duration(milliseconds: 50),
    );
  });

  tearDown(() => repository.dispose());

  /// L'ESP32 simulé répond `result` à toute commande publiée.
  void espRepliesWith(String result, {String? cmdId}) {
    when(() => mqtt.publish(topics.gateCmd, any())).thenAnswer((invocation) {
      final payload =
          jsonDecode(invocation.positionalArguments[1] as String) as Map;
      inbound.add(
        MqttInboundMessage(
          topic: topics.gateAck,
          payload: jsonEncode({
            'cmdId': cmdId ?? payload['cmdId'],
            'result': result,
            'ts': 1,
          }),
          retained: false,
        ),
      );
      return true;
    });
  }

  test('newCommand crée un cmdId neuf à chaque appel', () {
    final a = repository.newCommand(GateAction.open);
    final b = repository.newCommand(GateAction.open);

    expect(a.cmdId, isNot(b.cmdId));
  });

  test('publie le payload sur gate/cmd', () async {
    espRepliesWith('accepted');
    final command = repository.newCommand(GateAction.open);

    await repository.sendCommand(command);

    verify(() => mqtt.publish(topics.gateCmd, command.toPayload())).called(1);
  });

  for (final (result, outcome) in [
    ('accepted', CommandOutcome.executed),
    ('duplicate', CommandOutcome.executed), // §4 : duplicate = succès
    ('rejected_expired', CommandOutcome.rejectedExpired),
    ('rejected_no_time', CommandOutcome.rejectedNoTime),
  ]) {
    test('ack $result -> $outcome', () async {
      espRepliesWith(result);

      expect(
        await repository.sendCommand(repository.newCommand(GateAction.open)),
        outcome,
      );
    });
  }

  test('ignore l\'ack d\'une autre commande et finit en noResponse', () async {
    espRepliesWith('accepted', cmdId: 'autre-commande');

    expect(
      await repository.sendCommand(repository.newCommand(GateAction.open)),
      CommandOutcome.noResponse,
    );
  });

  test('sans ack dans le délai : noResponse', () async {
    expect(
      await repository.sendCommand(repository.newCommand(GateAction.open)),
      CommandOutcome.noResponse,
    );
  });

  test('sans session MQTT : notSent, rien n\'est publié en douce', () async {
    when(() => mqtt.publish(any(), any())).thenReturn(false);

    expect(
      await repository.sendCommand(repository.newCommand(GateAction.open)),
      CommandOutcome.notSent,
    );
  });
}
