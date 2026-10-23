// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_gallon_transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OfflineGallonTransactionAdapter
    extends TypeAdapter<OfflineGallonTransaction> {
  @override
  final int typeId = 5;

  @override
  OfflineGallonTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OfflineGallonTransaction(
      localTxId: fields[0] as String,
      saleLocalId: fields[1] as String,
      customerId: fields[2] as String?,
      productId: fields[3] as String?,
      quantity: fields[4] as int,
      transactionType: fields[5] as String,
      status: fields[6] as String?,
      createdAt: fields[7] as DateTime,
      amount: fields[8] as double,
      saleId: fields[9] as String?,
      customerName: fields[10] as String?,
      productName: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, OfflineGallonTransaction obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.localTxId)
      ..writeByte(1)
      ..write(obj.saleLocalId)
      ..writeByte(2)
      ..write(obj.customerId)
      ..writeByte(3)
      ..write(obj.productId)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.transactionType)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.amount)
      ..writeByte(9)
      ..write(obj.saleId)
      ..writeByte(10)
      ..write(obj.customerName)
      ..writeByte(11)
      ..write(obj.productName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfflineGallonTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
