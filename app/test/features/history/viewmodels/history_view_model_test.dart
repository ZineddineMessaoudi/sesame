import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/features/history/data/history_repository.dart';
import 'package:sesame/features/history/data/models/gate_event.dart';
import 'package:sesame/features/history/viewmodels/history_view_model.dart';

class MockHistoryRepository extends Mock implements HistoryRepository {}

void main() {
  late MockHistoryRepository repository;
  late ProviderContainer container;

  GateEvent ring(String id, {int hour = 22}) => GateEvent(
    ts: DateTime.utc(2026, 10, 19, hour),
    type: GateEventType.ring,
    ringId: id,
  );

  setUp(() {
    repository = MockHistoryRepository();
    when(() => repository.cached).thenReturn(const []);
    when(() => repository.fetch(from: any(named: 'from')))
        .thenAnswer((_) async => const []);

    container = ProviderContainer(
      overrides: [historyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  HistoryState state() => container.read(historyViewModelProvider);

  test('le cache s\'affiche avant même la requête réseau', () {
    when(() => repository.cached).thenReturn([ring('r-1')]);

    // Lecture synchrone : la requête n'a pas encore eu le temps de partir.
    expect(state().events.single.ringId, 'r-1');
    expect(state().loading, isTrue);
  });

  test('la récupération remplace les évènements affichés', () async {
    when(() => repository.cached).thenReturn([ring('ancien')]);
    when(() => repository.fetch(from: any(named: 'from')))
        .thenAnswer((_) async => [ring('frais')]);

    state(); // construit le ViewModel
    await container.read(historyViewModelProvider.notifier).refresh();

    expect(state().events.single.ringId, 'frais');
    expect(state().loading, isFalse);
    expect(state().error, isNull);
  });

  test('un échec réseau garde le cache affiché et signale l\'erreur', () async {
    when(() => repository.cached).thenReturn([ring('r-1')]);
    when(() => repository.fetch(from: any(named: 'from')))
        .thenThrow(const HistoryException('Serveur injoignable.'));

    state();
    await container.read(historyViewModelProvider.notifier).refresh();

    // Le cœur de l'offline-first : l'échec n'efface rien.
    expect(state().events.single.ringId, 'r-1');
    expect(state().error, 'Serveur injoignable.');
    expect(state().loading, isFalse);
  });

  test('isEmpty ne vaut que pour un historique vraiment vide', () async {
    state();
    await container.read(historyViewModelProvider.notifier).refresh();

    expect(state().isEmpty, isTrue);
  });
}
