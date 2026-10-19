import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lifecycle/app_lifecycle_service.dart';
import 'router.dart';
import 'theme.dart';

class SesameApp extends ConsumerWidget {
  const SesameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instancie le service de cycle de vie dès le démarrage, pour toute la durée de l'app.
    ref.watch(appLifecycleServiceProvider);
    return MaterialApp.router(
      title: 'Sésame',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
