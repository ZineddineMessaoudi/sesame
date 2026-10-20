# Préparer le Mac pour la démo

Le développement s'est terminé sur le PC Windows le 20/10. La démo du 21/10 se fait sur le MacBook Air. Ce document liste ce qu'il faut installer et vérifier, dans l'ordre. Prévoir **1 h 30 à 2 h**, à faire **le 20/10**, pas le matin de la soutenance.

## 0. Avant de commencer

- [ ] **Espace disque** : au moins **15 Go libres** (images Docker, émulateur, compilation Android).
- [ ] **PC Windows éteint côté backend** (`docker compose down` dans `backend/`). Deux Node-RED connectés au même HiveMQ écriraient chaque évènement deux fois et enverraient chaque notification en double.
- [ ] **Ne pas mettre à jour Xcode** avant la soutenance.

## 1. Récupérer le code

```bash
cd ~/dev/sesame
git checkout main && git pull
git checkout chore/tests-docs && git pull   # script webcam macOS + ce document
```

## 2. Recopier les secrets

Aucun de ces fichiers n'est dans Git. Les copier depuis le PC (gestionnaire de mots de passe ou clé USB), jamais par Git ni par e-mail.

| Fichier | Remarque |
| --- | --- |
| `app/env.json` | Doit contenir `CAMERA_URL` = `http://10.0.2.2:8889/portail/whep` |
| `app/android/app/google-services.json` | Firebase Android |
| `firmware/include/secrets.h` | Wi-Fi Wokwi + identifiants MQTT de l'ESP32 |
| `backend/.env` | Mettre `MEDIAMTX_HOST_IP=127.0.0.1` (voir plus bas) |
| `backend/firebase-service-account.json` | Clé de signature des push FCM |

- [ ] Garder **exactement la même valeur** de `NODE_RED_CREDENTIAL_SECRET` que sur le PC : elle déchiffre `flows_cred.json`, qui est versionné. Avec une autre valeur, Node-RED ne retrouve plus ses identifiants MQTT.
- [ ] `MEDIAMTX_HOST_IP=127.0.0.1` : depuis le passage des médias WebRTC en TCP, l'émulateur joint MediaMTX par `10.0.2.2`. L'IP du réseau de l'école n'est plus nécessaire.
- [ ] Vérifier qu'aucun secret n'apparaît dans `git status`.

## 3. Backend (Node-RED, InfluxDB, MediaMTX)

```bash
cd backend
docker compose up -d
docker compose ps                         # 3 conteneurs « running »
curl http://localhost:1880/api/events     # doit répondre du JSON
```

- Les images existent en version Apple Silicon, rien à changer.
- **InfluxDB repart vide** sur le Mac : l'écran Historique et son graphique seront vides au début. Faire quelques sonneries, ouvertures et fermetures avant la soutenance.
- Dans les logs de Node-RED (`docker logs sesame-node-red`), vérifier `Connected to broker`.

## 4. Caméra (webcam + micro du Mac)

```bash
brew install ffmpeg
cd backend/mediamtx
./stream-webcam.sh            # caméra 0, micro 0 (caméra intégrée du Mac)
```

- Au premier lancement, macOS demande l'accès **caméra et micro pour le Terminal** : accepter. En cas de refus : Réglages Système → Confidentialité et sécurité → Caméra / Micro.
- Lister les périphériques : `ffmpeg -f avfoundation -list_devices true -i ""`, puis `./stream-webcam.sh <caméra> <micro>`.
- [ ] Vérifier l'image et le son dans le navigateur : <http://localhost:8889/portail>.
- **Si MediaMTX redémarre, ffmpeg s'arrête et ne se reconnecte pas** : relancer le script. Symptôme dans l'app : « La caméra du portail n'émet pas ».
- Script non testé sur Mac (écrit depuis le PC). Si ffmpeg refuse la résolution ou la cadence, ajuster `-video_size` / `-framerate` dans le script.

## 5. App Flutter

```bash
cd app
fvm flutter pub get
fvm flutter run -d emulator-5554 --dart-define-from-file=env.json
```

- Émulateur **Android arm64 avec Google Play** (nécessaire pour FCM). adb n'est pas dans le PATH : `~/Library/Android/sdk/platform-tools/adb`.
- La première compilation est longue (bibliothèque WebRTC).
- [ ] **Biométrie** : définir un code PIN (Paramètres → Sécurité), puis enregistrer une empreinte (*Extended Controls* → *Fingerprint* → *Touch sensor*).
- [ ] **Autoriser les notifications** quand l'app le demande.
- [ ] **Se connecter dans l'app** (compte Firebase de démo). La session est conservée : rien à taper devant le jury.
- Clavier AZERTY : l'émulateur ne transmet pas Alt Gr + à. Pour taper `@` : `adb shell input text "adresse@exemple.fr"`, ou le clavier virtuel.

## 6. Firmware et Wokwi

```bash
code ~/dev/sesame/firmware     # ouvrir firmware/ comme dossier racine
```

- [ ] **Activer la licence Wokwi aujourd'hui (20/10)**, pour qu'elle soit valide le 21.
- [ ] *PlatformIO: Build* **avant** *Wokwi: Start Simulator* : Wokwi ne compile pas, il lance le dernier binaire compilé (`.pio/` n'est pas versionné).
- Le moniteur série doit afficher `NTP : heure synchronisée` puis `MQTT : connecté`.
- **Garder l'onglet Wokwi visible** : masqué, la simulation se met en pause et l'ESP32 se fige (horloge, keep-alive, commandes).
- Secours : copie **privée** du projet sur wokwi.com (`diagram.json` + `main.cpp` identiques).

## 7. Répétition complète

- [ ] **Sonnette, app fermée** : bouton Wokwi → push sur l'émulateur → appui → l'app s'ouvre sur « Qui est là ? » avec l'image et le son.
- [ ] **Ouverture** : « Ouvrir le portail » + **empreinte** (plutôt que le PIN : l'écran du PIN met l'app en pause et coupe la vidéo quelques secondes) → servo dans Wokwi → `opening` puis `open`.
- [ ] **Hors ligne** : mode avion sur l'émulateur → bannière hors ligne, dernier état avec son âge → « Ouvrir » → commande en attente → « Expirée, non envoyée » au bout de 60 s.
- [ ] **Équipement hors ligne** : arrêter Wokwi → « hors ligne » affiché en ~45 s (LWT).
- [ ] **Déconnexion** : se déconnecter → une sonnerie ne déclenche plus rien → se reconnecter.
- [ ] **Historique** : les évènements de la répétition apparaissent, avec le graphique.

## 8. Le matin de la soutenance (20 min avant)

- [ ] Wi-Fi ou partage de connexion actif (HiveMQ et FCM sont dans le cloud).
- [ ] `docker compose up -d` dans `backend/`, puis `./stream-webcam.sh` dans `backend/mediamtx/`.
- [ ] Émulateur lancé, app ouverte et **connectée**, portail affiché « en direct ».
- [ ] Wokwi : *Build* puis *Start Simulator*, onglet **visible**, `MQTT : connecté` au moniteur série.
- [ ] Une sonnerie de test → push reçu → caméra OK.
- [ ] Notifications du Mac en « Ne pas déranger », son du Mac coupé ou casque (risque d'effet larsen avec le micro).
