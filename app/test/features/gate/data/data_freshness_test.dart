import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/gate/data/models/data_freshness.dart';
import 'package:sesame/features/gate/views/widgets/freshness_label.dart';

void main() {
  test('seuils Live < 30 s, Stale < 5 min, Expired au-delà', () {
    expect(
      DataFreshness.ofAge(const Duration(seconds: 29)),
      DataFreshness.live,
    );
    expect(
      DataFreshness.ofAge(const Duration(seconds: 30)),
      DataFreshness.stale,
    );
    expect(
      DataFreshness.ofAge(const Duration(minutes: 4, seconds: 59)),
      DataFreshness.stale,
    );
    expect(
      DataFreshness.ofAge(const Duration(minutes: 5)),
      DataFreshness.expired,
    );
  });

  test('formatAge arrondit vers le bas à l\'unité la plus parlante', () {
    expect(formatAge(const Duration(seconds: 12)), '12 s');
    expect(formatAge(const Duration(minutes: 3, seconds: 59)), '3 min');
    expect(formatAge(const Duration(hours: 2, minutes: 30)), '2 h');
    expect(formatAge(const Duration(days: 4, hours: 3)), '4 j');
    expect(formatAge(const Duration(seconds: -5)), '0 s'); // horloge recalée
  });
}
