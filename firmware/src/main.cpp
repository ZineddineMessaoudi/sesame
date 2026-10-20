// Firmware Sésame : portail + sonnette, publiés sur HiveMQ Cloud (contrat MQTT §4).
// L'ESP32 est la seule source de vérité de l'état du portail (état "reported").

#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_sntp.h>
#include <time.h>

#include "secrets.h"

// --- Broches (uniquement des broches "safe", §8) ---
constexpr uint8_t PIN_DOORBELL = 13;  // bouton poussoir : sonnette
constexpr uint8_t PIN_MANUAL = 14;    // interrupteur à glissière : ouverture manuelle forcée
constexpr uint8_t PIN_SERVO = 18;     // moteur du portail
constexpr uint8_t PIN_LED = 25;       // voyant de statut

// --- Mouvement du portail ---
constexpr int ANGLE_CLOSED = 0;
constexpr int ANGLE_OPEN = 90;
// ~4 s de course : assez lent pour que "opening" / "closing" soient visibles dans l'app.
constexpr uint32_t STEP_INTERVAL_MS = 45;

// --- MQTT ---
// Le broker coupe un client muet après 1,5 × keep-alive de temps *réel*, mais l'ESP32
// compte en temps *simulé*, plus lent sous Wokwi. À 15 s, le ping arrivait après les
// 22,5 s réelles : reconnexion toutes les ~30 s, commandes et acks retardés (mesuré).
// 30 s : marge pour une simulation jusqu'à ~1,5× plus lente, LWT visible en ~45 s.
constexpr uint16_t MQTT_KEEPALIVE_S = 30;
constexpr uint32_t MQTT_RETRY_MS = 5000;
constexpr uint32_t NTP_WAIT_MS = 10000;
// Resynchro NTP fréquente (15 s = minimum d'ESP-IDF, 1 h par défaut) : dans Wokwi la simulation
// tourne moins vite que le temps réel, l'horloge prend du retard et ferait rejeter les commandes
// fraîches (issuedAt « dans le futur »). Sur un vrai ESP32, quelques minutes suffiraient.
constexpr uint32_t NTP_SYNC_INTERVAL_MS = 15000;
// Attente d'une resynchronisation déclenchée à la volée, quand une commande semble
// venir du futur : assez pour un aller-retour NTP, très en deçà des 10 s d'ack.
constexpr uint32_t NTP_RESYNC_WAIT_MS = 1200;

// --- Commandes (§4) ---
constexpr int64_t CMD_TTL_S = 60;           // durée de vie maximale d'une commande
constexpr int64_t CLOCK_TOLERANCE_S = 5;    // écart d'horloge toléré téléphone / ESP32
constexpr size_t DEDUP_SIZE = 16;           // nombre de cmdId acceptés mémorisés

// --- Sonnette ---
constexpr uint32_t DEBOUNCE_MS = 50;
// Anti-spam : un visiteur qui insiste ne doit pas déclencher une rafale de notifications push.
constexpr uint32_t RING_COOLDOWN_MS = 3000;

const String TOPIC_BASE = String("sesame/") + SITE_ID;
const String TOPIC_STATE = TOPIC_BASE + "/gate/state";
const String TOPIC_STATUS = TOPIC_BASE + "/device/status";
const String TOPIC_RING = TOPIC_BASE + "/doorbell/ring";
const String TOPIC_CMD = TOPIC_BASE + "/gate/cmd";
const String TOPIC_ACK = TOPIC_BASE + "/gate/ack";
const String CLIENT_ID = String("sesame-esp32-") + SITE_ID;  // unique : le broker éjecte les doublons

WiFiClientSecure tls;
PubSubClient mqtt(tls);
Servo servo;

enum class GateState { Closed, Opening, Open, Closing };

GateState gateState = GateState::Closed;
int currentAngle = ANGLE_CLOSED;
int targetAngle = ANGLE_CLOSED;
uint32_t lastStepAt = 0;
uint32_t lastMqttAttemptAt = 0;
uint32_t seq = 0;  // monotone pendant une session (repart à 0 au redémarrage, cf. app étape 3)
bool statePending = true;  // état à (re)publier : au démarrage et après chaque reconnexion
int lastManualLevel = HIGH;
int bellRawLevel = HIGH;      // dernière lecture brute (rebonds compris)
int bellStableLevel = HIGH;   // niveau validé après DEBOUNCE_MS sans changement
uint32_t bellChangedAt = 0;
uint32_t lastRingAt = 0;
// Tampon circulaire des derniers cmdId exécutés : QoS 1 peut livrer deux fois la même commande.
char acceptedCmdIds[DEDUP_SIZE][37] = {};
size_t nextDedupSlot = 0;

const char* toString(GateState s) {
  switch (s) {
    case GateState::Closed: return "closed";
    case GateState::Opening: return "opening";
    case GateState::Open: return "open";
    case GateState::Closing: return "closing";
  }
  return "closed";
}

bool timeIsSynced() {
  // Avant NTP, l'horloge démarre en 1970 : tout ce qui précède 2024 est "pas d'heure".
  return time(nullptr) > 1704067200;
}

void connectWifi() {
  Serial.printf("Wi-Fi : connexion à %s", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    Serial.print('.');
  }
  Serial.printf("\r\nWi-Fi : connecté, IP %s\r\n", WiFi.localIP().toString().c_str());
}

void startNtp() {
  // UTC : les ts du contrat sont en epoch secondes UTC, sans fuseau.
  sntp_set_sync_interval(NTP_SYNC_INTERVAL_MS);
  configTime(0, 0, "pool.ntp.org", "time.google.com");  // relancé : resynchro immédiate
}

// Resynchronisation courte, déclenchée quand on soupçonne notre horloge d'être
// en retard. Bloquante, mais brève : l'app attend l'ack 10 s (§4).
void resyncClock() {
  startNtp();
  const uint32_t start = millis();
  while (millis() - start < NTP_RESYNC_WAIT_MS) delay(50);
}

void syncClock() {
  startNtp();
  const uint32_t start = millis();
  while (!timeIsSynced() && millis() - start < NTP_WAIT_MS) delay(200);
  // Sans NTP on continue quand même : l'état reste publié, mais les commandes seront
  // refusées (rejected_no_time, §4). La synchro se poursuit en tâche de fond.
  Serial.println(timeIsSynced() ? "NTP : heure synchronisée" : "NTP : pas encore d'heure");
}

void publishState() {
  JsonDocument doc;
  doc["state"] = toString(gateState);
  doc["ts"] = timeIsSynced() ? static_cast<uint32_t>(time(nullptr)) : 0;
  doc["seq"] = ++seq;
  char payload[96];
  serializeJson(doc, payload);
  // retain : un client qui se connecte reçoit immédiatement le dernier état connu.
  if (mqtt.publish(TOPIC_STATE.c_str(), payload, true)) {
    statePending = false;
    Serial.printf("MQTT -> %s %s\r\n", TOPIC_STATE.c_str(), payload);
  }
}

// UUID v4 (RFC 4122) tiré du générateur matériel de l'ESP32 : identifiant unique de la sonnerie,
// qui permet à Node-RED et à l'app de dédupliquer un message reçu deux fois.
void makeUuid(char out[37]) {
  uint8_t b[16];
  for (int i = 0; i < 16; i += 4) {
    const uint32_t r = esp_random();
    memcpy(b + i, &r, 4);
  }
  b[6] = (b[6] & 0x0F) | 0x40;  // version 4
  b[8] = (b[8] & 0x3F) | 0x80;  // variante RFC 4122
  snprintf(out, 37, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
           b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12],
           b[13], b[14], b[15]);
}

void publishRing() {
  // Pas de mise en file hors ligne : une sonnerie relayée plusieurs minutes plus tard
  // ferait croire qu'un visiteur attend encore. Elle est perdue, et c'est voulu.
  if (!mqtt.connected()) {
    Serial.println("Sonnette : MQTT déconnecté, sonnerie ignorée");
    return;
  }
  char ringId[37];
  makeUuid(ringId);
  JsonDocument doc;
  doc["ringId"] = ringId;
  doc["ts"] = timeIsSynced() ? static_cast<uint32_t>(time(nullptr)) : 0;
  char payload[96];
  serializeJson(doc, payload);
  // Pas de retain : un événement ponctuel ne doit pas être rejoué à chaque nouvel abonné.
  if (mqtt.publish(TOPIC_RING.c_str(), payload, false)) {
    Serial.printf("MQTT -> %s %s\r\n", TOPIC_RING.c_str(), payload);
  }
}

void handleDoorbell() {
  // Anti-rebond logiciel non bloquant : on n'accepte un niveau que s'il est stable.
  const int level = digitalRead(PIN_DOORBELL);
  if (level != bellRawLevel) {
    bellRawLevel = level;
    bellChangedAt = millis();
    return;
  }
  if (millis() - bellChangedAt < DEBOUNCE_MS || level == bellStableLevel) return;
  bellStableLevel = level;
  if (level != LOW) return;  // on sonne à l'appui (front descendant), pas au relâchement
  if (lastRingAt != 0 && millis() - lastRingAt < RING_COOLDOWN_MS) {
    Serial.println("Sonnette : appui ignoré (anti-spam)");
    return;
  }
  lastRingAt = millis();
  publishRing();
}

void setGateState(GateState next) {
  if (next == gateState) return;  // edge computing : publication sur changement uniquement
  gateState = next;
  statePending = true;
}

void publishAck(const char* cmdId, const char* result) {
  JsonDocument doc;
  doc["cmdId"] = cmdId;
  doc["result"] = result;
  doc["ts"] = timeIsSynced() ? static_cast<uint32_t>(time(nullptr)) : 0;
  char payload[128];
  serializeJson(doc, payload);
  // QoS 0 : PubSubClient ne publie pas en QoS 1 (limite documentée dans l'ADR 0003).
  // Si l'ack se perd, l'app affiche « Pas de réponse » ; l'état publié reste la vérité.
  mqtt.publish(TOPIC_ACK.c_str(), payload, false);
  Serial.printf("MQTT -> %s %s\r\n", TOPIC_ACK.c_str(), payload);
}

bool isDuplicate(const char* cmdId) {
  for (const auto& id : acceptedCmdIds) {
    if (strcmp(id, cmdId) == 0) return true;
  }
  return false;
}

void rememberCmdId(const char* cmdId) {
  strlcpy(acceptedCmdIds[nextDedupSlot], cmdId, sizeof(acceptedCmdIds[0]));
  nextDedupSlot = (nextDedupSlot + 1) % DEDUP_SIZE;
}

// Applique les règles du contrat dans l'ordre : doublon, heure, durée de vie.
// Seules les commandes acceptées sont mémorisées : le doublon d'une commande refusée
// est réévalué (et refusé à nouveau), jamais exécuté par erreur.
const char* evaluateCommand(const char* cmdId, int64_t issuedAt, int64_t expiresAt) {
  if (isDuplicate(cmdId)) return "duplicate";
  // Refus par défaut : on n'ouvre jamais sans être sûr de l'heure.
  if (!timeIsSynced()) return "rejected_no_time";

  // Un TTL incohérent ou plus long que 60 s est refusé : il permettrait de rejouer
  // l'ordre plus tard. Évalué avant toute resynchro, car il ne dépend pas de notre heure.
  if (expiresAt <= issuedAt || expiresAt - issuedAt > CMD_TTL_S) return "rejected_expired";

  int64_t now = time(nullptr);
  // Une commande « venue du futur » accuse notre horloge, pas l'émetteur : dans
  // Wokwi, une simulation mise en pause (onglet masqué) fige l'ESP32 pendant que
  // le temps réel continue, et toute commande fraîche paraît alors anticipée. On
  // resynchronise et on réévalue **une seule fois** : si c'est encore du futur
  // après ça, on refuse pour de bon.
  if (issuedAt > now + CLOCK_TOLERANCE_S) {
    Serial.println("Commande datée du futur : resynchronisation avant de trancher");
    resyncClock();
    now = time(nullptr);
  }

  const bool expired = now > expiresAt + CLOCK_TOLERANCE_S;
  const bool fromFuture = issuedAt > now + CLOCK_TOLERANCE_S;
  if (expired || fromFuture) return "rejected_expired";
  return "accepted";
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (TOPIC_CMD != topic) return;
  JsonDocument doc;
  // Entrée const : ArduinoJson copie les chaînes, car le tampon de PubSubClient
  // est réutilisé par publishAck() juste après.
  if (deserializeJson(doc, static_cast<const byte*>(payload), length)) {
    Serial.println("Commande : JSON invalide, ignorée");
    return;
  }
  const char* cmdId = doc["cmdId"];
  const char* action = doc["action"];
  const bool valid = cmdId && strlen(cmdId) > 0 && strlen(cmdId) <= 36 && action &&
                     doc["issuedAt"].is<int64_t>() && doc["expiresAt"].is<int64_t>();
  // Commandes explicites uniquement : jamais de "toggle", qu'un doublon inverserait.
  const bool open = valid && strcmp(action, "open") == 0;
  const bool close = valid && strcmp(action, "close") == 0;
  if (!open && !close) {
    Serial.println("Commande : format inconnu, ignorée");
    return;
  }
  const char* result = evaluateCommand(cmdId, doc["issuedAt"], doc["expiresAt"]);
  Serial.printf("Commande %s (%s) : %s\r\n", action, cmdId, result);
  if (strcmp(result, "accepted") == 0) {
    rememberCmdId(cmdId);
    targetAngle = open ? ANGLE_OPEN : ANGLE_CLOSED;  // driveGate() publiera opening/open
  }
  publishAck(cmdId, result);
}

void connectMqtt() {
  Serial.printf("MQTT : connexion à %s:%d\r\n", MQTT_HOST, MQTT_PORT);
  // LWT : si la connexion tombe sans déconnexion propre, le broker publie "offline" (retain).
  const bool ok = mqtt.connect(CLIENT_ID.c_str(), MQTT_USERNAME, MQTT_PASSWORD,
                               TOPIC_STATUS.c_str(), 1, true, "offline");
  if (!ok) {
    Serial.printf("MQTT : échec (rc=%d), nouvel essai dans %lus\r\n", mqtt.state(),
                  MQTT_RETRY_MS / 1000);
    return;
  }
  Serial.println("MQTT : connecté");
  // La poignée de main TLS est très lente à simuler : l'horloge a pris ~10 s de retard
  // pendant la connexion (mesuré). On resynchronise sans attendre les 15 s.
  startNtp();
  mqtt.publish(TOPIC_STATUS.c_str(), "online", true);
  // Session propre (PubSubClient) : l'abonnement est refait à chaque connexion.
  if (mqtt.subscribe(TOPIC_CMD.c_str(), 1)) {
    Serial.printf("MQTT : abonné à %s\r\n", TOPIC_CMD.c_str());
  }
  statePending = true;  // republie l'état : il a pu changer pendant la coupure
}

void handleManualSwitch() {
  const int level = digitalRead(PIN_MANUAL);
  if (level == lastManualLevel) return;
  lastManualLevel = level;
  // Chaque bascule est une commande locale explicite : LOW = ouvrir, HIGH = fermer.
  targetAngle = (level == LOW) ? ANGLE_OPEN : ANGLE_CLOSED;
}

void driveGate() {
  if (currentAngle == targetAngle) {
    setGateState(currentAngle == ANGLE_OPEN ? GateState::Open : GateState::Closed);
    return;
  }
  setGateState(targetAngle > currentAngle ? GateState::Opening : GateState::Closing);
  if (millis() - lastStepAt < STEP_INTERVAL_MS) return;  // non bloquant : loop() reste réactive
  lastStepAt = millis();
  currentAngle += (targetAngle > currentAngle) ? 1 : -1;
  servo.write(currentAngle);
}

void updateLed() {
  // Fixe = connecté au broker, clignotant = en cours de connexion.
  digitalWrite(PIN_LED, mqtt.connected() ? HIGH : (millis() / 250) % 2);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_DOORBELL, INPUT_PULLUP);
  pinMode(PIN_MANUAL, INPUT_PULLUP);
  pinMode(PIN_LED, OUTPUT);
  servo.attach(PIN_SERVO);
  servo.write(currentAngle);
  lastManualLevel = digitalRead(PIN_MANUAL);
  targetAngle = (lastManualLevel == LOW) ? ANGLE_OPEN : ANGLE_CLOSED;

  connectWifi();
  syncClock();

  // Limite assumée de la simulation (§8) : chiffrement TLS sans vérification du certificat.
  tls.setInsecure();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setKeepAlive(MQTT_KEEPALIVE_S);
  mqtt.setBufferSize(512);
  mqtt.setCallback(onMqttMessage);
}

void loop() {
  if (!mqtt.connected() && (lastMqttAttemptAt == 0 || millis() - lastMqttAttemptAt > MQTT_RETRY_MS)) {
    lastMqttAttemptAt = millis();
    connectMqtt();
  }
  mqtt.loop();

  handleDoorbell();
  handleManualSwitch();
  driveGate();
  if (statePending && mqtt.connected()) publishState();
  updateLed();
}
