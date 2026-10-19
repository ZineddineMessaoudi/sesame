import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Réception des notifications push (FCM).
///
/// Complément indispensable de MQTT : l'app coupe sa session en arrière-plan
/// par sobriété énergétique (§5), donc seul un push peut encore la joindre.
/// C'est Node-RED, lui toujours connecté, qui publie vers le topic du site (§9).
///
/// Répartition voulue, qui évite toute notification en double :
/// - app au premier plan -> MQTT fait foi (carte à l'écran + notification
///   locale) ; Android n'affiche pas de lui-même un push reçu au premier plan ;
/// - app en arrière-plan ou fermée -> le système affiche le push FCM.
class PushService {
  /// [messaging] est une fonction et non une instance : `FirebaseMessaging.instance`
  /// lève si Firebase n'a pas pu s'initialiser, et cette erreur doit survenir
  /// dans le `Future` de [subscribe], pas à la création du provider.
  PushService(this._siteId, {FirebaseMessaging Function()? messaging})
    : _messaging = messaging ?? (() => FirebaseMessaging.instance);

  final FirebaseMessaging Function() _messaging;

  /// Topic FCM = identifiant opaque du site. Aucun identifiant utilisateur
  /// dans le routage des messages (minimisation, §10).
  final String _siteId;

  /// Idempotent : FCM ignore un abonnement déjà actif.
  Future<void> subscribe() async {
    final messaging = _messaging();
    await messaging.requestPermission();
    await messaging.subscribeToTopic(_siteId);
    debugPrint('Push : abonné au topic FCM "$_siteId"');
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(appConfigProvider).siteId),
);
