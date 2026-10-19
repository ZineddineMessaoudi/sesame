import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/biometric_repository.dart';
import '../data/gate_repository.dart';
import '../data/models/gate_command.dart';
import '../data/outbox_service.dart';

/// Étapes d'une commande vues par l'écran. `sealed` : la View doit traiter tous les cas.
sealed class CommandUiState {
  const CommandUiState();
}

class CommandIdle extends CommandUiState {
  const CommandIdle();
}

/// Attente de la biométrie.
class CommandAuthenticating extends CommandUiState {
  const CommandAuthenticating(this.action);
  final GateAction action;
}

/// Commande publiée, attente de l'ack (« Ouverture demandée… »).
class CommandSending extends CommandUiState {
  const CommandSending(this.action);
  final GateAction action;
}

class CommandFinished extends CommandUiState {
  const CommandFinished(this.action, this.outcome);
  final GateAction action;
  final CommandOutcome outcome;
}

class CommandIdentityRefused extends CommandUiState {
  const CommandIdentityRefused(this.action, this.check);
  final GateAction action;
  final IdentityCheck check;
}

/// ViewModel des commandes. Optimistic UI limitée (§5) : il n'affiche jamais
/// « Ouvert » lui-même ; seul `gate/state` (GateViewModel) fait foi.
class GateCommandViewModel extends Notifier<CommandUiState> {
  @override
  CommandUiState build() {
    // Une commande rejouée par l'outbox n'a pas d'auteur devant l'écran :
    // c'est ici qu'elle redevient visible, notamment « Expirée, non envoyée ».
    final sub = ref.watch(outboxServiceProvider).results.listen((result) {
      // Jamais par-dessus une commande en cours : l'utilisateur attend sa réponse.
      if (isBusy) return;
      state = CommandFinished(result.command.action, result.outcome);
    });
    ref.onDispose(sub.cancel);
    return const CommandIdle();
  }

  bool get isBusy => state is CommandAuthenticating || state is CommandSending;

  Future<void> request(GateAction action) async {
    if (isBusy) return; // double appui : une seule commande à la fois

    // Biométrie avant toute ouverture (§10). La fermeture n'en demande pas :
    // elle ne fait entrer personne, et doit rester rapide.
    if (action == GateAction.open) {
      state = CommandAuthenticating(action);
      final check = await ref
          .read(biometricRepositoryProvider)
          .confirm('Confirmez votre identité pour ouvrir le portail');
      if (!ref.mounted) return;
      if (check != IdentityCheck.confirmed) {
        state = CommandIdentityRefused(action, check);
        return;
      }
    }

    final repository = ref.read(gateRepositoryProvider);
    // Créée après la biométrie : le TTL de 60 s part de la confirmation, pas de l'appui.
    final command = repository.newCommand(action);
    state = CommandSending(action);
    var outcome = await repository.sendCommand(command);

    // Hors ligne : la commande est mise en attente plutôt que perdue (§5).
    // Elle garde son cmdId et son TTL : si le réseau tarde, elle expirera
    // sans jamais partir, ce qui est le comportement voulu.
    if (outcome == CommandOutcome.notSent) {
      await ref.read(outboxServiceProvider).enqueue(command);
      outcome = CommandOutcome.queued;
    }

    if (!ref.mounted) return;
    state = CommandFinished(action, outcome);
  }

  /// « Réessayer » = nouvelle commande : nouveau cmdId, nouveau TTL, nouvelle biométrie (§4).
  Future<void> retry(GateAction action) => request(action);
}

final gateCommandViewModelProvider =
    NotifierProvider<GateCommandViewModel, CommandUiState>(
      GateCommandViewModel.new,
    );
