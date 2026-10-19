import 'dart:convert';

/// Réponse de l'ESP32 sur `gate/ack`, noms identiques au contrat (§4).
enum AckResult {
  accepted('accepted'),
  rejectedExpired('rejected_expired'),
  rejectedNoTime('rejected_no_time'),
  duplicate('duplicate');

  const AckResult(this.wire);

  final String wire;

  static AckResult? fromWire(String value) {
    for (final result in values) {
      if (result.wire == value) return result;
    }
    return null;
  }
}

class GateAck {
  const GateAck({required this.cmdId, required this.result});

  final String cmdId;
  final AckResult result;

  /// `null` pour un payload invalide, comme pour `GateState.tryParse`.
  static GateAck? tryParse(String payload) {
    final Object? json;
    try {
      json = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (json case {'cmdId': final String cmdId, 'result': final String raw}) {
      final result = AckResult.fromWire(raw);
      return result == null ? null : GateAck(cmdId: cmdId, result: result);
    }
    return null;
  }
}
