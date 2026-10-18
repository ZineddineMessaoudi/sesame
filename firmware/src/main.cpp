// Firmware Sésame : portail + sonnette, publiés sur HiveMQ Cloud (contrat MQTT §4).
// L'ESP32 est la seule source de vérité de l'état du portail (état "reported").

#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>

#include "secrets.h"

// --- Broches (uniquement des broches "safe", §8) ---
constexpr uint8_t PIN_DOORBELL = 13;  // bouton poussoir (câblé, utilisé au prochain checkpoint)
constexpr uint8_t PIN_MANUAL = 14;    // interrupteur à glissière : ouverture manuelle forcée
constexpr uint8_t PIN_SERVO = 18;     // moteur du portail
constexpr uint8_t PIN_LED = 25;       // voyant de statut

// --- Mouvement du portail ---
constexpr int ANGLE_CLOSED = 0;
constexpr int ANGLE_OPEN = 90;
// ~4 s de course : assez lent pour que "opening" / "closing" soient visibles dans l'app.
constexpr uint32_t STEP_INTERVAL_MS = 45;

// --- MQTT ---
// Keep-alive court : le broker publie le LWT "offline" ~1,5 × keep-alive après une coupure,
// soit ~22 s ; avec 60 s il faudrait 90 s pour voir l'équipement hors ligne en démo.
constexpr uint16_t MQTT_KEEPALIVE_S = 15;
constexpr uint32_t MQTT_RETRY_MS = 5000;
constexpr uint32_t NTP_WAIT_MS = 10000;

const String TOPIC_BASE = String("sesame/") + SITE_ID;
const String TOPIC_STATE = TOPIC_BASE + "/gate/state";
const String TOPIC_STATUS = TOPIC_BASE + "/device/status";
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

void syncClock() {
  // UTC : les ts du contrat sont en epoch secondes UTC, sans fuseau.
  configTime(0, 0, "pool.ntp.org", "time.google.com");
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

void setGateState(GateState next) {
  if (next == gateState) return;  // edge computing : publication sur changement uniquement
  gateState = next;
  statePending = true;
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
  mqtt.publish(TOPIC_STATUS.c_str(), "online", true);
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
}

void loop() {
  if (!mqtt.connected() && (lastMqttAttemptAt == 0 || millis() - lastMqttAttemptAt > MQTT_RETRY_MS)) {
    lastMqttAttemptAt = millis();
    connectMqtt();
  }
  mqtt.loop();

  handleManualSwitch();
  driveGate();
  if (statePending && mqtt.connected()) publishState();
  updateLed();
}
