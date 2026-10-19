import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/storage/encryption_key_store.dart';
import 'package:sesame/features/gate/data/models/gate_snapshot.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';

import '../../helpers/hive_box.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('EncryptionKeyStore', () {
    late MockSecureStorage storage;
    final saved = <String, String>{};

    setUp(() {
      saved.clear();
      storage = MockSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((i) async => saved[i.namedArguments[#key]]);
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer(
        (i) async => saved[i.namedArguments[#key] as String] =
            i.namedArguments[#value] as String,
      );
    });

    test(
      'génère une clé de 256 bits au premier lancement et la stocke',
      () async {
        final key = await EncryptionKeyStore(storage).loadOrCreate();

        expect(key, hasLength(32));
        expect(base64Decode(saved.values.single), key);
      },
    );

    test('réutilise la même clé aux lancements suivants', () async {
      final first = await EncryptionKeyStore(storage).loadOrCreate();
      final second = await EncryptionKeyStore(storage).loadOrCreate();

      expect(second, first);
      verify(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).called(1);
    });
  });

  test('la box chiffrée ne se relit qu\'avec la bonne clé', () async {
    final key = Hive.generateSecureKey();
    final box = await openTestBox<GateSnapshot>(
      cipher: HiveAesCipher(key),
      name: 'chiffree',
    );
    await box.put(
      'current',
      GateSnapshot(
        state: const GateState(
          status: GateStatus.open,
          reportedAt: null,
          seq: 7,
        ),
        receivedAt: DateTime.utc(2026, 10, 19),
      ),
    );
    await box.close();

    final reopened = await openTestBox<GateSnapshot>(
      cipher: HiveAesCipher(key),
      name: 'chiffree',
    );
    expect(reopened.get('current')?.state.seq, 7);
    await reopened.close();

    // Mauvaise clé : la donnée n'est pas lisible.
    await expectLater(
      openTestBox<GateSnapshot>(
        cipher: HiveAesCipher(Hive.generateSecureKey()),
        name: 'chiffree',
      ).then((b) => b.get('current')),
      throwsA(anything),
    );
  });
}
