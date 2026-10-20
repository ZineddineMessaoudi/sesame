import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Session courante : `null` tant que personne n'est connecté.
///
/// État synchrone, initialisé avec la session restaurée par Firebase : le
/// routeur décide dès la première image, sans écran de chargement.
class SessionViewModel extends Notifier<AuthUser?> {
  @override
  AuthUser? build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.userChanges.listen((user) => state = user);
    ref.onDispose(subscription.cancel);
    return repository.currentUser;
  }

  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();
}

final sessionViewModelProvider = NotifierProvider<SessionViewModel, AuthUser?>(
  SessionViewModel.new,
);
