import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lifecycle/app_lifecycle_service.dart';
import '../core/mqtt/mqtt_service.dart';
import '../core/notifications/push_service.dart';
import '../features/auth/viewmodels/session_view_model.dart';
import 'router.dart';
import 'theme.dart';

class SesameApp extends ConsumerWidget {
  const SesameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instancie le service de cycle de vie dès le démarrage, pour toute la durée de l'app.
    ref.watch(appLifecycleServiceProvider);

    // MQTT et push liés à la session : un téléphone déconnecté ne reçoit plus
    // rien du site, ni au premier plan (MQTT) ni en arrière-plan (FCM).
    // Rejoué à chaque changement de session uniquement.
    final signedIn = ref.watch(sessionViewModelProvider) != null;
    final mqtt = ref.watch(mqttServiceProvider);
    mqtt.allow(signedIn);
    // Après une reconnexion, l'écran du portail déjà construit ne relance pas
    // MQTT de lui-même. start() est idempotent ; les abonnements sont rejoués.
    if (signedIn) unawaited(mqtt.start());

    // Sans attendre, et sans faire échouer le démarrage : Firebase absent ou
    // push refusé ne doit pas priver l'utilisateur du portail.
    final push = ref.watch(pushServiceProvider);
    unawaited(
      (signedIn ? push.subscribe() : push.unsubscribe()).catchError(
        (Object e) => debugPrint('Push : (dés)abonnement impossible ($e)'),
      ),
    );
    return MaterialApp.router(
      title: 'Sésame',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
