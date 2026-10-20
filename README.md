# Sésame

Interphone et portail connectés : être prévenu quand on sonne, voir qui est là, ouvrir à distance, connaître l'état du portail en temps réel.

Projet de fin de module (Flutter + IoT), réalisé seul. Le portail est simulé par un ESP32 sous Wokwi, la caméra par la webcam du PC.

## Fonctionnalités

- **Sonnette** : appui sur le bouton de l'ESP32 → notification push sur le téléphone, même app fermée.
- **État du portail en temps réel** (`open` / `closed` / `opening` / `closing`), publié par l'ESP32, seule source de vérité.
- **Ouverture et fermeture à distance**, avec confirmation biométrique pour ouvrir et accusé de réception de l'ESP32.
- **« Qui est là ? »** : vidéo et son de la caméra du portail en WebRTC, ouverte automatiquement à la sonnerie.
- **Historique** des sonneries, ouvertures et fermetures, avec graphique.
- **Hors ligne** : dernier état connu affiché avec son âge, commandes mises en attente puis abandonnées après 60 s, bannière de connexion.
- **Statut de l'équipement** (en ligne / hors ligne) par MQTT Last Will.
- **Connexion obligatoire** (Firebase Auth, comptes créés dans la console, pas d'inscription dans l'app).

## Architecture

```
[ESP32 Wokwi] --MQTT/TLS 8883--> [HiveMQ Cloud] <--MQTT/TLS--> [App Flutter]
                                       |                          ^   ^
                                       v                          |   |
                                [Node-RED (Docker)] --FCM push----+   |
                                   |          \                       |
                                   v           `--API REST /api/events+
                              [InfluxDB]                              |
                                                                      |
[Webcam + micro] --ffmpeg RTSP--> [MediaMTX (Docker)] --WebRTC WHEP---+
```

- **App Flutter** en MVVM strict : la View ne connaît que son ViewModel (Notifier Riverpod), le ViewModel ne connaît que des repositories, seuls les repositories touchent MQTT, HTTP et Hive.
- **Hive chiffré** (AES, clé dans le Keychain / Keystore) comme source de vérité locale : l'UI ne lit jamais le réseau directement.
- **Node-RED** historise dans InfluxDB (rétention 30 jours), envoie les push FCM et expose l'API de l'historique : l'app ne touche jamais InfluxDB.
- **Commandes sûres** : `open` / `close` explicites (jamais `toggle`), `cmdId` dédupliqué par l'ESP32, durée de vie de 60 s, refus tant que l'ESP32 n'a pas l'heure (NTP).

Les décisions structurantes sont détaillées dans les [ADR](docs/adr/).

## Dépôt

| Dossier | Contenu |
| --- | --- |
| [`app/`](app/) | Application Flutter (`lib/core/` : MQTT, réseau, stockage, cycle de vie ; `lib/features/` : auth, gate, doorbell, history, camera) |
| [`firmware/`](firmware/) | ESP32 (PlatformIO + Wokwi) : bouton, servomoteur, interrupteur de fin de course, LED |
| [`backend/`](backend/) | `docker-compose.yml` : Node-RED, InfluxDB 2.7, MediaMTX ; flux Node-RED versionnés |
| [`docs/`](docs/) | ADR, préparation de la démo |

## Stack

- **App** : Flutter 3.47 (via FVM), Riverpod 3 (Notifier / AsyncNotifier, providers écrits à la main), go_router, mqtt_client, hive_ce, flutter_secure_storage, local_auth, Firebase (Auth, Messaging), flutter_webrtc, fl_chart.
- **Firmware** : ESP32 DevKit, Arduino, PubSubClient, ArduinoJson, WiFiClientSecure.
- **Backend** : Node-RED 4.1, InfluxDB 2.7, MediaMTX 1.21, HiveMQ Cloud, Firebase Cloud Messaging.

## Lancer le projet

Prérequis : Docker, [FVM](https://fvm.app), Android Studio (émulateur arm64 **avec Google Play**, nécessaire pour FCM), VS Code + PlatformIO + Wokwi, ffmpeg, un cluster HiveMQ Cloud et un projet Firebase.

### 1. Secrets

Aucun secret n'est versionné. Chaque fichier a un modèle `*.example` à copier puis remplir :

| Fichier | Modèle |
| --- | --- |
| `app/env.json` | `app/env.example.json` |
| `backend/.env` | `backend/.env.example` |
| `firmware/include/secrets.h` | `firmware/include/secrets.example.h` |
| `app/android/app/google-services.json` | console Firebase |
| `backend/firebase-service-account.json` | console Firebase (compte de service, pour les push) |

Utiliser trois identifiants MQTT distincts : ESP32, app et Node-RED.

### 2. Backend

```bash
cd backend
docker compose up -d
curl http://localhost:1880/api/events   # {"count":0,"events":[]}
```

### 3. Caméra (facultatif)

```bash
cd backend/mediamtx
./stream-webcam.sh        # macOS ; stream-webcam.ps1 sous Windows
```

Contrôle dans un navigateur : <http://localhost:8889/portail>.

### 4. Firmware

Ouvrir `firmware/` dans VS Code, puis *PlatformIO: Build* et *Wokwi: Start Simulator* (Wokwi lance le dernier binaire compilé, il ne compile pas). Le moniteur série doit afficher `NTP : heure synchronisée` puis `MQTT : connecté`. Garder l'onglet Wokwi visible : masqué, la simulation se met en pause.

### 5. App

```bash
cd app
fvm flutter pub get
fvm flutter run -d emulator-5554 --dart-define-from-file=env.json
```

Sur l'émulateur Android, la machine hôte est joignable en `10.0.2.2` (Node-RED, MediaMTX).

## Qualité

```bash
cd app
fvm flutter analyze
fvm flutter test          # 130 tests
```

Commits au format Conventional Commits, une branche par étape fusionnée dans `main` en `--no-ff`.

## Sécurité et données personnelles

- MQTT uniquement en TLS (8883), WebRTC chiffré (DTLS-SRTP), stockage local chiffré.
- Biométrie avant chaque ouverture, anti-rejeu par `cmdId` + date d'expiration.
- `siteId` opaque, aucun identifiant utilisateur dans les messages, historique conservé 30 jours, aucune image ni vidéo enregistrée.
- Limites connues (identifiants MQTT dans l'APK, certificat non vérifié par l'ESP32 simulé, MediaMTX sans authentification sur le réseau local).
