import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Résultat de la confirmation d'identité.
enum IdentityCheck {
  confirmed,

  /// Refus ou annulation par l'utilisateur.
  cancelled,

  /// Aucun verrouillage configuré sur l'appareil : on ne peut pas confirmer,
  /// donc on refuse (jamais d'ouverture sans preuve d'identité).
  unavailable,
}

/// Confirmation d'identité locale (biométrie, ou code de l'appareil en repli).
/// Isolée derrière un repository : le ViewModel ne dépend pas du plugin.
class BiometricRepository {
  BiometricRepository([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<IdentityCheck> confirm(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // Repli sur le code de l'appareil : accessible à qui ne peut pas utiliser
        // la biométrie, et tout aussi local (Keystore / Secure Enclave).
        biometricOnly: false,
      );
      return ok ? IdentityCheck.confirmed : IdentityCheck.cancelled;
    } on LocalAuthException catch (e) {
      debugPrint('Biométrie : ${e.code.name}');
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware => IdentityCheck.unavailable,
        _ => IdentityCheck.cancelled,
      };
    }
  }
}

final biometricRepositoryProvider = Provider<BiometricRepository>(
  (ref) => BiometricRepository(),
);
