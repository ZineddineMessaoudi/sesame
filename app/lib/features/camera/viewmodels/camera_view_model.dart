import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../data/camera_repository.dart';

/// ViewModel de l'écran caméra : `AsyncValue` couvre les trois états
/// attendus (connexion en cours, flux en direct, erreur).
class CameraViewModel extends AsyncNotifier<MediaStream> {
  @override
  Future<MediaStream> build() async {
    final session = await ref.watch(cameraRepositoryProvider).open();
    // Écran quitté pendant la connexion : on ferme aussitôt le flux obtenu.
    if (!ref.mounted) {
      await session.close();
      throw const CameraException('Écran fermé.');
    }
    ref.onDispose(session.close);
    return session.stream;
  }

  /// Nouvelle connexion complète : l'ancienne est fermée par `onDispose`.
  void retry() => ref.invalidateSelf();
}

/// `autoDispose` : quitter l'écran coupe la vidéo. L'écran est lui-même
/// quitté quand l'app passe en arrière-plan (voir `CameraPage`) : le flux ne
/// tourne jamais en tâche de fond (sobriété, §5).
final cameraViewModelProvider =
    AsyncNotifierProvider.autoDispose<CameraViewModel, MediaStream>(
      CameraViewModel.new,
    );
