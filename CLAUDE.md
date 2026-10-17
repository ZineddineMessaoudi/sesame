# Sésame

> Interphone et portail connectés : être prévenu quand on sonne, voir qui est là, ouvrir à distance, connaître l'état du portail en temps réel.

## 1. Contexte

- Toujours expliquer le _pourquoi_ d'un choix (commentaire très court dans le code, ADR dans `docs/adr/` pour les décisions structurantes).
- Avancer par petites étapes vérifiables, jamais tout générer d'un coup.
- Ne pas ajouter de dépendance hors de la liste §6 sans le signaler et justifier.
- Stack imposée par le cours : **Flutter (Dart) + Riverpod + MQTT (HiveMQ Cloud) + Wokwi (ESP32 simulé)**. Node-RED, InfluxDB, Firebase et Hive ont été vus en cours et sont réutilisés.
- **Soutenance le 21 octobre 2026 au matin, projet réalisé seul** (avec Claude Code, autorisé par l'école). Voir les jalons §14.

### Workflow Git avec Claude Code (non négociable)

- **Claude ne commit jamais.** L'auteur signe lui-même tous ses commits.
- Travail découpé en **checkpoints d'environ 45 min**, chacun vérifiable. À chaque checkpoint, Claude s'arrête et donne : ce qui a été fait, comment le vérifier, et un message Conventional Commits prêt à copier. L'auteur valide, commit, push, puis on continue.
- Une branche par étape de la feuille de route (`feat/socle`, `feat/firmware`, `feat/gate-realtime`, `feat/gate-commands`, `feat/offline-first`, `feat/backend-history`, `feat/notifications`, `chore/tests-docs`), fusionnée dans `main` avec `--no-ff`.

### Grille d'évaluation

| Poids | Critère              | Ce que le projet doit montrer                                                               |
| ----- | -------------------- | ------------------------------------------------------------------------------------------- |
| 60 %  | Architecture Flutter | MVVM strict (View / ViewModel / Repository), Riverpod rigoureux, UI fluide et accessible    |
|       | Intégration IoT      | Capteur simulé ↔ app via MQTT, choix du protocole justifié, async maîtrisé                  |
|       | Offline-first        | Stratégie explicite, indicateurs réseau, retry, états loading/error/empty                   |
|       | Sécurité + dossier   | TLS en transit, chiffrement au repos (stockage local), dossier technique justifiant l'archi |
| 20 %  | Soutenance           | Démo live bout en bout (capteur -> écran), défense des choix                                |
| 20 %  | Soft skills          | Git propre et régulier, avancement visible                                                  |

**Règle de priorisation : toute fonctionnalité qui ne sert pas un critère ci-dessus est un bonus et passe après le MVP.**

## 2. Périmètre

### MVP

1. **Sonnette** : appui sur le bouton (Wokwi) -> événement MQTT -> notification push sur le téléphone, même app fermée.
2. **État du portail** temps réel (`open` / `closed` / `opening` / `closing`) + notification à chaque changement.
3. **Commande d'ouverture / fermeture** depuis l'app, avec confirmation biométrique et accusé de réception de l'ESP32.
4. **Historique** des événements (sonneries, ouvertures, fermetures) via Node-RED -> InfluxDB -> API REST.
5. **Offline-first** complet (§5).
6. **Statut de l'équipement** (en ligne / hors ligne) via MQTT Last Will.

### Phase 2 (vidéo) — hors périmètre pour la soutenance du 21/10

Décision : ne pas y toucher, même s'il reste du temps (aucun point dans la grille, risque maximal en démo). Conservée comme évolution documentée dans le dossier.

- **Caméra** : Wokwi ne simule pas de caméra. La caméra est simulée par la **webcam du PC** exposée via **MediaMTX** (Docker), lue dans l'app en WebRTC (ou HLS en repli). Vue à la demande + ouverture automatique de la vue lors d'une sonnerie. Le visiteur ne voit pas l'utilisateur (flux unidirectionnel).

### Bonus (seulement si le reste est terminé)

- Audio bidirectionnel avec le visiteur (WebRTC).
- Écran d'appel entrant natif (type CallKit) à la sonnerie.

## 3. Architecture

```
[ESP32 Wokwi] --MQTT/TLS 8883--> [HiveMQ Cloud] <--MQTT/TLS--> [App Flutter]
                                       |
                                       v
                                  [Node-RED (Docker)]
                                   |      |       \
                                   v      v        v
                            [InfluxDB] [FCM push] [API REST /api/events]
                                                        ^
                                              [App Flutter (historique)]

[Webcam PC] -> [MediaMTX (Docker)] --WebRTC--> [App Flutter]   (phase 2)
```

Justifications à reprendre dans le dossier :

- **MQTT plutôt que HTTP/BLE** : capteur fixe avec Wi-Fi, accès à distance (on est au travail), push temps réel, LWT pour le statut, retain pour l'état courant. BLE exclu : portée ~10 m, incompatible avec le cas d'usage.
- **FCM pour les notifications** : l'app coupe sa connexion MQTT en arrière-plan (sobriété énergétique, `AppLifecycleListener`) ; c'est donc Node-RED, toujours connecté, qui relaie sonneries et changements d'état en push.
- **Node-RED** = jumeau numérique « DIY » : il mémorise le dernier état, historise, et expose une API pour que l'app ne touche jamais InfluxDB directement.
- **L'ESP32 est la seule source de vérité de l'état du portail** (état _reported_). L'app n'affiche jamais « ouvert » sur la seule base de sa commande.

## 4. Contrat MQTT

`{siteId}` = identifiant opaque du site (ex. `site_7f3a`), jamais d'adresse ni de nom.

| Topic                           | Sens         | QoS | Retain  | Payload JSON                                                               |
| ------------------------------- | ------------ | --- | ------- | -------------------------------------------------------------------------- |
| `sesame/{siteId}/gate/state`    | ESP32 ->     | 1   | oui     | `{"state":"closed","ts":1760731200,"seq":42}`                              |
| `sesame/{siteId}/gate/cmd`      | app -> ESP32 | 1   | **non** | `{"cmdId":"uuid","action":"open","issuedAt":…,"expiresAt":…}`              |
| `sesame/{siteId}/gate/ack`      | ESP32 ->     | 1   | non     | `{"cmdId":"uuid","result":"accepted\|rejected_expired\|rejected_no_time\|duplicate","ts":…}` |
| `sesame/{siteId}/doorbell/ring` | ESP32 ->     | 1   | non     | `{"ringId":"uuid","ts":…}`                                                 |
| `sesame/{siteId}/device/status` | ESP32 ->     | 1   | oui     | `"online"` / `"offline"` (LWT)                                             |

Règles non négociables :

- **Commandes explicites et idempotentes** : `open` / `close`, jamais `toggle`. Avec QoS 1 un message peut arriver deux fois ; un `toggle` dupliqué refermerait le portail.
- **Déduplication** côté ESP32 par `cmdId` (buffer des N derniers).
- **Durée de vie (TTL) des commandes** : `expiresAt = issuedAt + 60 s`. L'ESP32 rejette une commande expirée (horloge via NTP). Un ordre d'ouverture envoyé hors ligne ne doit **jamais** être rejoué deux heures plus tard, quand le livreur est parti.
- **Horloge et TTL** : `issuedAt` / `expiresAt` viennent de l'horloge du téléphone, vérifiés par l'ESP32 (NTP).
  - **Refus par défaut** : tant que NTP n'est pas synchronisé, l'ESP32 rejette toute commande avec `rejected_no_time`. On n'ouvre jamais sans être sûr de l'heure.
  - Tolérance d'écart d'horloge **±5 s** ; rejet aussi si `issuedAt` est dans le futur au-delà de cette tolérance.
  - Limite documentée : confiance dans l'horloge du téléphone. Piste : MQTT 5 `Message Expiry Interval` (non utilisé, PubSubClient est en MQTT 3.1.1).
- **Renvoi ≠ nouvelle tentative** (idempotence par clé) :
  - Les renvois automatiques (outbox, reconnexion) gardent **le même** `cmdId`, `issuedAt` et `expiresAt` : le TTL ne repart jamais à zéro.
  - Le bouton « Réessayer » crée une **nouvelle** commande : nouveau `cmdId`, nouveau TTL, **nouvelle biométrie**.
  - Côté app, `duplicate` = succès (la commande a été exécutée une fois).
  - Délai d'attente de l'ack : **10 s**, puis « Pas de réponse du portail » + bouton Réessayer. L'affichage final reste piloté par `gate/state`.
- `ts` en epoch secondes UTC, `seq` monotone côté ESP32 (ordonnancement indépendant des horloges, cf. Lamport).

## 5. Offline-first, réseau et énergie

- **Hive = source de vérité locale** (pattern du cours : réseau -> repository -> Hive -> Notifier -> UI). L'UI ne lit jamais le réseau directement.
  - box `gate_state` : dernier état connu + `receivedAt`
  - box `events` : cache de l'historique
  - box `outbox` : commandes en attente
- **Outbox avec TTL** : une commande hors ligne est persistée avec le statut « En attente » ; `flushQueue()` est déclenché sur `onConnected` ; les commandes expirées sont **abandonnées** et affichées « Expirée, non envoyée ». Jamais d'envoi silencieux d'une ouverture périmée.
- **Optimistic UI limitée** : après une commande, afficher « Ouverture demandée… » jusqu'à l'`ack` puis au `state` publié ; timeout -> message d'erreur + bouton réessayer.
- **Fraîcheur de la donnée** (Age of Data) : Live < 30 s, Stale, Expired ; toujours afficher « Mis à jour il y a … ».
- **ConnectionQuality** `online` / `degraded` / `offline` = `connectivity_plus` + état de la session MQTT, affichée par un `ConnectivityBanner` non bloquant.
- **Cycle de vie** : `AppLifecycleListener` -> déconnexion MQTT en `paused`, reconnexion + resynchronisation (API historique) en `resumed`.
- MQTT : `keepAlivePeriod = 60`, `autoReconnect = true`, backoff exponentiel plafonné sur les reconnexions manuelles.
- `stream_transform` `.throttle(1s, trailing: true)` sur les flux qui alimentent l'UI.

## 6. Stack Flutter

Utiliser les dernières versions stables compatibles (vérifier sur pub.dev, ne pas inventer de versions).

- État / navigation : `flutter_riverpod` (**Notifier / AsyncNotifier uniquement**, pas de `StateProvider` ni `StateNotifier` legacy), `go_router`
  - Providers **écrits à la main**, sans `riverpod_generator` : plus explicite pour la soutenance, une dépendance et un générateur de moins.
- IoT / réseau : `mqtt_client`, `http`, `connectivity_plus`, `stream_transform`, `uuid`
- Stockage : **`hive_ce` + `hive_ce_flutter` + `hive_ce_generator`** / `build_runner`, `flutter_secure_storage`
  - Décision : fork maintenu `hive_ce` dès le départ, car `hive` n'est plus publié depuis 2022 et entre en conflit avec l'`analyzer` récent. Même API (`HiveAesCipher`, adapters). À mentionner dans le dossier.
- Firebase : `firebase_core`, `firebase_auth`, `firebase_messaging`, `flutter_local_notifications`
- Sécurité : `local_auth` (confirmation biométrique avant ouverture)
- UI : `fl_chart` (historique)
- Phase 2 : `flutter_webrtc`
- Tests : `flutter_test`, `mocktail`

## 7. Structure du dépôt

```
sesame/
├── app/                      # Flutter
│   └── lib/
│       ├── main.dart         # init Firebase, Hive (adapters + boxes chiffrées), ProviderScope
│       ├── app/              # router, thème
│       ├── core/
│       │   ├── config/       # lecture --dart-define
│       │   ├── mqtt/         # MqttService (connexion, callbacks, StreamController broadcast)
│       │   ├── connectivity/ # ConnectionNotifier, ConnectivityBanner
│       │   ├── storage/      # init Hive, clé de chiffrement
│       │   └── lifecycle/    # AppLifecycleService
│       └── features/
│           ├── auth/
│           ├── gate/         # état + commandes + outbox
│           ├── doorbell/
│           ├── history/
│           └── camera/       # phase 2
│               ├── data/         # models, repositories (Model du MVVM)
│               ├── viewmodels/   # Notifiers Riverpod (ViewModel)
│               └── views/        # widgets "bêtes" (View)
├── firmware/                 # PlatformIO + Wokwi
│   ├── platformio.ini
│   ├── wokwi.toml
│   ├── diagram.json
│   ├── include/secrets.example.h
│   └── src/main.cpp
├── backend/
│   ├── docker-compose.yml    # node-red, influxdb, mediamtx (phase 2)
│   └── node-red/flows.json   # exporté depuis Node-RED, versionné
└── docs/
    ├── dossier-technique.md
    ├── demo-checklist.md     # à dérouler 20 min avant la soutenance
    ├── adr/                  # 0001-mqtt-vs-ble.md, 0002-outbox-ttl.md, …
    └── schemas/
```

Chaque feature respecte : la View ne connaît que son ViewModel ; le ViewModel ne connaît que des repositories ; seuls les repositories touchent MQTT / HTTP / Hive.

## 8. Firmware (Wokwi)

- ESP32 DevKit, framework Arduino, `PubSubClient`, `ArduinoJson`, `WiFiClientSecure` (`setInsecure()` assumé et documenté comme limite de la simulation : pas de vérification du certificat sur l'ESP32).
- Composants `diagram.json` (broches « safe » uniquement : 13, 14, 16–19, 21–23, 25–27, 32, 33) :
  - bouton poussoir = sonnette (anti-rebond logiciel)
  - servomoteur = moteur du portail (ouverture/fermeture progressive -> états `opening` / `closing`)
  - interrupteur à glissière = fin de course / ouverture manuelle forcée
  - LED = voyant de statut
- NTP au démarrage (`configTime`) pour vérifier les TTL. Refus par défaut tant que l'heure n'est pas synchronisée (`rejected_no_time`, §4).
- Outillage : VS Code + PlatformIO + extension Wokwi. **Licence Wokwi (gratuite) à activer le 20/10**, pour qu'elle soit valide le 21. Secours : copie **privée** du projet sur wokwi.com (`diagram.json` + `main.cpp` identiques).
- LWT `offline` configuré à la connexion, `online` publié (retain) une fois connecté.
- Edge computing : publier l'état **uniquement sur changement**, jamais en polling.
- Secrets dans `include/secrets.h` (gitignoré), modèle dans `secrets.example.h`.

## 9. Backend Node-RED

- Flux 1 — ingestion : `mqtt in sesame/+/#` -> function (parse + validation) -> InfluxDB (measurement `gate_events`, tags `siteId`, `type`).
- Flux 2 — push : sonnerie ou changement d'état -> appel FCM HTTP v1 (topic FCM par `siteId`).
- Flux 3 — API : `GET /api/events?from=&to=` -> requête InfluxDB -> JSON -> réponse (headers CORS pour les tests navigateur).
- Rétention du bucket InfluxDB : **30 jours** (RGPD). Aucune image ni vidéo stockée.
- **InfluxDB 2.x en Docker**, dans le même `docker-compose.yml` que Node-RED (bucket et rétention initialisés par variables d'environnement). Pas d'InfluxDB Cloud : les offres InfluxDB 3 prennent mal en charge Flux, que `node-red-contrib-influxdb` utilise.
- Node-RED est **obligatoire** pour le MVP : c'est lui qui envoie les push FCM.

## 10. Sécurité (critère noté)

- **En transit** : MQTT sur TLS 8883 uniquement ; WebRTC chiffré (DTLS-SRTP) en phase 2.
- **Au repos** : boxes Hive chiffrées (`HiveAesCipher`), clé générée au premier lancement et stockée dans `flutter_secure_storage` (Keychain / Keystore).
- **Secrets** : jamais dans le code ni dans Git. Flutter : `--dart-define-from-file=env.json` (gitignoré, `env.example.json` versionné). `google-services.json` / `GoogleService-Info.plist` gitignorés.
- **Accès** : Firebase Auth obligatoire ; biométrie (`local_auth`) avant toute commande d'ouverture ; identifiants MQTT distincts pour l'ESP32, l'app et Node-RED (ACL par topic si l'offre HiveMQ le permet, sinon documenter la limite).
- **Limite connue (à documenter dans le dossier)** : les identifiants MQTT de l'app sont compilés dans l'APK. Quelqu'un qui les extrait peut publier sur `gate/cmd` sans Firebase Auth ni biométrie. Mesures : Firebase Auth (email et mot de passe) + identifiant MQTT de l'app restreint (publication sur `gate/cmd` uniquement) si HiveMQ le permet. **Architecture cible, non implémentée** : commandes envoyées à Node-RED, qui vérifie le jeton Firebase avant de publier ; l'app n'a plus le droit de publier sur MQTT.
- **Anti-rejeu** : `cmdId` + `expiresAt` (§4).
- **RGPD** : minimisation (siteId opaque, pas d'identifiant utilisateur en clair dans les payloads), rétention 30 jours, pas d'enregistrement vidéo.

## 11. Accessibilité

- `Semantics` sur les éléments clés (état du portail lu à voix haute, boutons d'action explicites).
- L'état ne repose jamais sur la couleur seule (icône + texte).
- Cibles tactiles ≥ 48 dp, support du texte agrandi.

## 12. Qualité, tests, Git

- `flutter analyze` sans warning ; `dart format`.
- Tests unitaires prioritaires : `OutboxService` (TTL, abandon des commandes expirées, ordre FIFO), calcul Live/Stale/Expired, `ConnectionNotifier`, parsing des payloads.
- Tests widget : `ConnectivityBanner`, carte d'état du portail, bouton d'ouverture (états désactivé / en attente).
- Git : Conventional Commits (`feat(gate): …`, `fix(mqtt): …`), une branche par feature, commits petits et fréquents (la régularité est notée). Commits signés par l'auteur, au rythme des checkpoints (§1, « Workflow Git avec Claude Code »).
- Dossier : section « Méthode de travail » (Claude Code utilisé comme binôme, l'auteur conçoit, décide et relit chaque étape).

## 13. Environnement de dev

Matériel : PC Windows à la maison (WSL2 Debian + Docker), MacBook Air (16 Go) en cours, iPhone.

### Jusqu'à la soutenance : tout sur le Mac

Décision du 18/10 : **développement et démo uniquement sur le MacBook Air**, pour supprimer la synchronisation entre deux machines.

- Cible de démo : **émulateur Android sur le Mac** (Android Studio), qui permet le push FCM avec l'app fermée. Itérations rapides possibles sur le simulateur iOS ; l'iPhone n'est pas une cible de démo.
- Backend local : `docker compose up` sur le Mac ; l'émulateur joint Node-RED via `10.0.2.2`.
- Les règles « deux machines » ci-dessous sont **suspendues** jusqu'au 21/10 (FVM et `.gitattributes` restent quand même en place).

### Deux machines, un seul dépôt (après la soutenance)

- **Git est le seul moyen de synchroniser** : commit + push avant de changer de machine, pull en arrivant. Aucun fichier échangé autrement (sauf secrets, voir plus bas).
- **Même version de Flutter partout** : FVM, avec `.fvmrc` versionné. Toutes les commandes passent par `fvm flutter …`.
- **Fins de ligne** : `.gitattributes` avec `* text=auto eol=lf` (plus `*.bat text eol=crlf`), créé dès le premier commit.
- **Versionnés** : `pubspec.lock`, `ios/Podfile.lock`, les fichiers générés `*.g.dart` (évite un `build_runner` obligatoire après chaque pull).
- **Windows** : SDK Flutter installé **côté Windows natif**, pas dans WSL, avec le dépôt sous `C:\workspace\perso\sesame` (pas dans `\\wsl.localhost`). L'émulateur Android tourne sous Windows. Docker y accède via `/mnt/c/...` depuis WSL, ou via Docker Desktop.
- **Mac** : SDK Flutter + Xcode + CocoaPods. Seule machine capable de compiler iOS. Les modifications de `ios/` (Info.plist, Podfile) se font et se testent sur le Mac.
- **Secrets non versionnés** à recopier à la main sur chaque machine (gestionnaire de mots de passe) : `app/env.json`, `google-services.json`, `GoogleService-Info.plist`, `firmware/include/secrets.h`, `backend/.env`. Un `*.example` versionné pour chacun.
- **Node-RED portable** : `backend/node-red/` monté en volume sur `/data`, pour que `flows.json` soit directement dans le dépôt. `credentialSecret` lu depuis `backend/.env` (même valeur sur les deux machines), sinon les identifiants chiffrés dans `flows_cred.json` sont illisibles sur l'autre machine.
- **Une seule instance Node-RED active à la fois** : HiveMQ, InfluxDB et Firebase sont dans le cloud et partagés. Deux Node-RED allumés = événements écrits deux fois dans InfluxDB et notifications push en double. Arrêter le conteneur avant de quitter une machine.

### Cibles et contraintes iOS

- Cibles : émulateur Android (Windows ou Mac), simulateur iOS et iPhone physique (Mac uniquement).
- **iPhone avec compte Apple gratuit** : installation possible, mais le profil expire au bout de **7 jours**. Réinstaller l'app la veille de la soutenance.
- **Push iOS** : APNs exige l'Apple Developer Program payant. Sans abonnement, le code FCM reste multiplateforme, mais la démo des notifications push se fait sur **Android**. Côté iPhone, afficher une notification locale quand l'app est au premier plan et reçoit l'événement MQTT.
- **Info.plist** : `NSFaceIDUsageDescription` (biométrie), `NSLocalNetworkUsageDescription` + `NSAllowsLocalNetworking` si l'app appelle Node-RED en HTTP sur le réseau local, `NSMicrophoneUsageDescription` seulement pour le bonus audio.
- **URL du backend** : jamais `localhost` en dur, toujours via `--dart-define` (IP LAN de la machine Docker pour l'iPhone, `10.0.2.2` pour l'émulateur Android).
- **Backend** : `docker compose up` dans `backend/`. Si Docker tourne dans WSL2 sans Docker Desktop, l'iPhone ne verra pas les ports : activer `networkingMode=mirrored` dans `.wslconfig`, ouvrir le port dans le pare-feu Windows, ou exposer l'API via un tunnel HTTPS (cloudflared).
- **Wi-Fi de l'école** : il isole souvent les appareils entre eux, donc l'iPhone ne joindra pas Node-RED sur le Mac par son IP. Utiliser le partage de connexion de l'iPhone ou le tunnel cloudflared.
- **Firmware** : VS Code + PlatformIO IDE + Wokwi Simulator, sur l'une ou l'autre machine. HiveMQ est dans le cloud, aucun souci réseau.
- **Webcam (phase 2)** : Docker n'accède pas à la webcam. `ffmpeg` tourne en natif sur l'hôte et pousse le flux vers MediaMTX en Docker.

## 14. Feuille de route (chaque étape = une démo vérifiable)

1. **Socle** : monorepo, `.gitignore`, `.gitattributes`, `.fvmrc`, fichiers `*.example` des secrets, app Flutter vide avec Riverpod + go_router, structure §7. Vérifier que l'app compile sur les deux machines avant d'aller plus loin.
2. **Firmware** : Wokwi publie `device/status` et `gate/state`, visibles dans MQTT Explorer.
3. **Lecture temps réel** : l'app affiche l'état du portail et le statut de l'équipement via MQTT.
4. **Commandes** : open/close avec `cmdId`, TTL, ack, déduplication ; servo qui bouge dans Wokwi.
5. **Offline-first** : Hive chiffré, hydratation au démarrage, Outbox avec TTL, bannière, Age of Data.
6. **Backend** : Node-RED -> InfluxDB -> API ; écran historique avec `fl_chart`.
7. **Notifications** : Firebase Auth + FCM via Node-RED, app fermée.
8. **Cycle de vie et sobriété** : `AppLifecycleListener`, throttle.
9. **Tests + accessibilité + dossier technique**.
10. ~~**Phase 2** : caméra via MediaMTX + `flutter_webrtc`.~~ Hors périmètre pour la soutenance.

### Jalons (soutenance le 21/10 au matin)

| Jalon               | Échéance          | Étapes                                                    | Si le jalon est manqué                                      |
| ------------------- | ----------------- | --------------------------------------------------------- | ----------------------------------------------------------- |
| J1                  | 18/10 à 20 h      | 1 à 3                                                     | Réduire au strict minimum                                   |
| J2                  | 19/10 à 20 h      | 4 et 5                                                    | Couper Node-RED / InfluxDB / FCM : historique local + notification locale |
| J3                  | 20/10 à 14 h      | 6 et 7                                                    | Historique local + notification locale                      |
| **Gel des fonctionnalités** | **20/10 à 14 h** | 9 uniquement : tests, accessibilité, dossier, relecture du code | —                                                     |

Le 21 au matin : on ne code plus. Checklist d'avant-démo dans `docs/demo-checklist.md`, à dérouler 20 min avant la soutenance.

### Scénario de démo cible

Sonner dans Wokwi -> push sur le téléphone -> ouvrir l'app -> (phase 2 : voir la caméra) -> « Ouvrir » + biométrie -> le servo tourne -> état `opening` puis `open` -> notification. Puis couper le Wi-Fi du téléphone : bannière hors ligne, dernier état affiché avec son âge, commande mise en attente puis expirée après 60 s.
