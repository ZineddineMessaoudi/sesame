import 'dart:convert';

/// Commandes explicites uniquement, jamais `toggle` : avec QoS 1 un message peut
/// arriver deux fois, et un `toggle` dupliqué refermerait le portail (§4).
enum GateAction { open, close }

/// Ordre envoyé à l'ESP32 sur `gate/cmd`.
///
/// `cmdId`, `issuedAt` et `expiresAt` sont figés à la création : un renvoi
/// automatique réutilise le même objet (le TTL ne repart jamais à zéro), alors
/// que « Réessayer » crée une nouvelle commande.
class GateCommand {
  const GateCommand({
    required this.cmdId,
    required this.action,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory GateCommand.create({
    required String cmdId,
    required GateAction action,
    required DateTime now,
  }) {
    // Secondes entières : l'ESP32 compare des epoch en secondes.
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
    return GateCommand(
      cmdId: cmdId,
      action: action,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(ttl),
    );
  }

  /// Une ouverture envoyée hors ligne ne doit jamais être rejouée plus tard (§4).
  static const ttl = Duration(seconds: 60);

  final String cmdId;
  final GateAction action;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  String toPayload() => jsonEncode({
    'cmdId': cmdId,
    'action': action.name,
    'issuedAt': issuedAt.millisecondsSinceEpoch ~/ 1000,
    'expiresAt': expiresAt.millisecondsSinceEpoch ~/ 1000,
  });
}
