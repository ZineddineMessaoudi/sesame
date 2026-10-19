import 'gate_state.dart';

/// Dernier état connu du portail, tel que mis en cache dans Hive.
///
/// `receivedAt` (horloge du téléphone) sert à la fraîcheur de la donnée :
/// « Mis à jour il y a … » ne dépend pas de l'horloge de l'ESP32.
class GateSnapshot {
  const GateSnapshot({required this.state, required this.receivedAt});

  final GateState state;
  final DateTime receivedAt;
}
