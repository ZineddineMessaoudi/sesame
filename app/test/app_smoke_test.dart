import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/app/app.dart';
import 'package:sesame/core/config/app_config.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';

import 'helpers/fake_mqtt.dart';

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          // Pas de vraie connexion au broker dans un test.
          mqttServiceProvider.overrideWithValue(fakeMqtt().mqtt),
        ],
        child: const SesameApp(),
      ),
    );

    expect(find.text('Sésame'), findsOneWidget);
  });
}
