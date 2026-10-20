# Reprise du 20/10 après-midi (Windows → Mac)

Note de passation pour reprendre sur le Mac, y compris avec Claude Code : sa mémoire est locale à chaque machine, celle du Mac s'est arrêtée au 18-19/10. **Lire ce fichier en début de session**, puis `docs/preparation-mac.md`.

## État

- `main` contient tout le MVP, plus l'authentification et la caméra. 130 tests verts, `flutter analyze` sans remarque.
- Branche en cours : `chore/tests-docs` (étape 9). Elle contient `docs/preparation-mac.md`, ce fichier et `backend/mediamtx/stream-webcam.sh` (version macOS du script webcam, **non testée**).
- Le PC Windows n'est plus utilisé : la démo se fait sur le Mac.

## Ce qui a été fait le 20/10

1. **Authentification Firebase** (e-mail + mot de passe, pas d'inscription dans l'app : comptes créés dans la console). Redirection vers `/connexion` sans session.
2. **MQTT et push liés à la session** : déconnecté, l'app ne reçoit plus rien (`MqttService.allow`, désabonnement du topic FCM).
3. **TTL des push FCM à 60 s** : un téléphone hors ligne n'affiche pas « Quelqu'un sonne » des heures après ; la sonnerie reste dans l'historique.
4. **Keep-alive de l'ESP32 passé de 15 à 30 s** : la simulation Wokwi, plus lente que le temps réel, se faisait couper par le broker toutes les ~30 s.
5. **Tolérance d'avance des commandes passée à 30 s** (expiration toujours à 5 s) : l'horloge de l'ESP32 prend 5 à 11 s de retard sous Wokwi.
6. **Caméra (phase 2, choix de l'auteur malgré le §2)** : webcam + micro → ffmpeg → MediaMTX (Docker) → WebRTC (WHEP) → `flutter_webrtc`. Écran « Qui est là ? » avec Ouvrir/Fermer ; la sonnerie (alerte, notification locale, push) l'ouvre. Son du visiteur vers l'utilisateur seulement.

## Décisions à défendre dans le dossier et à l'oral

- **Écart au contrat §4** : tolérance de ±5 s → 5 s côté expiration, 30 s côté avance. Mesuré : la simulation tourne à ~45 % du temps réel quand le servo bouge. Sans danger pour l'anti-rejeu, l'expiration reste stricte et `expiresAt − issuedAt ≤ 60 s` (validité totale au pire 90 s au lieu de 65 s).
- **Phase 2 réalisée** alors que CLAUDE.md l'écartait : arbitrage de l'auteur, une fois le MVP terminé, sur une branche isolée.
- **WHEP** plutôt qu'un serveur de signalisation : un POST HTTP de l'offre SDP suffit. Réception seule, chiffrement DTLS-SRTP, aucun serveur STUN tiers, aucun enregistrement (RGPD).
- **Médias WebRTC en TCP uniquement** : en UDP, le relais de Docker Desktop perdait le flux au hasard (écran noir, « No decodable frame » côté Android).
- **Caméra coupée en arrière-plan** : l'écran caméra se ferme en `paused`, sauf pendant le PIN d'une ouverture (sobriété, §5).
- **Sortie audio** sur le haut-parleur (ou Bluetooth) : Android joue sinon un flux WebRTC dans l'écouteur.
- **Pas d'inscription dans l'app** : personne ne peut se créer un accès au portail.
- **Même message d'erreur** pour un e-mail inconnu et un mauvais mot de passe : pas d'énumération des comptes.
- Limites connues : le cache local (dernier état, historique) reste sur le téléphone après déconnexion ; MediaMTX accepte la lecture sans authentification (réseau local uniquement) ; l'audio vers le visiteur n'est pas fait.

Décisions plus anciennes (QoS 0 de PubSubClient, sonnerie sans retain, pas de double notification, jeton OAuth neuf à chaque sonnerie, signature RS256 sans module npm, anti-injection Flux, HTTP en clair limité par domaine, graphique des sonneries seulement) : voir les commentaires du code et `docs/adr/0003-pubsubclient-qos0.md`.

## Pièges déjà résolus (ne pas re-diagnostiquer)

- **Écran caméra noir** → relais UDP de Docker (corrigé : TCP seul). Si ça revient : `docker logs sesame-mediamtx` doit montrer `host/tcp`.
- **« Commande expirée » aléatoire** → dérive d'horloge de Wokwi (corrigé, voir plus haut). Garder l'onglet Wokwi visible.
- **« Pas de réponse du portail »** alors que le portail s'ouvre → ESP32 reconnecté en boucle (keep-alive, corrigé). Diagnostic : dans `docker logs sesame-node-red`, un `closed` republié toutes les ~30 s signale des reconnexions.
- **Diagnostic d'horloge** : comparer le `ts` des messages de l'ESP32 à leur heure de réception dans les logs Node-RED.
- **ffmpeg s'arrête** quand MediaMTX redémarre : relancer le script.
- **L'écran du PIN** met l'app en pause (coupe MQTT et la vidéo quelques secondes) ; l'empreinte non → démo à l'empreinte.
- Après l'ajout d'un plugin natif ou d'une variable dans `env.json` : relancer `flutter run`, un hot restart ne suffit pas.

## Reste à faire (étape 9), par priorité

1. **Présentation** pour la soutenance (durée et format à préciser).
2. **`docs/dossier-technique.md`** : architecture, choix justifiés (MQTT vs HTTP/BLE, FCM, Node-RED, offline-first, sécurité, caméra), limites, méthode de travail (Claude Code en binôme).
3. **ADR** `0001-mqtt-vs-ble.md` et `0002-outbox-ttl.md` (seul le 0003 existe).
4. **`docs/demo-checklist.md`** : reprendre la section 8 de `preparation-mac.md`.
5. Passe d'accessibilité (`Semantics`, texte agrandi, cibles de 48 dp) et relecture.
