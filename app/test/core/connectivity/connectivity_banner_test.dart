import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/core/connectivity/connection_notifier.dart';
import 'package:sesame/core/connectivity/connectivity_banner.dart';

void main() {
  Future<void> pumpBanner(WidgetTester tester, ConnectionQuality quality) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConnectivityBanner(quality: quality)),
        ),
      );

  testWidgets('invisible quand tout va bien', (tester) async {
    await pumpBanner(tester, ConnectionQuality.online);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('hors ligne : icône et texte explicites', (tester) async {
    await pumpBanner(tester, ConnectionQuality.offline);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(
      find.text('Hors ligne : dernier état connu affiché.'),
      findsOneWidget,
    );
  });

  testWidgets('dégradé : connexion en cours', (tester) async {
    await pumpBanner(tester, ConnectionQuality.degraded);
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
    expect(find.text('Connexion au portail en cours…'), findsOneWidget);
  });
}
