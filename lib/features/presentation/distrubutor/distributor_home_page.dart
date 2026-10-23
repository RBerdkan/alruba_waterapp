import 'package:alruba_waterapp/features/presentation/logout_button.dart';
import 'package:alruba_waterapp/features/presentation/manager/Gallon_transaction_status_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/customer_details_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/owner_unpaid_sale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:alruba_waterapp/features/presentation/distrubutor/sale_form.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/distributor_sales_page.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/sales_queue_page.dart';

import 'package:alruba_waterapp/providers/distributor_sales_provider.dart'
    show DistributorSale, distributorSalesProvider, distributorPaymentsProvider;
import 'package:alruba_waterapp/providers/gallon_transactionprovider.dart'
    show gallonTransactionsProvider;

const _primaryGradient = LinearGradient(
  colors: [Color(0xFF2196F3), Color(0xFF64B5F6)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class DistributorHomePage extends ConsumerStatefulWidget {
  const DistributorHomePage({super.key});

  @override
  ConsumerState<DistributorHomePage> createState() =>
      _DistributorHomePageState();
}

class _DistributorHomePageState extends ConsumerState<DistributorHomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: _primaryGradient),
        ),
        actions: [
          const LogoutButton(fullWidth: false),
          const SizedBox(width: 100),
          IconButton(
            icon: const Icon(Icons.money_off, color: Colors.white),
            tooltip: 'Unpaid customers',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const OwnerUnpaidSalesPage(),
              ));
            },
          ),
          const SizedBox(width: 40),
          IconButton(
            icon: const Icon(Icons.local_drink_outlined, color: Colors.white),
            tooltip: 'Gallons transaction',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const GallonTransactionStatusPage(),
              ));
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const _DashboardTab(),
          const DistributorSalesPage(),
          const SalesQueuePage(),
          const CustomerDetailsPage(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MakeSalePage()),
          );
          ref.invalidate(distributorSalesProvider);
        },
        backgroundColor: Colors.blue.shade800,
        child: const Icon(Icons.add, size: 32, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        elevation: 16,
        padding: EdgeInsets.zero,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            gradient: _primaryGradient,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade900.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, -4),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabButton(Icons.dashboard_outlined, 0),
              _buildTabButton(Icons.list_alt_outlined, 1),
              const SizedBox(width: 48),
              _buildTabButton(Icons.pending_actions_outlined, 2),
              _buildTabButton(Icons.person_outline, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(IconData icon, int index) => IconButton(
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _currentIndex == index
                ? Colors.white.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              size: 28,
              color: _currentIndex == index
                  ? Colors.white
                  : Colors.white.withOpacity(0.7)),
        ),
        onPressed: () => setState(() => _currentIndex = index),
      );
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(distributorSalesProvider);
    final paymentsAsync = ref.watch(distributorPaymentsProvider);
    final gallonsAsync = ref.watch(gallonTransactionsProvider);
    final lbp = NumberFormat.currency(
        locale: 'en_US', symbol: 'LBP ', decimalDigits: 0);

    return salesAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: Colors.blue.shade800)),
      error: (e, _) => Center(
          child:
              Text('Error: $e', style: TextStyle(color: Colors.red.shade800))),
      data: (allSales) {
        return paymentsAsync.when(
          loading: () => Center(
              child: CircularProgressIndicator(color: Colors.blue.shade800)),
          error: (e, _) => Center(
              child: Text('Error loading payments: $e',
                  style: TextStyle(color: Colors.red.shade800))),
          data: (allPayments) {
            return gallonsAsync.when(
              loading: () => Center(
                  child:
                      CircularProgressIndicator(color: Colors.blue.shade800)),
              error: (e, _) => Center(
                  child: Text('Error loading gallons: $e',
                      style: TextStyle(color: Colors.red.shade800))),
              data: (allGallons) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);

                // --- TODAY'S SALES (NORMAL SALES ONLY) ---
                final todayNormalSales = allSales.where((s) {
                  final d = s.date.toLocal();
                  return d.year == now.year &&
                      d.month == now.month &&
                      d.day == now.day &&
                      s.saleType?.toLowerCase() == 'normal';
                }).toList();

                // Calculate unpaid sales total amount
                final unpaidSalesTotal = todayNormalSales
                    .where((s) => s.paymentStatus?.toLowerCase() == 'unpaid')
                    .fold<double>(0, (sum, s) => sum + s.totalAmount);

                // Group normal sales by product
                final Map<String, Map<String, int>> normalSalesByProduct = {};
                for (final sale in todayNormalSales) {
                  final product = sale.productName ?? 'غير محدد';
                  final status = sale.amountPaid >= sale.totalAmount &&
                          sale.totalAmount > 0
                      ? 'paid'
                      : sale.amountPaid > 0 &&
                              sale.amountPaid < sale.totalAmount
                          ? 'partial'
                          : 'unpaid';

                  normalSalesByProduct.putIfAbsent(product,
                      () => {'paid': 0, 'unpaid': 0, 'partial': 0, 'total': 0});
                  final productMap = normalSalesByProduct[product]!;
                  productMap[status] =
                      (productMap[status] ?? 0) + sale.quantity;
                  productMap['total'] =
                      (productMap['total'] ?? 0) + sale.quantity;
                }

                // --- TODAY'S GALLON TRANSACTIONS (DETAILED) ---
                final todayGallonTransactions = allGallons.where((g) {
                  final d = g.createdAt.toLocal();
                  return d.year == now.year &&
                      d.month == now.month &&
                      d.day == now.day;
                }).toList();

                // Create detailed gallon transaction list
                final List<String> gallonTransactionDetails = [];
                final Map<String, int> gallonSummary = {
                  'deposits': 0,
                  'purchases': 0,
                  'returns': 0,
                };

                for (final gallon in todayGallonTransactions) {
                  final customerName = gallon.customerName ?? 'مجهول';
                  final productName = gallon.productName ?? 'جالون ماء';
                  final quantity = gallon.quantity;
                  final type = gallon.transactionType ?? 'unknown';

                  // Update summary counts
                  switch (type) {
                    case 'deposit':
                      gallonSummary['deposits'] =
                          (gallonSummary['deposits'] ?? 0) + quantity;
                      gallonTransactionDetails
                          .add('$customerName: أودع $quantity $productName');
                      break;
                    case 'purchase':
                      gallonSummary['purchases'] =
                          (gallonSummary['purchases'] ?? 0) + quantity;
                      gallonTransactionDetails
                          .add('$customerName: اشترى $quantity $productName');
                      break;
                    case 'return':
                      gallonSummary['returns'] =
                          (gallonSummary['returns'] ?? 0) + quantity;
                      gallonTransactionDetails
                          .add('$customerName: أرجع $quantity $productName');
                      break;
                    case 'paid':
                      gallonTransactionDetails.add(
                          '$customerName: دفع مقابل $quantity $productName');
                      break;
                    default:
                      gallonTransactionDetails
                          .add('$customerName: $type $quantity $productName');
                  }
                }

                // --- TODAY'S PAYMENTS ---
                final todayPayments = allPayments.where((p) {
                  final paymentDateStr = p['payment_date'] as String?;
                  if (paymentDateStr == null) return false;
                  try {
                    final paymentDate = DateTime.parse(paymentDateStr);
                    return paymentDate.isAfter(today) &&
                        paymentDate
                            .isBefore(today.add(const Duration(days: 1)));
                  } catch (e) {
                    return false;
                  }
                }).toList();
                final totalCashInflow = todayPayments.fold<double>(0,
                    (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));

                // Payment type breakdown
                final partialPayments = todayPayments.where((p) {
                  final note = (p['note'] as String? ?? '').toLowerCase();
                  final sale = p['sale'] as Map<String, dynamic>?;
                  final status = sale?['payment_status']?.toLowerCase() ?? '';
                  return status == 'partial' ||
                      note.contains('جزئية') ||
                      note.contains('partial') ||
                      note.contains('دفعة من صفحة');
                }).toList();

                final depositPayments = todayPayments.where((p) {
                  final note = p['note'] as String? ?? '';
                  return note.contains('وديعة');
                }).toList();

                final partialAmount = partialPayments.fold<double>(0,
                    (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
                final depositAmount = depositPayments.fold<double>(0,
                    (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
                final paidSalesTotal =
                    totalCashInflow - partialAmount - depositAmount;

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(distributorSalesProvider);
                    ref.invalidate(distributorPaymentsProvider);
                    ref.invalidate(gallonTransactionsProvider);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.blue.shade50.withOpacity(0.3),
                          Colors.grey.shade50,
                          Colors.white,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- CASHFLOW CARD ---
                          _EqualSizeCard(
                            title: "💰 التدفق النقدي اليوم",
                            children: [
                              'إجمالي النقد المحصل: ${lbp.format(totalCashInflow)}',
                              'من مبيعات مدفوعة: ${lbp.format(paidSalesTotal)}',
                              'من دفعات ودائع: ${lbp.format(depositAmount)}',
                              'من دفعات جزئية: ${lbp.format(partialAmount)}',
                              'إجمالي المبيعات غير المدفوعة: ${lbp.format(unpaidSalesTotal)}',
                            ],
                          ),
                          const SizedBox(height: 16),

                          // --- NORMAL SALES PERFORMANCE ---
                          if (normalSalesByProduct.isNotEmpty)
                            _EqualSizeCard(
                              title: "📦 أداء المبيعات العادية",
                              children: [
                                ...normalSalesByProduct.entries.map((entry) {
                                  final product = entry.key;
                                  final counts = entry.value;
                                  final paid = counts['paid'] ?? 0;
                                  final unpaid = counts['unpaid'] ?? 0;
                                  final partial = counts['partial'] ?? 0;
                                  final total = counts['total'] ?? 0;

                                  return '${product}:\n   • مدفوع: $paid\n   • غير مدفوع: $unpaid\n   • جزئي: $partial\n   • المجموع: $total';
                                }),
                              ],
                              isProductPerformance: true,
                            ),
                          if (normalSalesByProduct.isNotEmpty)
                            const SizedBox(height: 16),

                          // --- DETAILED GALLON TRANSACTIONS ---
                          if (gallonTransactionDetails.isNotEmpty)
                            _EqualSizeCard(
                              title: "🏺 تفاصيل معاملات الجالونات",
                              children: gallonTransactionDetails,
                            ),
                          if (gallonTransactionDetails.isNotEmpty)
                            const SizedBox(height: 16),

                          // --- TODAY'S PAYMENTS LIST ---
                          _EqualSizeCard(
                            title: "📝 دفعات اليوم",
                            children: [
                              ...todayPayments.map((p) {
                                final sale = p['sale'] as Map<String, dynamic>?;
                                final customer = sale != null
                                    ? (sale['customer']
                                            as Map<String, dynamic>? ??
                                        {})
                                    : {};
                                final customerName =
                                    customer['name'] as String? ?? 'مجهول';
                                final amount =
                                    (p['amount'] as num?)?.toDouble() ?? 0;
                                final note = p['note'] as String? ?? '';
                                String type = 'مدفوعة';
                                if (note.contains('وديعة')) type = 'وديعة';
                                if (note.contains('جزئية')) type = 'جزئية';
                                return '$customerName: ${lbp.format(amount)} ($type)';
                              }),
                              if (todayPayments.isEmpty) 'لا يوجد دفعات اليوم',
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EqualSizeCard extends StatelessWidget {
  final String title;
  final List<String> children;
  final bool isProductPerformance;

  const _EqualSizeCard({
    required this.title,
    required this.children,
    this.isProductPerformance = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.white,
            blurRadius: 1,
            offset: const Offset(0, 1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Container(
        constraints: BoxConstraints(
          minHeight: isProductPerformance ? 250 : 200,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isProductPerformance
                        ? Colors.blue.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isProductPerformance
                          ? Colors.blue.shade200
                          : Colors.grey.shade200,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isProductPerformance ? Colors.blue : Colors.grey)
                                .shade200
                                .withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isProductPerformance)
                        Icon(
                          Icons.analytics_outlined,
                          size: 16,
                          color: Colors.blue.shade700,
                        ),
                      if (isProductPerformance) const SizedBox(width: 6),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isProductPerformance
                              ? Colors.blue.shade700
                              : Colors.grey.shade700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: children
                    .map((line) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                margin:
                                    const EdgeInsets.only(top: 8, right: 12),
                                decoration: BoxDecoration(
                                  color: isProductPerformance
                                      ? Colors.blue.shade400
                                      : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                    height: 1.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnpaidSalesPage extends ConsumerWidget {
  final String customerName;
  final List<DistributorSale> sales;

  const _UnpaidSalesPage({
    required this.customerName,
    required this.sales,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lbp = NumberFormat.currency(
        locale: 'en_US', symbol: 'LBP ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: Text('Unpaid: $customerName'),
        flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: _primaryGradient)),
      ),
      body: sales.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sales.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final s = sales[i];
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.inventory_2_outlined,
                          size: 22, color: Colors.orange.shade800),
                    ),
                    title: Text('${s.productName} x${s.quantity}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        )),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          'Total: ${lbp.format(s.totalAmount)}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy - hh:mm a')
                              .format(s.date.toLocal()),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          onPressed: () async {
                            final nav = Navigator.of(context);
                            final msg = ScaffoldMessenger.of(context);

                            try {
                              // Update the sale payment status to paid
                              final updatedSale = await Supabase.instance.client
                                  .from('sales')
                                  .update({
                                    'payment_status': 'paid',
                                    'amount_paid': s.totalAmount
                                  })
                                  .eq('id', s.saleId)
                                  .select();

                              if (updatedSale.isEmpty) {
                                msg.showSnackBar(const SnackBar(
                                    content: Text('No sale updated.')));
                                return;
                              }

                              // Also update related gallon transactions
                              await Supabase.instance.client
                                  .from('gallon_transactions')
                                  .update({
                                'status': 'paid',
                                'transaction_type': 'purchase'
                              }).eq('sale_id', s.saleId);
                            } on PostgrestException catch (err) {
                              msg.showSnackBar(SnackBar(
                                  content:
                                      Text('Update failed: ${err.message}')));
                              return;
                            } catch (err) {
                              msg.showSnackBar(
                                  SnackBar(content: Text('Unexpected: $err')));
                              return;
                            }

                            ref.invalidate(distributorSalesProvider);
                            msg.showSnackBar(const SnackBar(
                                content: Text('Payment recorded!')));
                            nav.pop();
                          },
                          child: const Text('تم الدفع'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          onPressed: () async {
                            final nav = Navigator.of(context);
                            final msg = ScaffoldMessenger.of(context);
                            final controller = TextEditingController();
                            final result = await showDialog<double>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('إدخال دفعة جزئية'),
                                content: TextField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'المبلغ المدفوع',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('إلغاء'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      final val =
                                          double.tryParse(controller.text);
                                      if (val == null ||
                                          val <= 0 ||
                                          val >= s.totalAmount - s.amountPaid) {
                                        msg.showSnackBar(const SnackBar(
                                            content: Text(
                                                'يرجى إدخال مبلغ صحيح أقل من المتبقي')));
                                        return;
                                      }
                                      Navigator.pop(ctx, val);
                                    },
                                    child: const Text('تأكيد'),
                                  ),
                                ],
                              ),
                            );
                            if (result == null) return;
                            final partialAmount = result;
                            try {
                              // Insert payment record
                              final now = DateTime.now();
                              final paymentDate = DateTime(now.year, now.month,
                                      now.day, now.hour, now.minute, now.second)
                                  .toUtc()
                                  .toIso8601String();
                              debugPrint(
                                  '[DistributorHome] Creating partial payment with date: $paymentDate');
                              debugPrint(
                                  '[DistributorHome] Current local time: $now');
                              debugPrint(
                                  '[DistributorHome] Payment date (local): ${DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second)}');

                              await Supabase.instance.client
                                  .from('payments')
                                  .insert({
                                'sale_id': s.saleId,
                                'amount': partialAmount,
                                'payment_date': paymentDate,
                                'note': 'دفعة جزئية من صفحة التحصيل',
                              });
                              // Update sale's amountPaid and payment_status
                              final newPaid = s.amountPaid + partialAmount;
                              final newStatus =
                                  newPaid >= s.totalAmount ? 'paid' : 'partial';
                              await Supabase.instance.client
                                  .from('sales')
                                  .update({
                                'amount_paid': newPaid,
                                'payment_status': newStatus
                              }).eq('id', s.saleId);
                            } on PostgrestException catch (err) {
                              msg.showSnackBar(SnackBar(
                                  content:
                                      Text('Update failed: ${err.message}')));
                              return;
                            } catch (err) {
                              msg.showSnackBar(
                                  SnackBar(content: Text('Unexpected: $err')));
                              return;
                            }
                            ref.invalidate(distributorSalesProvider);
                            msg.showSnackBar(const SnackBar(
                                content: Text('تم تسجيل الدفعة الجزئية!')));
                            nav.pop();
                          },
                          child: const Text('دفعة جزئية'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined,
                size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 20),
            Text('!تم تحصيل جميع المدفوعات',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      );
}
