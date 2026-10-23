// GallonTransactionStatusPage: Enhanced with product details, pricing, and better tracking

import 'package:alruba_waterapp/providers/distributor_sales_provider.dart';
import 'package:alruba_waterapp/providers/manager_slaes_provider.dart';
import 'package:alruba_waterapp/services/gallon_payment-service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../../../services/supabase_service.dart';

// Number formatter for Lebanese Pound
final _lbpFormatter = NumberFormat.currency(
  locale: 'ar_LB',
  symbol: 'ل.ل ',
  decimalDigits: 0,
);

class GallonTransactionStatusPage extends ConsumerStatefulWidget {
  const GallonTransactionStatusPage({super.key});

  @override
  ConsumerState<GallonTransactionStatusPage> createState() =>
      _GallonTransactionStatusPageState();
}

class _GallonTransactionStatusPageState
    extends ConsumerState<GallonTransactionStatusPage> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _showSettled = false;
  String _search = '';
  List<Map<String, dynamic>> _transactions = [];
  Map<String, Map<String, dynamic>> _customers = {};
  Map<String, Map<String, dynamic>> _products = {};
  bool _isNewCustomer = true;
  String _newCustomerType = 'regular';
  String _existingCustomerType = 'regular';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final txs = await SupabaseService.client
          .from('gallon_transactions')
          .select(
              '*, customer:customers(name, type), sale:sales(id, sold_by, seller_profile:profiles!sales_sold_by_fkey(first_name, last_name))')
          .order('created_at', ascending: false);

      final customerIds = txs
          .map((t) => t['customer_id'] as String?)
          .where((id) => id != null)
          .map((id) => id!)
          .toSet()
          .toList();
      final productIds = txs
          .map((t) => t['product_id'] as String?)
          .where((id) => id != null)
          .map((id) => id!)
          .toSet()
          .toList();
      final saleIds = txs
          .map((t) => t['sale_id'] as String?)
          .where((id) => id != null)
          .map((id) => id!)
          .toSet()
          .toList();

      final customerList = customerIds.isNotEmpty
          ? await SupabaseService.client
              .from('customers')
              .select('id, name, type')
              .inFilter('id', customerIds)
          : <Map<String, dynamic>>[];

      final productList = productIds.isNotEmpty
          ? await SupabaseService.client
              .from('products')
              .select('id, name, home_price, market_price')
              .inFilter('id', productIds)
          : <Map<String, dynamic>>[];

      final salesList = saleIds.isNotEmpty
          ? await SupabaseService.client
              .from('sales')
              .select('id, location_id')
              .inFilter('id', saleIds)
          : <Map<String, dynamic>>[];

      final salesMap = {for (var s in salesList) s['id']: s['location_id']};
      final customersMap = {for (var c in customerList) c['id']: c};
      final productsMap = {for (var p in productList) p['id']: p};

      _transactions = txs.map((tx) {
        final customerId = tx['customer_id'] as String?;
        final customerData =
            customerId != null ? (customersMap[customerId] ?? {}) : {};
        final customerName = customerData['name'] ?? customerId ?? 'مجهول';
        final customerType = customerData['type'] ?? 'regular';

        final productData = productsMap[tx['product_id']] ?? {};
        final productName = productData['name'] ?? 'غير معروف';

        // Use appropriate price based on customer type
        final homePrice = (productData['home_price'] as num?) ?? 0.0;
        final marketPrice = (productData['market_price'] as num?) ?? 0.0;
        final productPrice =
            customerType == 'distributor' ? marketPrice : homePrice;

        return {
          ...tx,
          'customer': {
            'name': customerName,
            'type': customerType,
          },
          'product': {
            'name': productName,
            'home_price': homePrice,
            'market_price': marketPrice,
            'price': productPrice,
          },
          'location_id': tx['sale_id'] != null ? salesMap[tx['sale_id']] : null,
        };
      }).toList();

      // Debug output
      if (_transactions.isNotEmpty) {
        print(
            'Gallon status page loaded: ${_transactions.length} transactions');
        print(
            'First transaction customer: ${_transactions.first['customer']?['name']}');
        // Print all transactions for debugging
        for (final tx in _transactions) {
          print(
              'TX: type=${tx['transaction_type']} qty=${tx['quantity']} cust=${tx['customer_id']} prod=${tx['product_id']} sale=${tx['sale_id']} id=${tx['id']}');
        }
      }
    } catch (e) {
      _snack('خطأ أثناء التحميل: $e', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group deposits
    final deposits = _transactions
        .where((t) =>
            t['transaction_type'] == 'deposit' &&
            (t['is_settled'] == false || _showSettled) &&
            (t['customer']?['name']?.toLowerCase()?.contains(_search) ?? true))
        .toList();

    // Calculate total unsettled gallons across all deposits
    int totalUnsettledGallons = 0;
    double totalUnsettledValue = 0.0;

    List<Widget> depositGroups = [];
    for (final deposit in deposits) {
      // Find related returns and payments
      final related = _transactions
          .where((t) =>
              t['customer_id'] == deposit['customer_id'] &&
              t['product_id'] == deposit['product_id'] &&
              t['id'] != deposit['id'] &&
              DateTime.parse(t['created_at'])
                  .isAfter(DateTime.parse(deposit['created_at'])))
          .toList();
      final returns =
          related.where((t) => t['transaction_type'] == 'return').toList();
      final payments = related
          .where((t) =>
              (t['transaction_type'] == 'purchase' ||
                  t['transaction_type'] == 'paid') &&
              t['linked_deposit_id'] == deposit['id'])
          .toList();
      final paid = payments.fold(0, (sum, t) => sum + (t['quantity'] as int));
      final returned =
          returns.fold(0, (sum, t) => sum + (t['quantity'] as int));
      final remaining = (deposit['quantity'] as int) - paid - returned;

      // Add to total unsettled if not fully settled
      if (remaining > 0) {
        totalUnsettledGallons += remaining;
        final productPrice = (deposit['product']?['price'] as num?) ?? 0.0;
        totalUnsettledValue += remaining * productPrice;
      }

      // Hide finished deposits unless _showSettled is ON
      if (!_showSettled && remaining == 0) continue;

      final dt = DateTime.tryParse(deposit['created_at'])?.toLocal();
      final productName = deposit['product']?['name'] ?? 'غير معروف';
      final productPrice = (deposit['product']?['price'] as num?) ?? 0.0;
      final totalValue = remaining * productPrice;

      depositGroups.add(
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ExpansionTile(
            initiallyExpanded: false,
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${deposit['customer']?['name'] ?? 'مجهول'} • $productName',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'السعر: ${_lbpFormatter.format(productPrice)} للجالون',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  (deposit['customer']?['type'] == 'distributor'
                                          ? Colors.blue
                                          : Colors.green)
                                      .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              deposit['customer']?['type'] == 'distributor'
                                  ? 'موزع'
                                  : 'عادي',
                              style: TextStyle(
                                fontSize: 10,
                                color: deposit['customer']?['type'] ==
                                        'distributor'
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.money, color: Colors.green),
                  onPressed: () => _confirmAction(deposit, 'pay'),
                ),
                IconButton(
                  icon: const Icon(Icons.reply, color: Colors.orange),
                  onPressed: () => _confirmAction(deposit, 'return'),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'تاريخ الإيداع: ${dt != null ? DateFormat('yyyy-MM-dd – HH:mm').format(dt) : '?'}'),
                Text('الكمية الأصلية: ${deposit['quantity']} جالون'),
                Text('المتبقي: $remaining جالون',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (remaining > 0)
                  Text('القيمة المتبقية: ${_lbpFormatter.format(totalValue)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            children: [
              if (payments.isNotEmpty)
                ...payments.map((p) => ListTile(
                      leading:
                          const Icon(Icons.shopping_cart, color: Colors.blue),
                      title: const Text('دفع مقابل الجالون'),
                      subtitle: Text(
                          'الكمية: ${p['quantity']} جالون\n${DateFormat('yyyy-MM-dd – HH:mm').format(DateTime.parse(p['created_at']).toLocal())}'),
                    )),
              if (returns.isNotEmpty)
                ...returns.map((r) => ListTile(
                      leading:
                          const Icon(Icons.remove_circle, color: Colors.red),
                      title: const Text('إرجاع جالون'),
                      subtitle: Text(
                          'الكمية: ${r['quantity']} جالون\n${DateFormat('yyyy-MM-dd – HH:mm').format(DateTime.parse(r['created_at']).toLocal())}'),
                    )),
              const Divider(),
              Text('المودَع: ${deposit['quantity']} جالون'),
              Text('مدفوع: $paid جالون'),
              Text('مرتجع: $returned جالون'),
              Text('المتبقي: $remaining جالون',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (remaining > 0)
                Text('القيمة المتبقية: ${totalValue.toStringAsFixed(2)} د.ك',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تفاصيل الأسعار:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                        'سعر المنزل: ${_lbpFormatter.format((deposit['product']?['home_price'] as num?) ?? 0.0)}'),
                    Text(
                        'سعر السوق: ${_lbpFormatter.format((deposit['product']?['market_price'] as num?) ?? 0.0)}'),
                    const SizedBox(height: 4),
                    Text(
                      'السعر المستخدم: ${_lbpFormatter.format(productPrice)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '(${deposit['customer']?['type'] == 'distributor' ? 'سعر السوق' : 'سعر المنزل'})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة جالونات الإيداع'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('إظهار المغلقة', style: TextStyle(fontSize: 12)),
              Switch(
                value: _showSettled,
                onChanged: (val) => setState(() => _showSettled = val),
              ),
            ],
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Summary card
                  if (!_showSettled && totalUnsettledGallons > 0)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'إجمالي الجالونات غير المسددة',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                Text(
                                  '$totalUnsettledGallons جالون • ${_lbpFormatter.format(totalUnsettledValue)}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              labelText: 'ابحث باسم الزبون',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (deposits.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('لا توجد نتائج')),
                          )
                        else
                          ...depositGroups,
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmAction(Map<String, dynamic> tx, String action) async {
    // Calculate current paid and returned for this deposit
    final related = _transactions
        .where((t) =>
            t['customer_id'] == tx['customer_id'] &&
            t['product_id'] == tx['product_id'] &&
            t['id'] != tx['id'] &&
            DateTime.parse(t['created_at'])
                .isAfter(DateTime.parse(tx['created_at'])))
        .toList();
    final paid = related
        .where((t) =>
            t['transaction_type'] == 'purchase' ||
            t['transaction_type'] == 'paid')
        .fold(0, (sum, t) => sum + (t['quantity'] as int));
    final returned = related
        .where((t) => t['transaction_type'] == 'return')
        .fold(0, (sum, t) => sum + (t['quantity'] as int));
    final remaining = (tx['quantity'] as int) - paid - returned;

    final qty = await showDialog<int>(
      context: context,
      builder: (ctx) => _QuantityDialog(
        maxQuantity: remaining,
        action: action,
        pricePerUnit: ((tx['product']?['price'] as num?) ?? 0.0).toDouble(),
      ),
    );

    if (qty == null) return;

    if (qty <= 0 || qty > remaining) {
      _snack('كمية غير صالحة أو تتجاوز المتبقي ($remaining جالون)', Colors.red);
      return;
    }

    try {
      if (action == 'pay') {
        final pricePerUnit =
            ((tx['product']?['price'] as num?) ?? 0.0).toDouble();
        // For deposits, get location from customer's profile
        String? locationId = tx['location_id'];
        if (locationId == null) {
          // Get customer's location
          try {
            final customer = await SupabaseService.client
                .from('customers')
                .select('location_id')
                .eq('id', tx['customer_id'])
                .single();
            locationId = customer['location_id']?.toString();

            if (locationId == null) {
              _snack('خطأ: العميل ليس له موقع محدد', Colors.red);
              return;
            }
          } catch (e) {
            _snack('خطأ: لا يمكن الحصول على موقع العميل', Colors.red);
            return;
          }
        }

        await payForDeposit(
          context: context,
          customerId: tx['customer_id'],
          productId: tx['product_id'],
          quantity: qty,
          pricePerUnit: pricePerUnit,
          linkedDepositSaleId:
              tx['sale_id'] ?? tx['id'], // Use transaction ID if no sale ID
          locationId: locationId,
        );
      } else {
        await SupabaseService.client.from('gallon_transactions').insert({
          'customer_id': tx['customer_id'],
          'product_id': tx['product_id'],
          'quantity': qty,
          'transaction_type': 'return',
          'status': 'paid',
          'amount': 0,
          'sale_id': tx['sale_id'],
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'is_settled': false,
          'seller_id': SupabaseService.client.auth.currentUser?.id,
        });
      }

      if (remaining > 0) {
        // Do not update the original deposit's quantity. Only mark as settled if needed.
      } else {
        await SupabaseService.client
            .from('gallon_transactions')
            .update({'is_settled': true}).eq('id', tx['id']);
      }

      _snack('تم تنفيذ العملية بنجاح', Colors.green);
      await _fetch();
      // After fetch, print related transactions for this deposit
      final depositId = tx['id'];
      final deposit = _transactions.firstWhere((t) => t['id'] == depositId,
          orElse: () => {});
      if (deposit.isNotEmpty) {
        final related = _transactions
            .where((t) =>
                t['customer_id'] == deposit['customer_id'] &&
                t['product_id'] == deposit['product_id'] &&
                t['id'] != deposit['id'] &&
                DateTime.parse(t['created_at'])
                    .isAfter(DateTime.parse(deposit['created_at'])))
            .toList();
        print(
            'After payment, related transactions for deposit ${deposit['id']}');
        for (final t in related) {
          print(
              '  type=${t['transaction_type']} qty=${t['quantity']} id=${t['id']}');
        }
      }
      ref.invalidate(distributorSalesProvider);
      ref.invalidate(managerSalesProvider);
    } catch (e) {
      _snack('فشل في تنفيذ العملية: $e', Colors.red);
    }
  }

  void _snack(String m, Color c) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }
}

class _QuantityDialog extends StatefulWidget {
  final int maxQuantity;
  final String action;
  final double pricePerUnit;

  const _QuantityDialog({
    required this.maxQuantity,
    required this.action,
    required this.pricePerUnit,
  });

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  int qty = 1;

  @override
  Widget build(BuildContext context) {
    final totalAmount = qty * widget.pricePerUnit;

    return AlertDialog(
      title: Text(widget.action == 'pay' ? 'دفع جالونات' : 'إرجاع جالونات'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () =>
                      setState(() => qty = (qty > 1) ? qty - 1 : qty)),
              Text('$qty', style: const TextStyle(fontSize: 20)),
              IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(
                      () => qty = (qty < widget.maxQuantity) ? qty + 1 : qty)),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.action == 'pay' && widget.pricePerUnit > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    'المبلغ المطلوب',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    _lbpFormatter.format(totalAmount),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '(${_lbpFormatter.format(widget.pricePerUnit)} × $qty جالون)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, qty),
            child: const Text('تأكيد')),
      ],
    );
  }
}
