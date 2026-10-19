import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/notifications/push_service.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

/// `NotificationSettings` a un constructeur à nombreux champs dont la valeur
/// ne nous intéresse pas : un Fake évite de tous les renseigner.
class FakeNotificationSettings extends Fake implements NotificationSettings {}

void main() {
  late MockFirebaseMessaging messaging;

  setUp(() {
    messaging = MockFirebaseMessaging();
    when(() => messaging.requestPermission())
        .thenAnswer((_) async => FakeNotificationSettings());
    when(() => messaging.subscribeToTopic(any())).thenAnswer((_) async {});
  });

  test('s\'abonne au topic portant l\'identifiant du site', () async {
    await PushService('site_7f3a', messaging: () => messaging).subscribe();

    verifyInOrder([
      () => messaging.requestPermission(),
      // Le topic est le siteId opaque : aucun identifiant utilisateur dans le
      // routage des messages (§10).
      () => messaging.subscribeToTopic('site_7f3a'),
    ]);
  });

  test('l\'échec de Firebase remonte au lieu d\'être avalé', () async {
    when(() => messaging.requestPermission()).thenThrow(StateError('no app'));

    // L'appelant (SesameApp) décide quoi en faire : ici l'app doit rester
    // utilisable sans push, pas planter au démarrage.
    expect(
      PushService('site_7f3a', messaging: () => messaging).subscribe(),
      throwsStateError,
    );
  });

  test('Firebase non initialisé : rien n\'explose à la construction', () {
    // La fabrique n'est appelée que dans subscribe(), jamais au moment où le
    // provider crée le service.
    expect(
      () => PushService(
        'site_7f3a',
        messaging: () => throw StateError('Firebase non initialisé'),
      ),
      returnsNormally,
    );
  });
}
