import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Utilisateur connecté, réduit à ce dont l'app a besoin : ni le ViewModel ni
/// la View ne dépendent du type `User` de Firebase.
@immutable
class AuthUser {
  const AuthUser({required this.uid, this.email});

  final String uid;
  final String? email;

  @override
  bool operator ==(Object other) => other is AuthUser && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// Échec de connexion, avec un message affichable tel quel.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Authentification Firebase par e-mail et mot de passe (Model du MVVM).
///
/// Pas d'inscription depuis l'app : les comptes du foyer sont créés dans la
/// console Firebase. Personne ne peut se créer un accès au portail.
class AuthRepository {
  /// [auth] vaut `null` quand Firebase n'a pas pu s'initialiser. On refuse
  /// alors toute connexion : sans authentification, pas d'accès au portail.
  AuthRepository(this._auth);

  final FirebaseAuth? _auth;

  /// Session restaurée par Firebase dès le démarrage, même hors ligne :
  /// l'utilisateur déjà connecté retrouve son portail sans réseau (§5).
  AuthUser? get currentUser => _toAuthUser(_auth?.currentUser);

  Stream<AuthUser?> get userChanges =>
      _auth?.authStateChanges().map(_toAuthUser) ?? const Stream.empty();

  Future<void> signIn(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthException('Service de connexion indisponible.');
    }
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      debugPrint('Auth : ${e.code}');
      throw AuthException(messageFor(e.code));
    }
  }

  Future<void> signOut() async => _auth?.signOut();

  /// Message volontairement identique pour un e-mail inconnu et un mauvais
  /// mot de passe : on ne révèle pas quels comptes existent.
  @visibleForTesting
  static String messageFor(String code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'E-mail ou mot de passe incorrect.',
    'invalid-email' => 'Adresse e-mail invalide.',
    'user-disabled' => 'Ce compte a été désactivé.',
    'too-many-requests' =>
      'Trop de tentatives. Réessayez dans quelques minutes.',
    'network-request-failed' =>
      'Pas de connexion Internet. La première connexion nécessite le réseau.',
    _ => 'Connexion impossible ($code).',
  };

  static AuthUser? _toAuthUser(User? user) =>
      user == null ? null : AuthUser(uid: user.uid, email: user.email);
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(Firebase.apps.isEmpty ? null : FirebaseAuth.instance),
);
