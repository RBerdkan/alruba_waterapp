import 'package:hive/hive.dart';

part 'offline_gallon_transaction.g.dart';

@HiveType(typeId: 5)
class OfflineGallonTransaction extends HiveObject {
  @HiveField(0)
  final String localTxId; // Required for Hive operations

  @HiveField(1)
  final String saleLocalId; // Reference to local sale ID

  @HiveField(2)
  String? customerId;

  @HiveField(3)
  String? productId;

  @HiveField(4)
  int quantity;

  @HiveField(5)
  String transactionType;

  @HiveField(6)
  String? status;

  @HiveField(7)
  DateTime createdAt;

  @HiveField(8)
  double amount;

  @HiveField(9)
  String? saleId; // Will be populated after sync

  @HiveField(10)
  String? customerName; // Store customer name for display

  @HiveField(11)
  String? productName; // Store product name for display

  OfflineGallonTransaction({
    required this.localTxId, // Made required
    required this.saleLocalId, // Made required
    this.customerId,
    this.productId,
    required this.quantity,
    required this.transactionType,
    this.status,
    required this.createdAt,
    required this.amount,
    this.saleId,
    this.customerName,
    this.productName,
  });
}
