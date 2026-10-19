import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

/// État de la session MQTT, indépendant de la librairie : les repositories
/// et le futur `ConnectionNotifier` ne dépendent pas de `mqtt_client`.
enum MqttSessionState { disconnected, connecting, connected }

/// Message reçu, déjà décodé en UTF-8.
class MqttInboundMessage {
  const MqttInboundMessage({
    required this.topic,
    required this.payload,
    required this.retained,
  });

  final String topic;
  final String payload;

  /// `true` si c'est la valeur mémorisée par le broker (retain), rejouée à l'abonnement.
  final bool retained;
}

/// Seule classe de l'app qui parle au broker. Les repositories s'abonnent à
/// [messages] ; l'UI ne la voit jamais (MVVM, §7).
class MqttService {
  MqttService(this._config);

  final AppConfig _config;

  static const _keepAliveSeconds = 60; // §5 : compromis réactivité / batterie
  static const _maxBackoff = Duration(seconds: 30);

  // Broadcast : plusieurs repositories (portail, sonnette, statut) écoutent le même flux.
  final _messages = StreamController<MqttInboundMessage>.broadcast();
  final _sessionStates = StreamController<MqttSessionState>.broadcast();
  final _subscriptions = <String>{};

  MqttServerClient? _client;
  Stream<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  MqttSessionState _sessionState = MqttSessionState.disconnected;
  bool _wanted = false; // l'app veut-elle être connectée ? (faux après stop())
  Future<void>? _starting;

  Stream<MqttInboundMessage> get messages => _messages.stream;
  Stream<MqttSessionState> get sessionStates => _sessionStates.stream;
  MqttSessionState get sessionState => _sessionState;

  /// Se connecte et réessaie avec un backoff exponentiel plafonné (1, 2, 4… 30 s)
  /// tant que [stop] n'a pas été appelé. Ensuite, `autoReconnect` de la librairie
  /// prend le relais pour les coupures en cours de session.
  Future<void> start() {
    // Posé ici et non dans la boucle : un start() qui suit un stop() pendant l'attente
    // du backoff doit relancer la boucle déjà en cours, pas la laisser s'arrêter.
    _wanted = true;
    return _starting ??= _connectLoop().whenComplete(() => _starting = null);
  }

  /// Déconnexion volontaire (ex. app en arrière-plan) : pas de reconnexion automatique.
  void stop() {
    _wanted = false;
    _client?.disconnect();
  }

  /// Mémorise l'abonnement pour le rejouer après chaque (re)connexion.
  void subscribe(String topic) {
    if (!_subscriptions.add(topic)) return;
    if (_sessionState == MqttSessionState.connected) {
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  /// Publie en QoS 1, sans retain. Renvoie `false` si la session n'est pas ouverte :
  /// c'est à l'appelant de décider (afficher l'erreur, mettre en attente…), jamais
  /// d'envoi différé caché ici.
  bool publish(String topic, String payload) {
    final client = _client;
    if (client == null || _sessionState != MqttSessionState.connected) {
      return false;
    }
    final data = MqttClientPayloadBuilder().addUTF8String(payload).payload!;
    try {
      client.publishMessage(topic, MqttQos.atLeastOnce, data);
      return true;
    } on Exception catch (e) {
      debugPrint('MQTT : publication impossible ($e)');
      return false;
    }
  }

  Future<void> dispose() async {
    stop();
    await _updatesSub?.cancel();
    await _messages.close();
    await _sessionStates.close();
  }

  Future<void> _connectLoop() async {
    var attempt = 0;
    while (_wanted && _sessionState != MqttSessionState.connected) {
      if (await _tryConnect()) return;
      final delay = Duration(seconds: min(1 << attempt, _maxBackoff.inSeconds));
      attempt++;
      debugPrint('MQTT : échec, nouvel essai dans ${delay.inSeconds} s');
      await Future<void>.delayed(delay);
    }
  }

  Future<bool> _tryConnect() async {
    final client = _client ??= _buildClient();
    _setState(MqttSessionState.connecting);
    try {
      await client.connect(_config.mqttUsername, _config.mqttPassword);
    } on Exception catch (e) {
      debugPrint('MQTT : connexion impossible ($e)');
      client.disconnect();
      _setState(MqttSessionState.disconnected);
      return false;
    }
    return client.connectionStatus?.state == MqttConnectionState.connected;
  }

  MqttServerClient _buildClient() {
    // Identifiant unique par lancement : le broker éjecte un second client au même identifiant
    // (ex. émulateur + simulateur iOS lancés en même temps).
    final clientId = 'sesame-app-${const Uuid().v4().substring(0, 8)}';
    final client =
        MqttServerClient.withPort(_config.mqttHost, clientId, _config.mqttPort)
          ..secure =
              true // TLS 8883 uniquement (§10) ; certificat vérifié par le système
          ..setProtocolV311()
          ..keepAlivePeriod = _keepAliveSeconds
          ..autoReconnect = true
          // On rejoue nous-mêmes les abonnements dans _onConnected : un seul chemin
          // pour la connexion initiale, la reconnexion auto et le retour au premier plan.
          ..resubscribeOnAutoReconnect = false
          ..logging(on: false)
          ..onConnected = _onConnected
          ..onAutoReconnected = _onConnected
          ..onAutoReconnect = (() => _setState(MqttSessionState.connecting))
          ..onDisconnected = (() => _setState(MqttSessionState.disconnected));
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean(); // pas de session persistante : l'état courant revient par retain
    return client;
  }

  void _onConnected() {
    final client = _client!;
    // `connect()` recrée le flux `updates` de la librairie (ex. après stop() puis start()) :
    // on se réabonne au nouveau, sinon plus aucun message n'arriverait.
    if (!identical(client.updates, _updates)) {
      _updatesSub?.cancel();
      _updates = client.updates;
      _updatesSub = _updates?.listen(_onUpdates);
    }
    for (final topic in _subscriptions) {
      client.subscribe(topic, MqttQos.atLeastOnce);
    }
    _setState(MqttSessionState.connected);
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> batch) {
    for (final received in batch) {
      final message = received.payload;
      if (message is! MqttPublishMessage) continue;
      _messages.add(
        MqttInboundMessage(
          topic: received.topic,
          // utf8 et non bytesToStringAsString : les payloads peuvent contenir des accents.
          payload: utf8.decode(message.payload.message, allowMalformed: true),
          retained: message.header?.retain ?? false,
        ),
      );
    }
  }

  void _setState(MqttSessionState next) {
    if (next == _sessionState || _sessionStates.isClosed) return;
    _sessionState = next;
    _sessionStates.add(next);
  }
}

/// Une seule connexion MQTT pour toute l'app, fermée avec le `ProviderScope`.
final mqttServiceProvider = Provider<MqttService>((ref) {
  final service = MqttService(ref.watch(appConfigProvider));
  ref.onDispose(service.dispose);
  return service;
});
