import 'package:flutter_test/flutter_test.dart';
import 'package:sesame/features/gate/data/models/device_status.dart';

void main() {
  group('DeviceStatus.tryParse', () {
    test('accepte le texte brut publié par le firmware', () {
      expect(DeviceStatus.tryParse('online'), DeviceStatus.online);
      expect(DeviceStatus.tryParse('offline'), DeviceStatus.offline);
    });

    test('accepte la forme JSON du contrat', () {
      expect(DeviceStatus.tryParse('"offline"'), DeviceStatus.offline);
    });

    test('rejette une valeur inconnue', () {
      expect(DeviceStatus.tryParse('rebooting'), isNull);
      expect(DeviceStatus.tryParse(''), isNull);
    });
  });
}
