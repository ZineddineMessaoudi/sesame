import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../data/doorbell_repository.dart';
import '../data/models/doorbell_ring.dart';

/// ViewModel de la sonnette : retient la dernière sonnerie à afficher et
/// déclenche la notification système.
///
/// L'état est `null` tant que personne n'a sonné, ou une fois la sonnerie vue.
class DoorbellViewModel extends Notifier<DoorbellRing?> {
  /// Identifiant fixe : une nouvelle sonnerie remplace la précédente au lieu
  /// d'empiler les notifications. Un visiteur impatient qui appuie cinq fois
  /// ne doit pas produire cinq alertes.
  static const notificationId = 1;

  @override
  DoorbellRing? build() {
    // Au démarrage, et non au premier coup de sonnette : un provider Riverpod
    // est paresseux, et demander l'autorisation Android 13+ seulement à la
    // première sonnerie ferait arriver celle-ci pendant que la boîte de
    // dialogue est encore ouverte — la notification serait perdue.
    // Une initialisation impossible (plugin absent, autorisation refusée) ne
    // doit pas empêcher l'affichage à l'écran, qui lui ne dépend de rien.
    unawaited(
      ref
          .watch(notificationServiceProvider)
          .initialize()
          .catchError(
            (Object e) =>
                debugPrint('Notifications : initialisation impossible ($e)'),
          ),
    );

    final sub = ref
        .watch(doorbellRepositoryProvider)
        .watchRings()
        .listen(_onRing);
    ref.onDispose(sub.cancel);
    return null;
  }

  void _onRing(DoorbellRing ring) {
    state = ring;
    // L'app peut être au premier plan sans que personne ne regarde l'écran :
    // l'affichage ne suffit pas, il faut la notification système (§13).
    unawaited(
      ref
          .read(notificationServiceProvider)
          .show(
            id: notificationId,
            title: 'Quelqu\'un sonne',
            body: 'Appui sur la sonnette du portail.',
          ),
    );
  }

  /// L'utilisateur a pris connaissance de la sonnerie.
  void acknowledge() => state = null;
}

final doorbellViewModelProvider =
    NotifierProvider<DoorbellViewModel, DoorbellRing?>(DoorbellViewModel.new);
