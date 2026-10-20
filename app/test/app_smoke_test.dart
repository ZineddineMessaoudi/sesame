import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/features/auth/data/auth_repository.dart';
import 'package:sesame/app/app.dart';
import 'package:sesame/core/config/app_config.dart';
import 'package:sesame/core/connectivity/network_monitor.dart';
import 'package:sesame/core/mqtt/mqtt_service.dart';
import 'package:sesame/core/storage/local_storage.dart';
import 'package:sesame/features/gate/data/models/gate_command.dart';
import 'package:sesame/features/gate/data/models/gate_snapshot.dart';
import 'package:sesame/features/history/data/models/gate_event.dart';

import 'helpers/fake_mqtt.dart';
import 'helpers/fake_network.dart';
import 'helpers/hive_box.dart';

void main() {
  late MqttService mqtt;

  Future<void> pumpApp(WidgetTester tester, {required AuthUser? user}) async {
    mqtt = fakeMqtt().mqtt;
    final config = AppConfig(
      mqttHost: 'broker.test',
      mqttPort: 8883,
      mqttUsername: 'app',
      mqttPassword: 'secret',
      siteId: 'site_test',
      apiBaseUrl: Uri.parse('http://localhost:1880'),
    );

    // Boxes ouvertes hors de la zone de test « fake async » de testWidgets (accès disque réel).
    final box = (await tester.runAsync(openTestBox<GateSnapshot>))!;
    final outbox = (await tester.runAsync(openTestBox<GateCommand>))!;
    final events = (await tester.runAsync(openTestBox<GateEvent>))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          // Pas de vraie connexion au broker dans un test.
          mqttServiceProvider.overrideWithValue(mqtt),
          localStorageProvider.overrideWithValue(
            LocalStorage(gateState: box, outbox: outbox, events: events),
          ),
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor()),
          authRepositoryProvider.overrideWithValue(_FixedSession(user)),
        ],
        child: const SesameApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets("connecté, l'app démarre sur l'écran du portail", (tester) async {
    await pumpApp(tester, user: const AuthUser(uid: 'u-1'));

    expect(find.byTooltip('Se déconnecter'), findsOneWidget);
  });

  testWidgets("sans session, l'app démarre sur l'écran de connexion", (
    tester,
  ) async {
    await pumpApp(tester, user: null);

    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.byTooltip('Se déconnecter'), findsNothing);
    // Le bug corrigé : déconnecté, l'app ne doit plus rien recevoir par MQTT.
    verify(() => mqtt.allow(false)).called(1);
    verifyNever(mqtt.start);
  });
}

/// Session figée : ni Firebase ni réseau dans un test widget.
class _FixedSession extends AuthRepository {
  _FixedSession(this._user) : super(null);
  final AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;
}
