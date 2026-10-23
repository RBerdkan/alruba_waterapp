import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alruba_waterapp/services/supabase_service.dart';

class ManagerSale {
  final String saleId;
  final DateTime date;
  final String paymentStatus;
  final int quantity;
  final double pricePerUnit;
  final double totalAmount;
  final String productName;
  final String customerName;
  final String phone;
  final String location;
  final String? preciseLocation;
  final DateTime? paymentDate;
  final double amountPaid;
  final String? sellerName;
  final String? sellerRole;
  final String? sellerId; // Add this if not already present
  final String? saleType;

  ManagerSale({
    required this.saleId,
    required this.date,
    required this.paymentStatus,
    required this.quantity,
    required this.pricePerUnit,
    required this.totalAmount,
    required this.productName,
    required this.customerName,
    required this.phone,
    required this.location,
    this.preciseLocation,
    this.paymentDate,
    required this.amountPaid,
    this.sellerName,
    this.sellerRole,
    this.sellerId,
    this.saleType,
  });

  factory ManagerSale.fromMap(Map<String, dynamic> m) {
    final customer = m['customer'] as Map<String, dynamic>? ?? {};
    final locData = customer['location'] as Map<String, dynamic>?;

    final product = m['product'] as Map<String, dynamic>? ?? {};
    final sellerProfile = m['seller_profile'] as Map<String, dynamic>? ?? {};

    final rawPd = m['payment_date'];
    DateTime? pd;
    if (rawPd != null) {
      if (rawPd is String) {
        pd = DateTime.parse(rawPd).toLocal();
      } else if (rawPd is DateTime) {
        pd = rawPd.toLocal();
      }
    }

    final sellerFirst = sellerProfile['first_name'] as String? ?? '';
    final sellerLast = sellerProfile['last_name'] as String? ?? '';
    final sellerFullName = '$sellerFirst $sellerLast'.trim();

    return ManagerSale(
      saleId: m['id'] as String,
      date: DateTime.parse(m['created_at'] as String).toLocal(),
      paymentDate: pd,
      paymentStatus:
          (m['payment_status'] as String?)?.toLowerCase() ?? 'unknown',
      quantity: (m['quantity'] as num?)?.toInt() ?? 0,
      pricePerUnit: (m['price_per_unit'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (m['total_amount'] as num?)?.toDouble() ??
          ((m['quantity'] as num?)?.toInt() ?? 0) *
              ((m['price_per_unit'] as num?)?.toDouble() ?? 0.0),
      productName: product['name'] as String? ?? 'Unknown Item',
      customerName: customer['name'] as String? ?? 'Unknown',
      phone: customer['phone'] as String? ?? '',
      location: locData?['name'] as String? ?? 'Unknown',
      preciseLocation: customer['precise_location'] as String?,
      amountPaid: (m['amount_paid'] ?? 0).toDouble(),
      sellerName: sellerFullName,
      sellerRole: m['seller_profile']?['role'] as String?,
      sellerId: m['sold_by'] as String?,
      saleType: m['sale_type'] as String?,
    );
  }
}

final managerSalesProvider =
    FutureProvider.autoDispose<List<ManagerSale>>((ref) async {
  final resp = await SupabaseService.client.from('sales').select(r'''
        id,
        created_at,
        payment_date,
        payment_status,
        quantity,
        price_per_unit,
        total_amount,
        amount_paid,
        sale_type,
        sold_by,
        product:products!fk_sales_product(name),
        customer:customers!fk_sales_customer(
          name,
          phone,
          precise_location,
          location:locations(name)
        ),
seller_profile:profiles!sales_sold_by_fkey(role, first_name, last_name)
      ''')
      // Include all sales (owners, managers, distributors)
      .order('created_at', ascending: true);

  return (resp as List)
      .cast<Map<String, dynamic>>()
      .map((m) => ManagerSale.fromMap(m))
      .toList();
});
