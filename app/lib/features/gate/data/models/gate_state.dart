import 'dart:convert';

/// Position du portail, telle que publiée par l'ESP32 (seule source de vérité, §3).
enum GateStatus { open, closed, opening, closing }

/// Dernier état *reported* du portail : `{"state":"closed","ts":1760731200,"seq":42}`.
class GateState {
  const GateState({
    required this.status,
    required this.reportedAt,
    required this.seq,
  });

  final GateStatus status;

  /// `null` si l'ESP32 n'avait pas encore l'heure NTP (`ts` = 0).
  final DateTime? reportedAt;

  /// Numéro d'ordre de l'ESP32 : ordonne les messages sans dépendre des horloges.
  final int seq;

  /// Renvoie `null` pour un payload invalide : un message corrompu est ignoré
  /// au lieu de faire planter le flux temps réel.
  static GateState? tryParse(String payload) {
    final Object? json;
    try {
      json = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (json
        case {
          'state': final String state,
          'ts': final int ts,
          'seq': final int seq,
        }
        when ts >= 0 && seq >= 0) {
      final status = GateStatus.values.asNameMap()[state];
      if (status == null) return null;
      return GateState(
        status: status,
        reportedAt: ts == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
        seq: seq,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is GateState &&
      other.status == status &&
      other.reportedAt == reportedAt &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(status, reportedAt, seq);

  @override
  String toString() => 'GateState($status, seq: $seq, reportedAt: $reportedAt)';
}
