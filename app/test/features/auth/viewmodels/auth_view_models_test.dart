import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/features/auth/data/auth_repository.dart';
import 'package:sesame/features/auth/viewmodels/session_view_model.dart';
import 'package:sesame/features/auth/viewmodels/sign_in_view_model.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  const alice = AuthUser(uid: 'u-1', email: 'alice@test.fr');

  late MockAuthRepository repository;
  late StreamController<AuthUser?> changes;
  late ProviderContainer container;

  setUp(() {
    repository = MockAuthRepository();
    changes = StreamController<AuthUser?>.broadcast();
    when(() => repository.currentUser).thenReturn(null);
    when(() => repository.userChanges).thenAnswer((_) => changes.stream);
    when(() => repository.signIn(any(), any())).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(() {
      container.dispose();
      changes.close();
    });
  });

  group('SessionViewModel', () {
    test('reprend la session restaurée par Firebase, sans attendre', () {
      when(() => repository.currentUser).thenReturn(alice);

      expect(container.read(sessionViewModelProvider), alice);
    });

    test('suit les connexions et déconnexions', () async {
      container.read(sessionViewModelProvider);

      changes.add(alice);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionViewModelProvider), alice);

      changes.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionViewModelProvider), isNull);
    });
  });

  group('SignInViewModel', () {
    SignInState state() => container.read(signInViewModelProvider);
    SignInViewModel vm() => container.read(signInViewModelProvider.notifier);

    test('champs vides : erreur locale, aucun appel à Firebase', () async {
      await vm().submit('  ', '');

      expect(state().error, isNotNull);
      verifyNever(() => repository.signIn(any(), any()));
    });

    test('l\'e-mail est nettoyé des espaces avant l\'envoi', () async {
      await vm().submit(' alice@test.fr ', 'secret');

      verify(() => repository.signIn('alice@test.fr', 'secret')).called(1);
      expect(state().error, isNull);
      expect(state().submitting, isFalse);
    });

    test('un échec affiche le message du repository', () async {
      when(() => repository.signIn(any(), any()))
          .thenThrow(const AuthException('E-mail ou mot de passe incorrect.'));

      await vm().submit('alice@test.fr', 'faux');

      expect(state().error, 'E-mail ou mot de passe incorrect.');
      expect(state().submitting, isFalse);
    });

    test('pas de double envoi pendant une connexion en cours', () async {
      final pending = Completer<void>();
      when(() => repository.signIn(any(), any()))
          .thenAnswer((_) => pending.future);

      final first = vm().submit('alice@test.fr', 'secret');
      expect(state().submitting, isTrue);
      await vm().submit('alice@test.fr', 'secret');
      pending.complete();
      await first;

      verify(() => repository.signIn(any(), any())).called(1);
    });
  });
}
