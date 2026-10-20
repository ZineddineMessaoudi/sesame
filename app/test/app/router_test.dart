import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/app/router.dart';

void main() {
  test('sans session, tout écran renvoie vers la connexion', () {
    expect(
      redirectFor(signedIn: false, location: AppRoutes.gate),
      AppRoutes.signIn,
    );
    expect(
      redirectFor(signedIn: false, location: AppRoutes.history),
      AppRoutes.signIn,
    );
    expect(redirectFor(signedIn: false, location: AppRoutes.signIn), isNull);
  });

  test('connecté, l\'écran de connexion renvoie vers le portail', () {
    expect(
      redirectFor(signedIn: true, location: AppRoutes.signIn),
      AppRoutes.gate,
    );
    expect(redirectFor(signedIn: true, location: AppRoutes.history), isNull);
  });
}
