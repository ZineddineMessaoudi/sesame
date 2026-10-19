// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_adapters.dart';

// **************************************************************************
// AdaptersGenerator
// **************************************************************************

class GateStatusAdapter extends TypeAdapter<GateStatus> {
  @override
  final typeId = 0;

  @override
  GateStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return GateStatus.open;
      case 1:
        return GateStatus.closed;
      case 2:
        return GateStatus.opening;
      case 3:
        return GateStatus.closing;
      default:
        return GateStatus.open;
    }
  }

  @override
  void write(BinaryWriter writer, GateStatus obj) {
    switch (obj) {
      case GateStatus.open:
        writer.writeByte(0);
      case GateStatus.closed:
        writer.writeByte(1);
      case GateStatus.opening:
        writer.writeByte(2);
      case GateStatus.closing:
        writer.writeByte(3);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GateStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GateStateAdapter extends TypeAdapter<GateState> {
  @override
  final typeId = 1;

  @override
  GateState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GateState(
      status: fields[0] as GateStatus,
      reportedAt: fields[1] as DateTime?,
      seq: (fields[2] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, GateState obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.status)
      ..writeByte(1)
      ..write(obj.reportedAt)
      ..writeByte(2)
      ..write(obj.seq);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GateStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GateSnapshotAdapter extends TypeAdapter<GateSnapshot> {
  @override
  final typeId = 2;

  @override
  GateSnapshot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GateSnapshot(
      state: fields[0] as GateState,
      receivedAt: fields[1] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, GateSnapshot obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.state)
      ..writeByte(1)
      ..write(obj.receivedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GateSnapshotAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
