# ADR 0003 — Garder PubSubClient malgré la publication en QoS 0

- Statut : accepté
- Date : 19/10/2026

## Contexte

Le contrat MQTT (CLAUDE.md §4) prévoit QoS 1 pour tous les topics publiés par l'ESP32 (`gate/state`, `gate/ack`, `doorbell/ring`, `device/status`).

Le firmware utilise `PubSubClient` (knolleary, 2.8), la bibliothèque vue en cours. Elle a deux limites :

- `publish()` n'envoie qu'en **QoS 0** ;
- elle parle MQTT 3.1.1 uniquement (pas de `Message Expiry Interval` de MQTT 5).

Elle sait en revanche :

- s'**abonner en QoS 1** (utilisé pour `gate/cmd`) ;
- publier le **LWT en QoS 1** avec retain (`device/status = offline`).

## Options

1. **Garder PubSubClient** et documenter la limite.
2. Passer à `esp_mqtt` (client MQTT d'ESP-IDF, utilisable depuis Arduino) : QoS 1 et 2 en publication, mais une API à base d'événements différente, à réécrire et retester dans Wokwi.
3. Passer à une autre bibliothèque Arduino (`arduino-mqtt`, `AsyncMqttClient`) : même coût de migration, maintenance moins sûre.

## Décision

Option 1. À deux jours de la soutenance, changer de client MQTT sur l'ESP32 met en risque la démo pour un gain faible, car les mécanismes suivants couvrent déjà la perte d'un message :

| Message perdu | Ce qui compense |
| --- | --- |
| `gate/state` | Publié en **retain** : tout client qui se (re)connecte reçoit le dernier état. Le prochain changement corrige l'affichage. L'ESP32 republie aussi l'état à chaque reconnexion. |
| `gate/ack` | Délai d'attente de 10 s côté app, puis « Pas de réponse du portail » + Réessayer. L'affichage final est piloté par `gate/state`, pas par l'ack. |
| `doorbell/ring` | Perte possible d'une notification. Limite acceptée pour la simulation. |
| `device/status` | `online` en QoS 0 + retain, `offline` par LWT en QoS 1. |

Dans le sens app -> ESP32, la commande `gate/cmd` est bien reçue en QoS 1. C'est la raison d'être de la déduplication par `cmdId` : QoS 1 peut livrer deux fois la même commande.

## Conséquences

- QoS 0 entre l'ESP32 et le broker est d'autant plus acceptable que le lien TCP/TLS est fiable tant qu'il est ouvert ; une perte n'arrive qu'en cas de coupure, et la reconnexion republie l'état.
- **Évolution** : passer à `esp_mqtt` pour obtenir QoS 1 en publication, et MQTT 5 pour le `Message Expiry Interval` sur les commandes (TTL appliqué aussi par le broker).
