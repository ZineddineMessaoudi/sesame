import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/connectivity/connection_notifier.dart';
import 'package:sesame/core/connectivity/network_monitor.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';

import '../../helpers/fake_mqtt.dart';
import '../../helpers/fake_network.dart';

void main() {
  late MockMqttService mqtt;
  late StreamController<MqttSessionState> sessions;
  late FakeNetworkMonitor network;
  late ProviderContainer container;
  var session = MqttSessionState.connecting;

  setUp(() {
    mqtt = fakeMqtt().mqtt;
    sessions = StreamController<MqttSessionState>.broadcast();
    session = MqttSessionState.connecting;
    when(() => mqtt.sessionStates).thenAnswer((_) => sessions.stream);
    when(() => mqtt.sessionState).thenAnswer((_) => session);
    network = FakeNetworkMonitor();
    container = ProviderContainer(
      overrides: [
        mqttServiceProvider.overrideWithValue(mqtt),
        networkMonitorProvider.overrideWithValue(network),
      ],
    );
    addTearDown(container.dispose);
    container.listen(connectionProvider, (_, _) {}); // garde le notifier en vie
  });

  ConnectionQuality quality() => container.read(connectionProvider);

  /// Laisse passer le throttle (1 s) et les microtâches.
  Future<void> settle() => Future<void>.delayed(
    ConnectionNotifier.throttle + const Duration(milliseconds: 50),
  );

  void setSession(MqttSessionState next) {
    session = next;
    sessions.add(next);
  }

  test('réseau présent mais MQTT pas encore connecté : degraded', () async {
    await settle();
    expect(quality(), ConnectionQuality.degraded);
  });

  test('réseau présent et session MQTT ouverte : online', () async {
    setSession(MqttSessionState.connected);
    await settle();
    expect(quality(), ConnectionQuality.online);
  });

  test('aucun réseau : offline, quel que soit l\'état MQTT', () async {
    network.changesController.add(false);
    setSession(MqttSessionState.disconnected);
    await settle();
    expect(quality(), ConnectionQuality.offline);
  });

  test('le retour du réseau relance MQTT sans attendre le backoff', () async {
    network.changesController.add(false);
    await settle();
    verifyNever(mqtt.retryNow);

    network.changesController.add(true);
    await settle();
    verify(mqtt.retryNow).called(1);
    expect(quality(), ConnectionQuality.degraded); // reconnexion en cours
  });

  test(
    'une rafale de changements est lissée, la dernière valeur gagne',
    () async {
      await settle();
      network.changesController
        ..add(false)
        ..add(true)
        ..add(false);
      await settle();
      expect(quality(), ConnectionQuality.offline);
    },
  );
}
