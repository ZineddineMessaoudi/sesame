import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// État du formulaire de connexion.
class SignInState {
  const SignInState({this.submitting = false, this.error});

  /// Vrai pendant l'appel à Firebase : bouton désactivé, pas de double envoi.
  final bool submitting;

  /// Message prêt à afficher, `null` si rien à signaler.
  final String? error;
}

class SignInViewModel extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  /// En cas de succès, rien à faire ici : la session change et le routeur
  /// redirige de lui-même vers le portail.
  Future<void> submit(String email, String password) async {
    if (state.submitting) return;
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      state = const SignInState(
        error: 'Renseignez l\'e-mail et le mot de passe.',
      );
      return;
    }

    state = const SignInState(submitting: true);
    try {
      await ref.read(authRepositoryProvider).signIn(trimmed, password);
      if (!ref.mounted) return;
      state = const SignInState();
    } on AuthException catch (e) {
      if (!ref.mounted) return;
      state = SignInState(error: e.message);
    }
  }
}

final signInViewModelProvider = NotifierProvider<SignInViewModel, SignInState>(
  SignInViewModel.new,
);
