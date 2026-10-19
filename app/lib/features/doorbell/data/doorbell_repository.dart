import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/mqtt/mqtt_service.dart';
import '../../../core/mqtt/mqtt_topics.dart';
import 'models/doorbell_ring.dart';

/// Accès aux sonneries (Model du MVVM) : seule couche de la feature qui
/// connaît MQTT. Traduit `doorbell/ring` en événements métier dédupliqués.
class DoorbellRepository {
  DoorbellRepository(this._mqtt, this._topics, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _mqtt.subscribe(_topics.doorbellRing);
    _sub = _mqtt.messages.listen(_onMessage);
  }

  final MqttService _mqtt;
  final MqttTopics _topics;
  final DateTime Function() _clock;
  late final StreamSubscription<MqttInboundMessage> _sub;

  /// Mêmes 16 identifiants mémorisés que la déduplication de l'ESP32 (§4) :
  /// assez pour absorber les doublons QoS 1 sans grossir indéfiniment.
  static const _recentIdsKept = 16;
  final _recentIds = Queue<String>();

  final _rings = StreamController<DoorbellRing>.broadcast();

  /// Un événement par coup de sonnette, doublons de livraison déjà écartés.
  Stream<DoorbellRing> watchRings() => _rings.stream;

  Future<void> dispose() async {
    await _sub.cancel();
    await _rings.close();
  }

  void _onMessage(MqttInboundMessage message) {
    if (message.topic != _topics.doorbellRing) return;
    final ring = DoorbellRing.tryParse(message.payload, receivedAt: _clock());
    if (ring == null) {
      debugPrint('Sonnette : payload ignoré (${message.payload})');
      return;
    }
    // Avec QoS 1 le broker peut livrer deux fois : on ne fait pas sonner
    // le téléphone deux fois pour un seul appui sur le bouton.
    if (!_isNew(ring.ringId)) return;
    _rings.add(ring);
  }

  bool _isNew(String ringId) {
    if (_recentIds.contains(ringId)) return false;
    _recentIds.addLast(ringId);
    if (_recentIds.length > _recentIdsKept) _recentIds.removeFirst();
    return true;
  }
}

final doorbellRepositoryProvider = Provider<DoorbellRepository>((ref) {
  final repository = DoorbellRepository(
    ref.watch(mqttServiceProvider),
    MqttTopics(ref.watch(appConfigProvider).siteId),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
