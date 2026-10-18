import 'package:flutter/material.dart';

/// Thème Material 3 généré depuis une couleur de base : contrastes conformes
/// en clair comme en sombre, sans palette maintenue à la main.
abstract final class AppTheme {
  static const _seed = Color(0xFF2E5E4E);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
    // Cibles tactiles ≥ 48 dp (§11), quelle que soit la plateforme.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
