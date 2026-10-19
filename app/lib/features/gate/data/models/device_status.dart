/// Statut de l'ESP32, publié en retain sur `device/status` ; `offline` vient du LWT.
enum DeviceStatus {
  online,
  offline;

  /// Le firmware publie `online` en texte brut ; on accepte aussi la forme JSON
  /// `"online"` du contrat (§4), pour ne pas dépendre de ce détail.
  static DeviceStatus? tryParse(String payload) {
    var value = payload.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    return DeviceStatus.values.asNameMap()[value];
  }
}
