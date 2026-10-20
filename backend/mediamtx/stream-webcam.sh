#!/usr/bin/env bash
# Version macOS de stream-webcam.ps1 : publie la caméra et le micro du Mac vers
# MediaMTX. Mêmes réglages d'encodage, seule la capture change (avfoundation).
#
# Usage (depuis backend/mediamtx) :
#   ./stream-webcam.sh                            # caméra et micro du Mac
#   ./stream-webcam.sh "Caméra de « iPhone »" 0   # par nom ou par numéro
# Lister les périphériques : ffmpeg -f avfoundation -list_devices true -i ""
# Au premier lancement, macOS demande l'accès caméra et micro pour le Terminal.
set -euo pipefail

# Par nom plutôt que par numéro : avec un iPhone à proximité (Continuité), ses
# caméra et micro s'intercalent dans la liste et décalent les numéros.
CAMERA="${1:-Caméra MacBook Air}"
MICROPHONE="${2:-Micro MacBook Air}"
TARGET="${3:-rtsp://localhost:8554/portail}"

# - capture en nv12 : format natif de la caméra (yuv420p est refusé en entrée) ;
# - H.264 baseline sans images B (zerolatency) : décodable par WebRTC et Android ;
# - une image clé par seconde (-g 30) : l'image apparaît en moins d'1 s ;
# - mise à l'échelle en 640 px : la caméra intégrée capture en 720p, inutile ici ;
# - Opus 48 kHz : seul codec audio que WebRTC impose partout.
exec ffmpeg -hide_banner -loglevel warning \
  -f avfoundation -framerate 30 -video_size 1280x720 -pixel_format nv12 \
  -i "${CAMERA}:${MICROPHONE}" \
  -vf scale=640:-2 \
  -c:v libx264 -preset ultrafast -tune zerolatency -profile:v baseline -pix_fmt yuv420p -g 30 -b:v 1M \
  -c:a libopus -ar 48000 -ac 1 -b:a 48k \
  -f rtsp -rtsp_transport tcp "$TARGET"
