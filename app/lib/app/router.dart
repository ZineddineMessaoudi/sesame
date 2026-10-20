import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/auth/viewmodels/session_view_model.dart';
import '../features/auth/views/sign_in_page.dart';
import '../features/gate/views/gate_page.dart';
import '../features/history/views/history_page.dart';

/// Chemins centralisés : aucune chaîne de route en dur dans les vues.
abstract final class AppRoutes {
  static const gate = '/';
  static const history = '/historique';
  static const signIn = '/connexion';
}

/// Le routeur est un provider pour rediriger selon la session Firebase sans
/// toucher aux vues : aucun écran du portail n'est construit sans connexion.
final routerProvider = Provider<GoRouter>((ref) {
  // Pont Riverpod -> go_router : `refreshListenable` attend un Listenable.
  // `read` et non `watch` : recréer le routeur perdrait la pile de navigation.
  final session = ValueNotifier<AuthUser?>(ref.read(sessionViewModelProvider));
  ref.listen(sessionViewModelProvider, (_, user) => session.value = user);

  final router = GoRouter(
    initialLocation: AppRoutes.gate,
    refreshListenable: session,
    redirect: (context, state) => redirectFor(
      signedIn: session.value != null,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.gate,
        builder: (context, state) => const GatePage(),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (context, state) => const HistoryPage(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInPage(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    session.dispose();
  });
  return router;
});

/// Règle de navigation, isolée pour être testée sans widget.
@visibleForTesting
String? redirectFor({required bool signedIn, required String location}) {
  final onSignIn = location == AppRoutes.signIn;
  if (!signedIn) return onSignIn ? null : AppRoutes.signIn;
  return onSignIn ? AppRoutes.gate : null;
}
