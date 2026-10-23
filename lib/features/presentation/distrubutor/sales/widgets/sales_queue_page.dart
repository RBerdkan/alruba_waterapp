import 'package:alruba_waterapp/models/offline_gallon_transaction.dart';
import 'package:alruba_waterapp/providers/customers_provider.dart';
import 'package:alruba_waterapp/providers/distributor_sales_provider.dart';
import 'package:alruba_waterapp/providers/gallon_transactionprovider.dart';
import 'package:alruba_waterapp/providers/manager_slaes_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:alruba_waterapp/models/offline_sale.dart';
import 'package:alruba_waterapp/services/offline_sync_service.dart';

class SalesQueuePage extends ConsumerStatefulWidget {
  const SalesQueuePage({super.key});

  @override
  ConsumerState<SalesQueuePage> createState() => _SalesQueuePageState();
}

class _SalesQueuePageState extends ConsumerState<SalesQueuePage> {
  bool _isSyncing = false;
  bool _boxesInitialized = false;

  // LBP currency formatter
  final _lbpFormat = NumberFormat.currency(
    locale: 'ar_LB',
    symbol: 'ل.ل',
    name: '', // Prevent LPB from being added
    decimalDigits: 0,
    customPattern: '#,##0 ¤', // Number then currency
  );

  @override
  void initState() {
    super.initState();
    _ensureBoxesOpen();
  }

  Future<void> _syncSales() async {
    setState(() {
      _isSyncing = true;
    });
    try {
      final salesBox = Hive.box<OfflineSale>('offline_sales');
      final gallonBox =
          Hive.box<OfflineGallonTransaction>('offline_gallon_transactions');

      final List<OfflineSale> localSales = salesBox.values.toList();
      final List<OfflineGallonTransaction> localGallons =
          gallonBox.values.toList();

      await OfflineSyncService().syncOfflineData();

      ref.invalidate(customersProvider);
      ref.invalidate(distributorSalesProvider);

      // Clear both boxes after successful sync
      await salesBox.clear();
      await gallonBox.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تمت المزامنة بنجاح! ${localSales.length} مبيعات و ${localGallons.length} ودائع'),
          backgroundColor: Colors.green,
        ),
      );
      ref.invalidate(distributorSalesProvider);
      ref.invalidate(managerSalesProvider);
      ref.invalidate(gallonTransactionsProvider);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشلت المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<void> _clearQueue() async {
    final saleBox = Hive.box<OfflineSale>('offline_sales');
    await saleBox.clear();

    final txBox = await Hive.openBox<OfflineGallonTransaction>(
        'offline_gallon_transactions');
    await txBox.clear();

    if (!mounted) return;
    setState(() {});
  }

  // Helper method to ensure both boxes are opened
  Future<void> _ensureBoxesOpen() async {
    try {
      await Hive.openBox<OfflineSale>('offline_sales');
      await Hive.openBox<OfflineGallonTransaction>(
          'offline_gallon_transactions');
      if (mounted) {
        setState(() {
          _boxesInitialized = true;
        });
      }
    } catch (e) {
      print('Error opening Hive boxes: $e');
    }
  }

  void _showSaleDetails(OfflineSale sale) {
    final formattedDate =
        DateFormat('yyyy-MM-dd hh:mm a').format(sale.createdAt);
    final phoneNumber = sale.customerPhone ?? sale.newCustomerPhone ?? 'N/A';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            sale.customerName ?? 'عميل غير معروف',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الهاتف: $phoneNumber',
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 10),
                const Divider(thickness: 1.2),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('المنتج: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(sale.productName ?? 'لا يوجد منتج')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('الكمية: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${sale.quantity}'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('السعر لكل وحدة: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_lbpFormat.format(sale.pricePerUnit)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('الإجمالي: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_lbpFormat.format(sale.totalPrice)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('الدفع: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(sale.paymentStatus),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('تاريخ الإنشاء: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formattedDate),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showGallonTransactionDetails(OfflineGallonTransaction transaction) {
    final formattedDate =
        DateFormat('yyyy-MM-dd hh:mm a').format(transaction.createdAt);

    String transactionType = '';
    String description = '';
    IconData icon = Icons.water_drop;
    Color color = Colors.blue;

    switch (transaction.transactionType) {
      case 'deposit':
        transactionType = 'وديعة (ثقة)';
        description = 'تم إعطاء الجالونات للعميل على الثقة بدون دفع';
        icon = Icons.account_balance_wallet;
        color = Colors.purple;
        break;
      case 'purchase':
        transactionType = 'شراء جالونات';
        description = 'تم شراء الجالونات مع الدفع';
        icon = Icons.shopping_cart;
        color = Colors.green;
        break;
      case 'return':
        transactionType = 'إرجاع جالونات';
        description = 'تم إرجاع الجالونات الفارغة';
        icon = Icons.swap_horiz;
        color = Colors.orange;
        break;
      default:
        transactionType = transaction.transactionType;
        description = 'عملية جالون عادية';
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(transactionType),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description,
                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 16),
                const Divider(thickness: 1.2),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('العميل: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(transaction.customerName ?? 'غير محدد'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('المنتج: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(transaction.productName ?? 'غير محدد'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('الكمية: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${transaction.quantity} جالون'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('المبلغ: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(transaction.amount > 0
                        ? _lbpFormat.format(transaction.amount)
                        : 'مجاني'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('الحالة: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(transaction.status ?? 'غير محدد'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('تاريخ الإنشاء: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formattedDate),
                  ],
                ),
                if ((transaction.saleLocalId ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('معرف البيع: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text((transaction.saleLocalId ?? '').substring(0, 8) +
                          '...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("قائمة الانتظار"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _isSyncing ? null : _syncSales,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label:
                        Text(_isSyncing ? 'جارٍ المزامنة...' : 'مزامنة الكل'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          title: const Text('مسح القائمة'),
                          content: const Text(
                              'هل أنت متأكد من حذف جميع المبيعات غير المتزامنة؟'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('تأكيد'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _clearQueue();
                      }
                    },
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('مسح الكل'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'المبيعات'),
                      Tab(text: 'الودائع'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Sales Tab
                        !_boxesInitialized
                            ? const Center(child: CircularProgressIndicator())
                            : ValueListenableBuilder<Box<OfflineSale>>(
              valueListenable:
                                    Hive.box<OfflineSale>('offline_sales')
                                        .listenable(),
              builder: (context, box, _) {
                final unsyncedSales = box.values.toList();
                if (unsyncedSales.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا توجد مبيعات غير متزامنة!',
                      style: TextStyle(fontSize: 18),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: unsyncedSales.length,
                  itemBuilder: (context, index) {
                    final sale = unsyncedSales[index];
                                      final customerLabel =
                                          sale.customerName ?? 'عميل غير معروف';
                                      final productLabel =
                                          sale.productName ?? 'لا يوجد منتج';
                    return Card(
                      margin: const EdgeInsets.all(8),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                      child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                                          leading: const Icon(
                                              Icons.pending_actions,
                                              size: 30),
                        title: Text(
                          customerLabel,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                        ),
                                          subtitle: Text(
                                              'المنتج: $productLabel\n'
                            'الكمية: ${sale.quantity} | السعر: ${_lbpFormat.format(sale.pricePerUnit)}'),
                        trailing: Text(
                          _lbpFormat.format(sale.totalPrice),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                        ),
                        onTap: () => _showSaleDetails(sale),
                      ),
                    );
                  },
                );
              },
                              ),
                        // Gallon Transactions Tab
                        !_boxesInitialized
                            ? const Center(child: CircularProgressIndicator())
                            : ValueListenableBuilder<
                                Box<OfflineGallonTransaction>>(
                                valueListenable:
                                    Hive.box<OfflineGallonTransaction>(
                                            'offline_gallon_transactions')
                                        .listenable(),
                                builder: (context, box, _) {
                                  final unsyncedTransactions =
                                      box.values.toList();
                                  if (unsyncedTransactions.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        'لا توجد ودائع غير متزامنة!',
                                        style: TextStyle(fontSize: 18),
                                      ),
                                    );
                                  }
                                  return ListView.builder(
                                    itemCount: unsyncedTransactions.length,
                                    itemBuilder: (context, index) {
                                      final transaction =
                                          unsyncedTransactions[index];
                                      String transactionType = '';
                                      IconData icon = Icons.water_drop;
                                      Color color = Colors.blue;

                                      switch (transaction.transactionType) {
                                        case 'deposit':
                                          transactionType = 'وديعة (ثقة)';
                                          icon = Icons.account_balance_wallet;
                                          color = Colors.purple;
                                          break;
                                        case 'purchase':
                                          transactionType = 'شراء جالونات';
                                          icon = Icons.shopping_cart;
                                          color = Colors.green;
                                          break;
                                        case 'return':
                                          transactionType = 'إرجاع جالونات';
                                          icon = Icons.swap_horiz;
                                          color = Colors.orange;
                                          break;
                                        default:
                                          transactionType =
                                              transaction.transactionType;
                                      }

                                      return Card(
                                        margin: const EdgeInsets.all(8),
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 10),
                                          leading: Icon(icon,
                                              size: 30, color: color),
                                          title: Text(
                                            transaction.customerName ??
                                                transactionType,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          subtitle: Text(
                                              'الكمية: ${transaction.quantity} جالون\n'
                                              'النوع: ${transaction.transactionType}\n'
                                              'التاريخ: ${DateFormat('MMM dd, HH:mm').format(transaction.createdAt)}'),
                                          onTap: () =>
                                              _showGallonTransactionDetails(
                                                  transaction),
                                          trailing: transaction.amount > 0
                                              ? Text(
                                                  _lbpFormat.format(
                                                      transaction.amount),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )
                                              : const Text('مجاني'),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
