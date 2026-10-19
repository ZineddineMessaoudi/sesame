/// Fraîcheur de la donnée affichée (Age of Data, §5).
enum DataFreshness {
  /// Confirmée il y a moins de 30 s.
  live,

  /// Entre 30 s et 5 min : probablement encore juste, à prendre avec prudence.
  stale,

  /// Plus de 5 min : le portail a pu bouger, l'état affiché peut être faux.
  expired;

  static const liveFor = Duration(seconds: 30);
  static const staleFor = Duration(minutes: 5);

  static DataFreshness ofAge(Duration age) {
    if (age < liveFor) return live;
    if (age < staleFor) return stale;
    return expired;
  }
}
