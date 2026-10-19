import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewmodels/gate_view_model.dart';
import 'widgets/gate_status_card.dart';

/// Écran principal : observe le `GateViewModel` et délègue l'affichage aux widgets.
class GatePage extends ConsumerWidget {
  const GatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(gateViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sésame')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // Défilement : le texte agrandi (accessibilité) ne doit jamais déborder.
            padding: const EdgeInsets.all(16),
            child: GateStatusCard(
              gate: viewState.gate,
              device: viewState.device,
            ),
          ),
        ),
      ),
    );
  }
}
