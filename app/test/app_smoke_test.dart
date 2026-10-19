import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/app/app.dart';
import 'package:sesame/core/config/app_config.dart';
import 'package:sesame/core/connectivity/network_monitor.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';
import 'package:sesame/core/storage/local_storage.dart';
import 'package:sesame/features/gate/data/models/gate_snapshot.dart';

import 'helpers/fake_mqtt.dart';
import 'helpers/fake_network.dart';
import 'helpers/hive_box.dart';

void main() {
  testWidgets('l\'app démarre sur l\'écran du portail', (tester) async {
    final config = AppConfig(
      mqttHost: 'broker.test',
      mqttPort: 8883,
      mqttUsername: 'app',
      mqttPassword: 'secret',
      siteId: 'site_test',
      apiBaseUrl: Uri.parse('http://localhost:1880'),
    );

    // Box ouverte hors de la zone de test « fake async » de testWidgets (accès disque réel).
    final box = (await tester.runAsync(openTestBox<GateSnapshot>))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          // Pas de vraie connexion au broker dans un test.
          mqttServiceProvider.overrideWithValue(fakeMqtt().mqtt),
          localStorageProvider.overrideWithValue(LocalStorage(gateState: box)),
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor()),
        ],
        child: const SesameApp(),
      ),
    );

    expect(find.text('Sésame'), findsOneWidget);
  });
}
