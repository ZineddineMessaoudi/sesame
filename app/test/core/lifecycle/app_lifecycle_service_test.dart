import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/lifecycle/app_lifecycle_service.dart';

import '../../helpers/fake_mqtt.dart';

void main() {
  testWidgets('coupe MQTT en arrière-plan et le relance au retour', (
    tester,
  ) async {
    final (:mqtt, inbound: _) = fakeMqtt();
    final service = AppLifecycleService(mqtt);
    addTearDown(service.dispose);

    // Passage en arrière-plan : resumed → inactive → hidden → paused.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    verify(mqtt.stop).called(1);
    verifyNever(mqtt.start);

    // Retour au premier plan : paused → hidden → inactive → resumed.
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    verify(mqtt.start).called(1);
  });

  testWidgets('une boîte de dialogue système (inactive) ne coupe pas MQTT', (
    tester,
  ) async {
    final (:mqtt, inbound: _) = fakeMqtt();
    final service = AppLifecycleService(mqtt);
    addTearDown(service.dispose);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    verifyNever(mqtt.stop);
  });
}
