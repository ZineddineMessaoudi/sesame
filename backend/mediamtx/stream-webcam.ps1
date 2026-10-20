# Publie la webcam et le micro du PC vers MediaMTX : c'est la « caméra du portail »
# de la démo (Wokwi ne simule pas de caméra, §2). ffmpeg tourne sur l'hôte car
# Docker n'a pas accès à la webcam.
#
# Usage (PowerShell, depuis backend/mediamtx) :
#   .\stream-webcam.ps1
#   .\stream-webcam.ps1 -Camera "Ma webcam" -Microphone "Microphone (USB)"
# Lister les périphériques : ffmpeg -list_devices true -f dshow -i dummy

param(
    [string]$Camera = "usb-webcam",
    [string]$Microphone = "Microphone (usb-audio)",
    [string]$Target = "rtsp://localhost:8554/portail"
)

# Choix d'encodage, tous imposés par WebRTC ou par la latence :
# - H.264 baseline, sans images B (zerolatency) : décodable par tous les navigateurs et par Android ;
# - une image clé par seconde (-g 30) : un spectateur qui arrive voit l'image en moins d'1 s ;
# - Opus 48 kHz : seul codec audio que WebRTC impose partout.
ffmpeg -hide_banner -loglevel warning `
    -f dshow -rtbufsize 64M -video_size 640x480 -framerate 30 `
    -i video="$Camera":audio="$Microphone" `
    -c:v libx264 -preset ultrafast -tune zerolatency -profile:v baseline -pix_fmt yuv420p -g 30 -b:v 1M `
    -c:a libopus -ar 48000 -ac 1 -b:a 48k `
    -f rtsp -rtsp_transport tcp $Target
