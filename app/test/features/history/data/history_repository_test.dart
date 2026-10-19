import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';
import 'package:sesame/features/history/data/history_repository.dart';
import 'package:sesame/features/history/data/models/gate_event.dart';

import '../../../helpers/hive_box.dart';

void main() {
  final baseUrl = Uri.parse('http://10.0.2.2:1880');
  late Box<GateEvent> box;

  setUp(() async {
    box = await openTestBox<GateEvent>();
  });

  /// Repository branché sur une réponse HTTP fabriquée, sans réseau.
  HistoryRepository repositoryReturning(
    String body, {
    int status = 200,
    void Function(http.Request)? onRequest,
  }) => HistoryRepository(
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        body,
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    baseUrl,
    box,
  );

  String apiBody(List<Map<String, Object?>> events) =>
      jsonEncode({'count': events.length, 'events': events});

  test('interroge /api/events avec la fenêtre demandée', () async {
    late Uri called;
    final repository = repositoryReturning(
      apiBody([]),
      onRequest: (r) => called = r.url,
    );

    await repository.fetch(from: '-24h');

    expect(called.path, '/api/events');
    expect(called.queryParameters['from'], '-24h');
  });

  test(
    'traduit les évènements et les trie du plus récent au plus ancien',
    () async {
      final repository = repositoryReturning(
        apiBody([
          {
            'ts': '2026-10-19T22:00:00Z',
            'type': 'state',
            'state': 'closed',
            'seq': 3,
          },
          {'ts': '2026-10-19T23:00:00Z', 'type': 'ring', 'ringId': 'r-1'},
        ]),
      );

      final events = await repository.fetch();

      expect(events.map((e) => e.type), [
        GateEventType.ring,
        GateEventType.state,
      ]);
      expect(events.last.status, GateStatus.closed);
      expect(events.last.seq, 3);
      expect(events.first.ringId, 'r-1');
    },
  );

  test('un évènement corrompu est écarté sans vider l\'historique', () async {
    final repository = repositoryReturning(
      apiBody([
        {'ts': 'pas une date', 'type': 'ring'},
        {'ts': '2026-10-19T22:00:00Z', 'type': 'inconnu'},
        // Changement d'état sans état lisible : il n'a rien à raconter.
        {'ts': '2026-10-19T22:30:00Z', 'type': 'state'},
        {'ts': '2026-10-19T23:00:00Z', 'type': 'ring', 'ringId': 'r-1'},
      ]),
    );

    expect((await repository.fetch()).single.ringId, 'r-1');
  });

  test('le cache survit et reste trié pour l\'affichage hors ligne', () async {
    final repository = repositoryReturning(
      apiBody([
        {'ts': '2026-10-19T22:00:00Z', 'type': 'ring', 'ringId': 'vieux'},
        {'ts': '2026-10-19T23:00:00Z', 'type': 'ring', 'ringId': 'recent'},
      ]),
    );

    await repository.fetch();

    expect(repository.cached.map((e) => e.ringId), ['recent', 'vieux']);
  });

  test('une nouvelle récupération remplace le cache, sans doublon', () async {
    await repositoryReturning(
      apiBody([
        {'ts': '2026-10-19T22:00:00Z', 'type': 'ring', 'ringId': 'r-1'},
      ]),
    ).fetch();

    final repository = repositoryReturning(
      apiBody([
        {'ts': '2026-10-19T23:00:00Z', 'type': 'ring', 'ringId': 'r-2'},
      ]),
    );
    await repository.fetch();

    expect(repository.cached.map((e) => e.ringId), ['r-2']);
  });

  test('une erreur HTTP est traduite en message affichable', () async {
    final repository = repositoryReturning('oups', status: 500);

    expect(
      repository.fetch(),
      throwsA(
        isA<HistoryException>().having(
          (e) => e.message,
          'message',
          contains('500'),
        ),
      ),
    );
  });

  test('un corps illisible ne fait pas planter l\'écran', () async {
    final repository = repositoryReturning('pas du json');

    expect(repository.fetch(), throwsA(isA<HistoryException>()));
  });

  test('le cache reste disponible après un échec réseau', () async {
    await repositoryReturning(
      apiBody([
        {'ts': '2026-10-19T22:00:00Z', 'type': 'ring', 'ringId': 'r-1'},
      ]),
    ).fetch();

    final repository = repositoryReturning('oups', status: 503);
    await expectLater(repository.fetch(), throwsA(isA<HistoryException>()));

    // C'est tout l'intérêt de l'offline-first : l'échec ne détruit rien.
    expect(repository.cached.single.ringId, 'r-1');
  });
}
