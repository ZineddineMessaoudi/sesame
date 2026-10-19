import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';

void main() {
  group('GateState.tryParse', () {
    test('lit un payload valide du firmware', () {
      final state = GateState.tryParse(
        '{"state":"opening","ts":1792391878,"seq":2}',
      );

      expect(
        state,
        GateState(
          status: GateStatus.opening,
          reportedAt: DateTime.utc(2026, 10, 19, 6, 37, 58),
          seq: 2,
        ),
      );
    });

    test('ts = 0 (pas encore de NTP) donne une date inconnue', () {
      final state = GateState.tryParse('{"state":"closed","ts":0,"seq":1}');

      expect(state?.reportedAt, isNull);
      expect(state?.status, GateStatus.closed);
    });

    for (final payload in [
      'pas du json',
      '[]',
      '{"state":"closed","ts":1}', // seq manquant
      '{"state":"toggle","ts":1,"seq":1}', // état inconnu
      '{"state":"open","ts":"1","seq":1}', // mauvais type
      '{"state":"open","ts":1,"seq":-1}', // seq négatif
    ]) {
      test('rejette un payload invalide : $payload', () {
        expect(GateState.tryParse(payload), isNull);
      });
    }
  });
}
