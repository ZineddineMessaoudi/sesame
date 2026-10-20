import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../gate/viewmodels/gate_command_view_model.dart';
import '../../gate/viewmodels/gate_view_model.dart';
import '../../gate/views/widgets/gate_command_panel.dart';
import '../viewmodels/camera_view_model.dart';

/// Écran « Qui est là ? » : vidéo en direct du portail, et les commandes
/// juste en dessous pour ouvrir sans changer d'écran.
class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  // Le renderer est un objet d'affichage natif : il vit avec la View, pas
  // dans le ViewModel, qui ne connaît que le flux.
  //
  // Un renderer neuf par flux : chaque connexion (réessai, retour à l'écran)
  // repart d'un afficheur propre, sans état hérité du flux précédent.
  RTCVideoRenderer? _renderer;
  MediaStream? _shown;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _leaveWhenHidden);
    // Effet de bord hors du build : le renderer suit chaque nouveau flux.
    ref.listenManual(
      cameraViewModelProvider,
      (_, next) => _show(next.value),
      fireImmediately: true,
    );
  }

  /// App en arrière-plan : on quitte l'écran, ce qui coupe le flux
  /// (`autoDispose`) ; un appui sur la notification en rouvre un neuf.
  /// Exception : le PIN d'une ouverture met aussi l'app en pause. On reste
  /// alors sur l'écran, l'utilisateur est en train d'ouvrir au visiteur.
  void _leaveWhenHidden() {
    if (ref.read(gateCommandViewModelProvider.notifier).isBusy) return;
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _show(MediaStream? stream) async {
    if (identical(stream, _shown)) return;
    _shown = stream;
    final previous = _renderer;
    if (previous != null) {
      setState(() => _renderer = null);
      previous.srcObject = null;
      await previous.dispose();
    }
    if (stream == null) return;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    // Écran quitté, ou flux déjà remplacé pendant l'initialisation.
    if (!mounted || !identical(_shown, stream)) {
      await renderer.dispose();
      return;
    }
    renderer.srcObject = stream;
    setState(() => _renderer = renderer);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _renderer?.srcObject = null;
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = ref.watch(cameraViewModelProvider);
    final gate = ref.watch(gateViewModelProvider);
    final commandState = ref.watch(gateCommandViewModelProvider);
    final commands = ref.read(gateCommandViewModelProvider.notifier);
    final renderer = _renderer;

    return Scaffold(
      appBar: AppBar(title: const Text('Qui est là ?')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: Colors.black,
                  child: switch (camera) {
                    AsyncData() when renderer != null => Semantics(
                      label: 'Vidéo en direct du portail',
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RTCVideoView(
                              renderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitContain,
                            ),
                          ),
                          const Positioned(
                            top: 8,
                            left: 8,
                            child: _LiveBadge(),
                          ),
                        ],
                      ),
                    ),
                    AsyncError(:final error) => _CameraMessage(
                      icon: Icons.videocam_off_outlined,
                      text: error.toString(),
                      action: TextButton(
                        onPressed: ref
                            .read(cameraViewModelProvider.notifier)
                            .retry,
                        child: const Text('Réessayer'),
                      ),
                    ),
                    _ => const _CameraMessage(
                      icon: Icons.videocam_outlined,
                      text: 'Connexion à la caméra…',
                      action: CircularProgressIndicator(),
                    ),
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            GateCommandPanel(
              gateStatus: gate.gate?.status,
              commandState: commandState,
              onCommand: commands.request,
              onRetry: commands.retry,
            ),
          ],
        ),
      ),
    );
  }
}

/// « En direct » en texte et pas seulement en couleur (§11).
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'EN DIRECT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }
}
