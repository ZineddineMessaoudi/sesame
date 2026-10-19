/// Topics du contrat MQTT (§4), construits en un seul endroit pour éviter les fautes de frappe.
class MqttTopics {
  const MqttTopics(this.siteId);

  /// Identifiant opaque du site : jamais d'adresse ni de nom (RGPD, §10).
  final String siteId;

  String get _base => 'sesame/$siteId';

  String get gateState => '$_base/gate/state';
  String get gateCmd => '$_base/gate/cmd';
  String get gateAck => '$_base/gate/ack';
  String get doorbellRing => '$_base/doorbell/ring';
  String get deviceStatus => '$_base/device/status';
}
