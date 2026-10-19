import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';
import 'package:sesame/core/mqtt/mqtt_topics.dart';
import 'package:sesame/features/gate/data/gate_repository.dart';
import 'package:sesame/features/gate/data/models/device_status.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';

import '../../../helpers/fake_mqtt.dart';

void main() {
  const topics = MqttTopics('site_test');
  late StreamController<MqttInboundMessage> inbound;
  late MockMqttService mqtt;
  late GateRepository repository;

  setUp(() {
    (:mqtt, :inbound) = fakeMqtt();
    repository = GateRepository(mqtt, topics);
  });

  tearDown(() => repository.dispose());

  void state(String status, int seq, {bool retained = false}) => inbound.add(
    MqttInboundMessage(
      topic: topics.gateState,
      payload: '{"state":"$status","ts":1792391878,"seq":$seq}',
      retained: retained,
    ),
  );

  void status(String payload) => inbound.add(
    MqttInboundMessage(
      topic: topics.deviceStatus,
      payload: payload,
      retained: false,
    ),
  );

  Future<List<int>> seqsOf(void Function() publish) async {
    final seqs = <int>[];
    final sub = repository.watchGateState().listen((s) => seqs.add(s.seq));
    publish();
    await pumpEventQueue();
    await sub.cancel();
    return seqs;
  }

  test('s\'abonne aux topics du portail et de l\'équipement', () {
    verify(() => mqtt.subscribe(topics.gateState)).called(1);
    verify(() => mqtt.subscribe(topics.deviceStatus)).called(1);
  });

  test('ignore les doublons QoS 1 et les messages en retard', () async {
    final seqs = await seqsOf(() {
      state('opening', 2);
      state('opening', 2); // doublon
      state('open', 3);
      state('closed', 1); // en retard
    });

    expect(seqs, [2, 3]);
  });

  test(
    'accepte toujours l\'état retenu, même avec un seq plus petit',
    () async {
      final seqs = await seqsOf(() {
        state('open', 9);
        state(
          'closed',
          1,
          retained: true,
        ); // ESP32 redémarré pendant une déconnexion
        state('opening', 2);
      });

      expect(seqs, [9, 1, 2]);
    },
  );

  test('repart de zéro quand l\'ESP32 republie online', () async {
    final seqs = await seqsOf(() {
      state('open', 9);
      status('online'); // redémarrage : seq repart à 0
      state('closed', 1);
    });

    expect(seqs, [9, 1]);
  });

  test('ignore un payload invalide sans casser le flux', () async {
    final received = <GateState>[];
    final sub = repository.watchGateState().listen(received.add);
    inbound.add(
      MqttInboundMessage(
        topic: topics.gateState,
        payload: '{oops',
        retained: false,
      ),
    );
    state('closed', 1);
    await pumpEventQueue();
    await sub.cancel();

    expect(received.map((s) => s.status), [GateStatus.closed]);
  });

  test('publie le statut de l\'équipement', () async {
    final received = <DeviceStatus>[];
    final sub = repository.watchDeviceStatus().listen(received.add);
    status('online');
    status('offline');
    await pumpEventQueue();
    await sub.cancel();

    expect(received, [DeviceStatus.online, DeviceStatus.offline]);
  });
}
