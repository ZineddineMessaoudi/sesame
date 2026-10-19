import 'dart:async';

import 'package:sesame/core/connectivity/network_monitor.dart';

/// Réseau simulé : les tests poussent `true` / `false` dans [changesController].
class FakeNetworkMonitor implements NetworkMonitor {
  FakeNetworkMonitor({this.initial = true});

  bool initial;
  final changesController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get changes => changesController.stream;

  @override
  Future<bool> check() async => initial;
}
