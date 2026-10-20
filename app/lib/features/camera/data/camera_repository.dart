import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';

/// Échec d'ouverture de la caméra, avec un message affichable tel quel.
class CameraException implements Exception {
  const CameraException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Flux vidéo en cours. [close] libère la connexion WebRTC et prévient le
/// serveur : un flux oublié consommerait batterie et bande passante.
class CameraSession {
  CameraSession(this.stream, this._close);

  final MediaStream stream;
  final Future<void> Function() _close;
  Future<void>? _closing;

  /// Idempotent : mise en arrière-plan puis sortie de l'écran ferment toutes
  /// deux la session, sans double fermeture côté natif.
  Future<void> close() => _closing ??= _close();
}

/// Lecture de la caméra du portail en WebRTC, via WHEP (Model du MVVM).
///
/// WHEP : l'offre SDP part dans un simple POST HTTP et la réponse revient
/// dans le corps. Pas de serveur de signalisation à écrire ni à héberger.
/// Flux en réception seule : le visiteur ne voit ni n'entend l'utilisateur.
class CameraRepository {
  CameraRepository(
    this._client,
    this._whepUrl, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Uri? _whepUrl;
  final Duration timeout;

  Future<CameraSession> open() async {
    final url = _whepUrl;
    if (url == null) {
      throw const CameraException('Caméra non configurée (CAMERA_URL).');
    }

    // Aucun serveur STUN : MediaMTX annonce lui-même les adresses par
    // lesquelles on le joint, et rien ne doit sortir vers un service tiers.
    final pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
    try {
      for (final kind in [
        RTCRtpMediaType.RTCRtpMediaTypeVideo,
        RTCRtpMediaType.RTCRtpMediaTypeAudio,
      ]) {
        await pc.addTransceiver(
          kind: kind,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }

      final remoteStream = Completer<MediaStream>();
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty && !remoteStream.isCompleted) {
          remoteStream.complete(event.streams.first);
        }
      };
      final connected = Completer<void>();
      pc.onConnectionState = (state) {
        if (connected.isCompleted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          connected.complete();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          connected.completeError(
            const CameraException('Flux vidéo injoignable (réseau).'),
          );
        }
      };
      final gathered = Completer<void>();
      pc.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !gathered.isCompleted) {
          gathered.complete();
        }
      };

      await pc.setLocalDescription(await pc.createOffer());
      // Sans STUN, la collecte des candidats locaux est quasi immédiate.
      // Plafonnée quand même : on envoie ce qu'on a plutôt que d'attendre.
      await gathered.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      final offer = await pc.getLocalDescription();

      final http.Response response;
      try {
        response = await _client
            .post(
              url,
              headers: {'Content-Type': 'application/sdp'},
              body: offer!.sdp,
            )
            .timeout(timeout);
      } on TimeoutException {
        throw const CameraException('Le serveur vidéo n\'a pas répondu.');
      } on Exception catch (e) {
        throw CameraException('Serveur vidéo injoignable ($e).');
      }
      if (response.statusCode == 404) {
        throw const CameraException('La caméra du portail n\'émet pas.');
      }
      if (response.statusCode != 201) {
        throw CameraException(
          'Le serveur vidéo a répondu ${response.statusCode}.',
        );
      }
      await pc.setRemoteDescription(
        RTCSessionDescription(response.body, 'answer'),
      );

      // Connexion vérifiée avant de rendre la main : une vidéo noire sans
      // explication serait pire qu'un message d'erreur.
      await connected.future.timeout(
        timeout,
        onTimeout: () =>
            throw const CameraException('Flux vidéo injoignable (délai).'),
      );
      final stream = await remoteStream.future.timeout(timeout);

      // Android traite le flux comme un appel et joue le son dans l'écouteur,
      // inaudible téléphone à la main. Un interphone se regarde, pas à
      // l'oreille : haut-parleur, ou casque Bluetooth s'il y en a un.
      try {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } on Object catch (e) {
        debugPrint('Caméra : sortie audio inchangée ($e)');
      }

      // Ressource WHEP créée par le serveur : la supprimer libère sa session
      // tout de suite, au lieu d'attendre qu'il constate la coupure.
      final location = response.headers['location'];
      return CameraSession(stream, () async {
        await pc.close();
        if (location != null) {
          unawaited(
            _client
                .delete(url.resolve(location))
                .then<void>((_) {}, onError: (Object _) {}),
          );
        }
      });
    } on Object catch (e) {
      await pc.close();
      if (e is CameraException) rethrow;
      debugPrint('Caméra : $e');
      throw const CameraException('Impossible d\'ouvrir la caméra.');
    }
  }
}

final cameraRepositoryProvider = Provider<CameraRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return CameraRepository(client, ref.watch(appConfigProvider).cameraUrl);
});
