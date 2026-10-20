import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/core/config/app_config.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';

void main() {
  test('sans session, start() ne tente aucune connexion', () async {
    final service = MqttService(
      AppConfig(
        // Hôte injoignable : si start() tentait de se connecter, le test
        // resterait bloqué dans la boucle de reconnexion.
        mqttHost: 'broker.invalid',
        mqttPort: 8883,
        mqttUsername: 'app',
        mqttPassword: 'secret',
        siteId: 'site_test',
        apiBaseUrl: Uri.parse('http://localhost:1880'),
      ),
    );
    addTearDown(service.dispose);

    service.allow(false);
    await service.start();

    expect(service.sessionState, MqttSessionState.disconnected);
  });
}
