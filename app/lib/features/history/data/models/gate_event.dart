import '../../../gate/data/models/gate_state.dart';

/// Nature d'un évènement historisé, reprise du tag `type` d'InfluxDB (§9).
enum GateEventType { ring, state }

/// Évènement renvoyé par `GET /api/events`, et mis en cache dans Hive.
///
/// L'app ne touche jamais InfluxDB directement : elle ne connaît que cette
/// forme-là, exposée par Node-RED (§3).
class GateEvent {
  const GateEvent({
    required this.ts,
    required this.type,
    this.status,
    this.ringId,
    this.seq,
  });

  /// Horodatage renvoyé par le backend, toujours en UTC.
  final DateTime ts;
  final GateEventType type;

  /// Renseigné pour [GateEventType.state] uniquement.
  final GateStatus? status;

  /// Renseigné pour [GateEventType.ring] uniquement.
  final String? ringId;

  /// Numéro d'ordre de l'ESP32, présent sur les changements d'état.
  final int? seq;

  /// `null` pour un évènement inexploitable : une ligne corrompue est ignorée
  /// plutôt que de faire échouer tout l'historique.
  static GateEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final ts = DateTime.tryParse('${json['ts']}');
    final type = GateEventType.values.asNameMap()['${json['type']}'];
    if (ts == null || type == null) return null;

    final status = GateStatus.values.asNameMap()['${json['state']}'];
    // Un changement d'état sans état lisible n'a rien à raconter.
    if (type == GateEventType.state && status == null) return null;

    return GateEvent(
      ts: ts.toUtc(),
      type: type,
      status: status,
      ringId: json['ringId'] as String?,
      seq: (json['seq'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GateEvent &&
      other.ts == ts &&
      other.type == type &&
      other.status == status &&
      other.ringId == ringId &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(ts, type, status, ringId, seq);

  @override
  String toString() => 'GateEvent($type, $ts, ${status ?? ringId})';
}
