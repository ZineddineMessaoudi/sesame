import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lifecycle/app_lifecycle_service.dart';
import '../core/notifications/push_service.dart';
import 'router.dart';
import 'theme.dart';

class SesameApp extends ConsumerWidget {
  const SesameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instancie le service de cycle de vie dès le démarrage, pour toute la durée de l'app.
    ref.watch(appLifecycleServiceProvider);

    // Abonnement au topic FCM du site. Sans attendre, et sans faire échouer le
    // démarrage : Firebase absent ou push refusé ne doit pas priver
    // l'utilisateur du portail.
    unawaited(
      ref
          .watch(pushServiceProvider)
          .subscribe()
          .catchError(
            (Object e) => debugPrint('Push : abonnement impossible ($e)'),
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
