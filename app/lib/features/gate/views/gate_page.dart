import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewmodels/gate_command_view_model.dart';
import '../viewmodels/gate_view_model.dart';
import 'widgets/gate_command_panel.dart';
import 'widgets/gate_status_card.dart';

/// Écran principal : observe les ViewModels et délègue l'affichage aux widgets.
class GatePage extends ConsumerWidget {
  const GatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(gateViewModelProvider);
    final commandState = ref.watch(gateCommandViewModelProvider);
    final commands = ref.read(gateCommandViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Sésame')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // Défilement : le texte agrandi (accessibilité) ne doit jamais déborder.
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GateStatusCard(
                    gate: viewState.gate,
                    device: viewState.device,
                  ),
                  const SizedBox(height: 24),
                  GateCommandPanel(
                    gateStatus: viewState.gate?.status,
                    commandState: commandState,
                    onCommand: commands.request,
                    onRetry: commands.retry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
