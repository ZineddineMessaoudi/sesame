import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';

class MockMqttService extends Mock implements MqttService {}

/// MqttService simulé : les tests poussent les messages dans [inbound], aucun réseau.
({MockMqttService mqtt, StreamController<MqttInboundMessage> inbound})
fakeMqtt() {
  final inbound = StreamController<MqttInboundMessage>.broadcast();
  final mqtt = MockMqttService();
  when(() => mqtt.messages).thenAnswer((_) => inbound.stream);
  when(() => mqtt.start()).thenAnswer((_) async {});
  when(() => mqtt.dispose()).thenAnswer((_) async {});
  return (mqtt: mqtt, inbound: inbound);
}
