import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sesame/core/connectivity/connection_notifier.dart';
import 'package:sesame/features/gate/data/gate_repository.dart';
import 'package:sesame/features/gate/data/models/device_status.dart';
import 'package:sesame/features/gate/data/models/gate_snapshot.dart';
import 'package:sesame/features/gate/data/models/gate_state.dart';
import 'package:sesame/features/gate/viewmodels/gate_view_model.dart';

class MockGateRepository extends Mock implements GateRepository {}

/// Qualité de connexion pilotée par le test.
class FakeConnection extends ConnectionNotifier {
  @override
  ConnectionQuality build() => ConnectionQuality.online;

  void set(ConnectionQuality quality) => state = quality;
}

void main() {
  late MockGateRepository repository;
  late StreamController<DeviceStatus> devices;
  late ProviderContainer container;

  final cached = GateSnapshot(
    state: const GateState(status: GateStatus.closed, reportedAt: null, seq: 1),
    receivedAt: DateTime.utc(2026, 10, 19, 8),
  );
  final confirmed = GateSnapshot(
    state: cached.state,
    receivedAt: DateTime.utc(2026, 10, 19, 10),
  );

  setUp(() {
    repository = MockGateRepository();
    devices = StreamController<DeviceStatus>.broadcast();
    when(() => repository.watchGateState())
        .thenAnswer((_) => const Stream.empty());
    when(() => repository.watchDeviceStatus())
        .thenAnswer((_) => devices.stream);
    when(() => repository.connect()).thenAnswer((_) async {});
    when(() => repository.lastKnown).thenReturn(cached);
    when(() => repository.confirmNow()).thenReturn(confirmed);
    container = ProviderContainer(
      overrides: [
        gateRepositoryProvider.overrideWithValue(repository),
        connectionProvider.overrideWith(FakeConnection.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(gateViewModelProvider, (_, _) {});
  });

  GateViewState state() => container.read(gateViewModelProvider);
  FakeConnection connection() =>
      container.read(connectionProvider.notifier) as FakeConnection;

  test('démarre sur le cache, sans prétendre être en direct', () {
    expect(state().gate?.status, GateStatus.closed);
    expect(state().isLive, isFalse);
  });

  test(
    'en direct quand la connexion est online et l\'ESP32 en ligne',
    () async {
      devices.add(DeviceStatus.online);
      await pumpEventQueue();

      expect(state().isLive, isTrue);
    },
  );

  test('perte du réseau : fin du direct, état daté de cet instant', () async {
    devices.add(DeviceStatus.online);
    await pumpEventQueue();

    connection().set(ConnectionQuality.offline);
    await pumpEventQueue();

    expect(state().isLive, isFalse);
    expect(state().confirmedAt, confirmed.receivedAt);
    verify(() => repository.confirmNow()).called(1);
  });

  test('ESP32 hors ligne (LWT) : fin du direct aussi', () async {
    devices.add(DeviceStatus.online);
    await pumpEventQueue();

    devices.add(DeviceStatus.offline);
    await pumpEventQueue();

    expect(state().isLive, isFalse);
    verify(() => repository.confirmNow()).called(1);
  });

  test('sans avoir été en direct, rien n\'est re-daté', () async {
    connection().set(ConnectionQuality.offline);
    await pumpEventQueue();

    verifyNever(() => repository.confirmNow());
    expect(state().confirmedAt, cached.receivedAt);
  });

  test('hors connexion, le statut de l\'ESP32 redevient inconnu', () async {
    devices.add(DeviceStatus.online);
    await pumpEventQueue();
    expect(state().visibleDevice, DeviceStatus.online);

    connection().set(ConnectionQuality.degraded);
    await pumpEventQueue();

    expect(state().visibleDevice, isNull);
  });
}
