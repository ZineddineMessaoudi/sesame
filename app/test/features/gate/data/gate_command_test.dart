import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/gate/data/models/gate_ack.dart';
import 'package:sesame/features/gate/data/models/gate_command.dart';

void main() {
  group('GateCommand', () {
    final now = DateTime.utc(2026, 10, 19, 7, 30, 0, 750); // 750 ms : tronqué

    test('produit le payload du contrat, en secondes, avec un TTL de 60 s', () {
      final command = GateCommand.create(
        cmdId: 'abc',
        action: GateAction.open,
        now: now,
      );

      expect(jsonDecode(command.toPayload()), {
        'cmdId': 'abc',
        'action': 'open',
        'issuedAt': 1792395000,
        'expiresAt': 1792395060,
      });
    });

    test('est expirée à partir de expiresAt', () {
      final command = GateCommand.create(
        cmdId: 'abc',
        action: GateAction.close,
        now: now,
      );

      expect(
        command.isExpiredAt(now.add(const Duration(seconds: 59))),
        isFalse,
      );
      expect(command.isExpiredAt(now.add(const Duration(seconds: 60))), isTrue);
    });
  });

  group('GateAck.tryParse', () {
    test('lit les quatre résultats du contrat', () {
      for (final (wire, result) in [
        ('accepted', AckResult.accepted),
        ('rejected_expired', AckResult.rejectedExpired),
        ('rejected_no_time', AckResult.rejectedNoTime),
        ('duplicate', AckResult.duplicate),
      ]) {
        final ack = GateAck.tryParse('{"cmdId":"abc","result":"$wire","ts":1}');
        expect(ack?.result, result);
        expect(ack?.cmdId, 'abc');
      }
    });

    test('rejette un résultat inconnu ou un payload invalide', () {
      expect(GateAck.tryParse('{"cmdId":"abc","result":"ok"}'), isNull);
      expect(GateAck.tryParse('{"result":"accepted"}'), isNull);
      expect(GateAck.tryParse('pas du json'), isNull);
    });
  });
}
