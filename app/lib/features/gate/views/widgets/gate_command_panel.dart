import 'package:flutter/material.dart';

import '../../../auth/data/biometric_repository.dart';
import '../../data/gate_repository.dart';
import '../../data/models/gate_command.dart';
import '../../data/models/gate_state.dart';
import '../../viewmodels/gate_command_view_model.dart';

/// Boutons Ouvrir / Fermer et retour sur la commande en cours. Widget « bête ».
class GateCommandPanel extends StatelessWidget {
  const GateCommandPanel({
    super.key,
    required this.gateStatus,
    required this.commandState,
    required this.onCommand,
    required this.onRetry,
  });

  /// `null` tant que l'état du portail est inconnu : on ne commande pas à l'aveugle.
  final GateStatus? gateStatus;
  final CommandUiState commandState;
  final ValueChanged<GateAction> onCommand;
  final ValueChanged<GateAction> onRetry;

  bool get _busy =>
      commandState is CommandAuthenticating || commandState is CommandSending;

  @override
  Widget build(BuildContext context) {
    final status = gateStatus;
    // Pas d'« Ouvrir » sur un portail déjà ouvert : sans danger (commande idempotente),
    // mais inutile et trompeur.
    final canOpen =
        !_busy &&
        status != null &&
        status != GateStatus.open &&
        status != GateStatus.opening;
    final canClose =
        !_busy &&
        status != null &&
        status != GateStatus.closed &&
        status != GateStatus.closing;
    final feedback = _feedback(commandState);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Boutons empilés pleine largeur : rien ne déborde avec un texte agrandi (§11).
        FilledButton.icon(
          onPressed: canOpen ? () => onCommand(GateAction.open) : null,
          icon: const Icon(Icons.lock_open),
          label: const Text('Ouvrir le portail'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: canClose ? () => onCommand(GateAction.close) : null,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Fermer le portail'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
        if (feedback != null) ...[
          const SizedBox(height: 16),
          _Feedback(
            feedback: feedback,
            busy: _busy,
            onRetry: switch (commandState) {
              // Pas de « Réessayer » sur une commande en attente : elle partira
              // toute seule, et réessayer en empilerait une seconde.
              CommandFinished(:final action, :final outcome)
                  when outcome != CommandOutcome.executed &&
                      outcome != CommandOutcome.queued =>
                () => onRetry(action),
              CommandIdentityRefused(:final action, :final check)
                  when check == IdentityCheck.cancelled =>
                () => onRetry(action),
              _ => null,
            },
          ),
        ],
      ],
    );
  }

  static String? _feedback(CommandUiState state) => switch (state) {
    CommandIdle() => null,
    CommandAuthenticating() => 'Confirmez votre identité…',
    CommandSending(action: GateAction.open) => 'Ouverture demandée…',
    CommandSending(action: GateAction.close) => 'Fermeture demandée…',
    CommandFinished(:final outcome) => switch (outcome) {
      CommandOutcome.executed => 'Commande reçue par le portail.',
      CommandOutcome.noResponse => 'Pas de réponse du portail.',
      CommandOutcome.notSent => 'Hors connexion : commande non envoyée.',
      CommandOutcome.queued =>
        'Hors connexion : en attente, elle partira au retour du réseau.',
      // Jamais publiée : on le dit, plutôt que de laisser croire à une ouverture.
      CommandOutcome.expiredUnsent => 'Expirée, non envoyée.',
      CommandOutcome.rejectedExpired =>
        'Commande refusée : expirée. Vérifiez l\'heure du téléphone.',
      CommandOutcome.rejectedNoTime => 'Le portail n\'a pas encore l\'heure. Réessayez dans quelques secondes.',
    },
    CommandIdentityRefused(:final check) => switch (check) {
      IdentityCheck.unavailable => 'Configurez un verrouillage de l\'écran pour pouvoir ouvrir le portail.',
      _ => 'Identité non confirmée : commande annulée.',
    },
  };
}

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.feedback,
    required this.busy,
    required this.onRetry,
  });

  final String feedback;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // liveRegion : chaque nouveau message est annoncé par le lecteur d'écran.
        Semantics(
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy) ...[
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(child: Text(feedback, textAlign: TextAlign.center)),
            ],
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ],
    );
  }
}
