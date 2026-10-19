import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/notifications/notification_service.dart';
import 'package:sesame/features/doorbell/data/doorbell_repository.dart';
import 'package:sesame/features/doorbell/data/models/doorbell_ring.dart';
import 'package:sesame/features/doorbell/viewmodels/doorbell_view_model.dart';

class MockDoorbellRepository extends Mock implements DoorbellRepository {}

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late StreamController<DoorbellRing> rings;
  late MockDoorbellRepository repository;
  late MockNotificationService notifications;
  late ProviderContainer container;

  DoorbellRing ring(String id) => DoorbellRing(
    ringId: id,
    reportedAt: null,
    receivedAt: DateTime.utc(2026, 10, 19, 22, 30),
  );

  setUp(() {
    rings = StreamController<DoorbellRing>.broadcast();
    repository = MockDoorbellRepository();
    when(() => repository.watchRings()).thenAnswer((_) => rings.stream);
    notifications = MockNotificationService();
    when(() => notifications.initialize()).thenAnswer((_) async {});
    when(
      () => notifications.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        doorbellRepositoryProvider.overrideWithValue(repository),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(rings.close);
  });

  DoorbellRing? state() => container.read(doorbellViewModelProvider);

  test('au démarrage, aucune sonnerie à afficher', () {
    expect(state(), isNull);
  });

  test('l\'autorisation est demandée au démarrage, pas à la 1re sonnerie', () {
    state(); // construit le ViewModel

    // Sinon la boîte de dialogue Android 13+ s'ouvre pendant que la première
    // sonnerie arrive, et cette notification-là est perdue.
    verify(() => notifications.initialize()).called(1);
  });

  test('une sonnerie s\'affiche et déclenche la notification', () async {
    state(); // instancie le ViewModel, donc l'abonnement

    rings.add(ring('ring-1'));
    await pumpEventQueue();

    expect(state()?.ringId, 'ring-1');
    verify(
      () => notifications.show(
        id: DoorbellViewModel.notificationId,
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).called(1);
  });

  test('une seconde sonnerie remplace la première', () async {
    state();

    rings.add(ring('ring-1'));
    await pumpEventQueue();
    rings.add(ring('ring-2'));
    await pumpEventQueue();

    expect(state()?.ringId, 'ring-2');
    // Même identifiant de notification : elles ne s'empilent pas.
    verify(
      () => notifications.show(
        id: DoorbellViewModel.notificationId,
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).called(2);
  });

  test('acknowledge efface la sonnerie affichée', () async {
    state();
    rings.add(ring('ring-1'));
    await pumpEventQueue();

    container.read(doorbellViewModelProvider.notifier).acknowledge();

    expect(state(), isNull);
  });
}
