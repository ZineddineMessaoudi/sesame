import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/gate/views/gate_page.dart';
import '../features/history/views/history_page.dart';

/// Chemins centralisés : aucune chaîne de route en dur dans les vues.
abstract final class AppRoutes {
  static const gate = '/';
  static const history = '/historique';
}

/// Le routeur est un provider pour pouvoir, plus tard, rediriger selon
/// l'état d'authentification Firebase (étape 7) sans toucher aux vues.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.gate,
    routes: [
      GoRoute(
        path: AppRoutes.gate,
        builder: (context, state) => const GatePage(),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (context, state) => const HistoryPage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
