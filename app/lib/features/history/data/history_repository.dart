import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/storage/local_storage.dart';
import 'models/gate_event.dart';

/// Échec de récupération de l'historique, avec un message affichable tel quel.
class HistoryException implements Exception {
  const HistoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Accès à l'historique (Model du MVVM) : interroge l'API de Node-RED et tient
/// le cache Hive à jour. L'app ne touche jamais InfluxDB directement (§3).
class HistoryRepository {
  HistoryRepository(
    this._client,
    this._baseUrl,
    this._cache, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Uri _baseUrl;
  final Box<GateEvent> _cache;

  /// Le backend tourne sur la machine de dev : mieux vaut échouer vite et
  /// afficher le cache que laisser l'écran tourner indéfiniment.
  final Duration timeout;

  /// Dernier historique connu, du plus récent au plus ancien. Affiché
  /// immédiatement au démarrage, avant toute requête réseau, et seul contenu
  /// disponible hors ligne (§5).
  List<GateEvent> get cached {
    final events = _cache.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return List.unmodifiable(events);
  }

  /// Récupère l'historique et remplace le cache. [from] suit la syntaxe
  /// acceptée par l'API (`-7d`, `-24h`, ou un instant RFC3339).
  Future<List<GateEvent>> fetch({String from = '-7d'}) async {
    final uri = _baseUrl.replace(
      path: '/api/events',
      queryParameters: {'from': from},
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const HistoryException('Le serveur n\'a pas répondu à temps.');
    } on Object catch (e) {
      throw HistoryException('Serveur injoignable ($e).');
    }

    if (response.statusCode != 200) {
      throw HistoryException('Le serveur a répondu ${response.statusCode}.');
    }

    final Object? body;
    try {
      // bodyBytes et non body : la réponse contient des accents.
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const HistoryException('Réponse du serveur illisible.');
    }

    if (body is! Map || body['events'] is! List) {
      throw const HistoryException('Réponse du serveur inattendue.');
    }

    // Les évènements corrompus sont écartés un à un : un seul mauvais
    // enregistrement ne doit pas vider tout l'historique.
    final events =
        (body['events'] as List)
            .map(GateEvent.tryParse)
            .whereType<GateEvent>()
            .toList()
          ..sort((a, b) => b.ts.compareTo(a.ts));

    await _cache.clear();
    await _cache.addAll(events);
    return List.unmodifiable(events);
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HistoryRepository(
    client,
    ref.watch(appConfigProvider).apiBaseUrl,
    ref.watch(localStorageProvider).events,
  );
});
