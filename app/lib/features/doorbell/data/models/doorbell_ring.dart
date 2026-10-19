import 'dart:convert';

/// Coup de sonnette reçu sur `doorbell/ring` : `{"ringId":"uuid","ts":1760731200}`.
///
/// Événement ponctuel, publié sans retain : il n'est jamais rejoué à
/// l'abonnement. Et le firmware ne met pas les sonneries en file quand il est
/// hors ligne — une sonnerie relayée dix minutes plus tard ferait croire qu'un
/// visiteur attend encore.
class DoorbellRing {
  const DoorbellRing({
    required this.ringId,
    required this.reportedAt,
    required this.receivedAt,
  });

  /// Identifiant unique du coup de sonnette, qui sert à dédupliquer : avec
  /// QoS 1 le même message peut être livré deux fois (§4).
  final String ringId;

  /// Horloge de l'ESP32 ; `null` s'il n'avait pas encore l'heure NTP (`ts` = 0).
  final DateTime? reportedAt;

  /// Horloge du téléphone, posée à la réception : c'est elle qui sert à
  /// l'affichage, comme `GateSnapshot.receivedAt`, pour ne pas dépendre de
  /// l'heure de l'ESP32.
  final DateTime receivedAt;

  /// Renvoie `null` pour un payload invalide : un message corrompu est ignoré
  /// au lieu de faire planter le flux temps réel.
  static DoorbellRing? tryParse(
    String payload, {
    required DateTime receivedAt,
  }) {
    final Object? json;
    try {
      json = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (json case {'ringId': final String ringId, 'ts': final int ts}
        when ringId.isNotEmpty && ts >= 0) {
      return DoorbellRing(
        ringId: ringId,
        reportedAt: ts == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
        receivedAt: receivedAt,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DoorbellRing &&
      other.ringId == ringId &&
      other.reportedAt == reportedAt &&
      other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(ringId, reportedAt, receivedAt);

  @override
  String toString() => 'DoorbellRing($ringId, reportedAt: $reportedAt)';
}
