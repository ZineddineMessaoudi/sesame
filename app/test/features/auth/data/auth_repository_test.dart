import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/auth/data/auth_repository.dart';

void main() {
  test('e-mail inconnu et mauvais mot de passe donnent le même message', () {
    // Pas d'énumération des comptes : on ne dit jamais lequel des deux est faux.
    const expected = 'E-mail ou mot de passe incorrect.';
    expect(AuthRepository.messageFor('invalid-credential'), expected);
    expect(AuthRepository.messageFor('user-not-found'), expected);
    expect(AuthRepository.messageFor('wrong-password'), expected);
  });

  test('hors ligne, le message explique que le réseau est nécessaire', () {
    expect(
      AuthRepository.messageFor('network-request-failed'),
      contains('connexion Internet'),
    );
  });

  test(
    'sans Firebase, aucune session et toute connexion est refusée',
    () async {
      final repository = AuthRepository(null);

      expect(repository.currentUser, isNull);
      await expectLater(
        repository.signIn('a@b.fr', 'secret'),
        throwsA(isA<AuthException>()),
      );
    },
  );
}
