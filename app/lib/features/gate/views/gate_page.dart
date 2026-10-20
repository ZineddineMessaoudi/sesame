import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/connectivity/connection_notifier.dart';
import '../../../core/connectivity/connectivity_banner.dart';
import '../../auth/viewmodels/session_view_model.dart';
import '../../doorbell/viewmodels/doorbell_view_model.dart';
import '../../doorbell/views/widgets/doorbell_alert.dart';

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
    final quality = ref.watch(connectionProvider);
    final ring = ref.watch(doorbellViewModelProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sésame'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.camera),
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Caméra',
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.history),
            icon: const Icon(Icons.history),
            tooltip: 'Historique',
          ),
          IconButton(
            onPressed: ref.read(sessionViewModelProvider.notifier).signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ConnectivityBanner(quality: quality),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  // Défilement : le texte agrandi (accessibilité) ne doit jamais déborder.
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // En tête : une sonnerie est l'information la plus urgente.
                        if (ring != null) ...[
                          DoorbellAlert(
                            ring: ring,
                            onDismiss: ref
                                .read(doorbellViewModelProvider.notifier)
                                .acknowledge,
                            onView: () {
                              ref
                                  .read(doorbellViewModelProvider.notifier)
                                  .acknowledge();
                              context.push(AppRoutes.camera);
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        GateStatusCard(
                          gate: viewState.gate,
                          device: viewState.visibleDevice,
                          isLive: viewState.isLive,
                          confirmedAt: viewState.confirmedAt,
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
          ],
        ),
      ),
    );
  }
}
