import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';
import 'package:sesame/core/mqtt/mqtt_topics.dart';
import 'package:sesame/features/doorbell/data/doorbell_repository.dart';

import '../../../helpers/fake_mqtt.dart';

void main() {
  const topics = MqttTopics('site_test');
  final receivedAt = DateTime.utc(2026, 10, 19, 22, 30);
  late MockMqttService mqtt;
  late StreamController<MqttInboundMessage> inbound;
  late DoorbellRepository repository;

  setUp(() {
    (:mqtt, :inbound) = fakeMqtt();
    repository = DoorbellRepository(mqtt, topics, clock: () => receivedAt);
  });

  tearDown(() => repository.dispose());

  void publishRing(String payload, {String? topic}) => inbound.add(
    MqttInboundMessage(
      topic: topic ?? topics.doorbellRing,
      payload: payload,
      retained: false,
    ),
  );

  String ringPayload(String ringId, {int ts = 1760731200}) =>
      jsonEncode({'ringId': ringId, 'ts': ts});

  test('une sonnerie est émise sur le flux', () async {
    final rings = repository.watchRings().toList();

    publishRing(ringPayload('ring-1'));
    await pumpEventQueue();
    await repository.dispose();

    expect((await rings).single.ringId, 'ring-1');
  });

  test('ts = 0 : l\'ESP32 n\'avait pas l\'heure, reportedAt est nul', () async {
    final ring = repository.watchRings().first;

    publishRing(ringPayload('ring-1', ts: 0));

    expect((await ring).reportedAt, isNull);
    // L'horloge du téléphone, elle, reste exploitable pour l'affichage.
    expect((await ring).receivedAt, receivedAt);
  });

  test('un doublon QoS 1 ne sonne qu\'une fois', () async {
    final rings = repository.watchRings().toList();

    publishRing(ringPayload('ring-1'));
    publishRing(ringPayload('ring-1'));
    await pumpEventQueue();
    await repository.dispose();

    expect(await rings, hasLength(1));
  });

  test('deux appuis distincts sonnent deux fois', () async {
    final rings = repository.watchRings().toList();

    publishRing(ringPayload('ring-1'));
    publishRing(ringPayload('ring-2'));
    await pumpEventQueue();
    await repository.dispose();

    expect((await rings).map((r) => r.ringId), ['ring-1', 'ring-2']);
  });

  test('un payload invalide est ignoré sans casser le flux', () async {
    final rings = repository.watchRings().toList();

    publishRing('pas du json');
    publishRing(jsonEncode({'ringId': '', 'ts': 1})); // ringId vide
    publishRing(jsonEncode({'ts': 1})); // ringId manquant
    publishRing(ringPayload('ring-1'));
    await pumpEventQueue();
    await repository.dispose();

    expect((await rings).single.ringId, 'ring-1');
  });

  test('un message d\'un autre topic est ignoré', () async {
    final rings = repository.watchRings().toList();

    publishRing(ringPayload('ring-1'), topic: topics.gateState);
    await pumpEventQueue();
    await repository.dispose();

    expect(await rings, isEmpty);
  });
}
