// Modèle des secrets du firmware. Copier en secrets.h (gitignoré) et remplir.
#pragma once

// Wi-Fi simulé par Wokwi : réseau ouvert "Wokwi-GUEST".
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASSWORD ""

// HiveMQ Cloud (TLS 8883). Identifiant dédié à l'ESP32, distinct de l'app et de Node-RED.
#define MQTT_HOST "xxxxxxxx.s1.eu.hivemq.cloud"
#define MQTT_PORT 8883
#define MQTT_USERNAME "esp32"
#define MQTT_PASSWORD "change-me"

// Identifiant opaque du site (jamais d'adresse ni de nom, RGPD).
#define SITE_ID "site_7f3a"
