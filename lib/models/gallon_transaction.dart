class GallonTransaction {
  final String id;
  final String customerId;
  final String? productId;
  final String? saleId;
  final int quantity;
  final String transactionType; // 'deposit', 'return', 'purchase', etc
  final String status; // 'paid', 'unpaid', 'deposit', etc
  final DateTime createdAt;
  final double amount;
  final String? customerName;
  final String? sellerName; // ✅ Added
  final String? sellerId; // ✅ ADD THIS
  final String? productName; // ✅ Added
  final String? customerLocation;

  GallonTransaction({
    required this.id,
    required this.customerId,
    required this.quantity,
    required this.transactionType,
    required this.status,
    required this.createdAt,
    required this.amount,
    this.customerName,
    this.sellerName, // ✅ Added
    this.sellerId, // ✅ ADD THIS
    this.productId,
    this.saleId,
    this.productName, // ✅ Added
    this.customerLocation,
  });

  factory GallonTransaction.fromMap(Map<String, dynamic> map) {
    final parsedDate = DateTime.parse(map['created_at']).toLocal();

    // Handle customer name - prioritize the mapped customer name
    String? customerName;
    if (map['customer'] is Map<String, dynamic> &&
        map['customer']['name'] != null) {
      customerName = map['customer']['name'] as String?;
    } else if (map['customer_name'] != null) {
      customerName = map['customer_name'] as String?;
    } else {
      customerName = 'مجهول';
    }

    // Handle seller information - prioritize direct seller fields
    String? sellerName = map['seller_name'] as String?;
    String? sellerId = map['seller_id'] as String?;
    String? productName = map['product_name'] as String?;

    // Fallback to sale data if direct fields are not available
    if (sellerName == null || sellerId == null || productName == null) {
      final sale = map['sale'] as Map<String, dynamic>?;
      if (sale != null) {
        sellerId ??= sale['sold_by'] as String?;
        if (sellerName == null) {
          final profile = sale['seller_profile'] as Map<String, dynamic>?;
          if (profile != null) {
            final first = profile['first_name'] ?? '';
            final last = profile['last_name'] ?? '';
            sellerName = '$first $last'.trim();
          }
        }
        if (productName == null) {
          final product = sale['product'] as Map<String, dynamic>?;
          if (product != null) {
            productName = product['name'] as String?;
          }
        }
      }
    }

    String? customerLocation;
    if (map['customer'] is Map<String, dynamic> &&
        map['customer']['location'] != null) {
      customerLocation = map['customer']['location'] as String?;
    }

    return GallonTransaction(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      productId: map['product_id'] as String?,
      saleId: map['sale_id'] as String?,
      quantity: (map['quantity'] as num).toInt(),
      transactionType: map['transaction_type'] as String,
      status: map['status'] as String? ?? 'unknown',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: parsedDate,
      customerName: customerName,
      sellerName: sellerName,
      sellerId: sellerId,
      productName: productName ?? 'Unknown Product',
      customerLocation: customerLocation,
    );
  }
}
