import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Présence d'une interface réseau (Wi-Fi, mobile, Ethernet), via `connectivity_plus`.
///
/// Attention : une interface active ne garantit pas l'accès à Internet (portail
/// captif, Wi-Fi de l'école isolé…). C'est pour cela que la qualité de connexion
/// combine cette information avec l'état réel de la session MQTT.
class NetworkMonitor {
  NetworkMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map((results) {
        debugPrint('Réseau : ${results.map((r) => r.name).join(', ')}');
        return _hasNetwork(results);
      });

  /// En cas d'échec du plugin, on suppose qu'un réseau existe : l'état de la
  /// session MQTT tranchera alors entre `online` et `degraded`.
  Future<bool> check() async {
    try {
      return _hasNetwork(await _connectivity.checkConnectivity());
    } on Exception catch (e) {
      debugPrint('Réseau : vérification impossible ($e)');
      return true;
    }
  }

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}

final networkMonitorProvider = Provider<NetworkMonitor>(
  (ref) => NetworkMonitor(),
);
