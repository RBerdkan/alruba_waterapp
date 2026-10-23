// File: manager_cashflow_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:alruba_waterapp/providers/manager_slaes_provider.dart';
import 'package:alruba_waterapp/providers/payments_provider.dart';
import 'package:alruba_waterapp/providers/gallon_transactionprovider.dart';
import 'package:alruba_waterapp/providers/role_provider.dart';
import 'package:alruba_waterapp/providers/location_provider.dart';
import 'package:alruba_waterapp/models/location.dart';
import 'package:alruba_waterapp/models/payment.dart';
import 'package:alruba_waterapp/services/supabase_service.dart';
import 'package:collection/collection.dart';

/// Provider for all payments (not just today's)
final allPaymentsProvider =
    FutureProvider.autoDispose<List<Payment>>((ref) async {
  final rows = await SupabaseService.client
      .from('payments')
      .select()
      .order('payment_date', ascending: false);

  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map((m) => Payment.fromMap(m))
      .toList();
});

/// Provider for payments with sales data for proper filtering
final paymentsWithSalesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await SupabaseService.client.from('payments').select(r'''
        id,
        sale_id,
        amount,
        payment_date,
        note,
        sale:sales(
          id,
          sold_by,
          payment_status,
          sale_type,
          customer:customers!sales_customer_id_fkey(name),
          seller_profile:profiles!sales_sold_by_fkey(first_name, last_name, role)
        )
      ''').order('payment_date', ascending: false);

  return (response as List).cast<Map<String, dynamic>>();
});

/// Provider for all users from profiles table
final allUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final response = await SupabaseService.client
        .from('profiles')
        .select('user_id, first_name, last_name, role')
        .order('first_name', ascending: true);

    // Debug logging
    print('All users loaded: ${response.length}');
    for (final user in response) {
      print(
          'User: ${user['first_name']} ${user['last_name']} - Role: ${user['role']}');
    }

    return response;
  } catch (e) {
    throw Exception('Failed to load users: ${e.toString()}');
  }
});

/// Page showing today's comprehensive business metrics for all sales and gallon transactions (manager view)
class ManagerCashflowPage extends ConsumerStatefulWidget {
  const ManagerCashflowPage({super.key});

  @override
  ConsumerState<ManagerCashflowPage> createState() =>
      _ManagerCashflowPageState();
}

class _ManagerCashflowPageState extends ConsumerState<ManagerCashflowPage> {
  String? selectedUser; // user full name or null for all
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(managerSalesProvider);
    final paymentsAsync = ref.watch(paymentsWithSalesProvider);
    final gallonsAsync = ref.watch(gallonTransactionsProvider);
    final usersAsync = ref.watch(allUsersProvider);
    final lbp = NumberFormat.currency(
        locale: 'en_US', symbol: 'LBP ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('التدفق النقدي'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading users: $e')),
        data: (allUsers) {
          final currentUser = SupabaseService.client.auth.currentUser;
          String? currentUserRole;
          for (final user in allUsers) {
            if (user['user_id'] == currentUser?.id) {
              currentUserRole = user['role'] as String?;
              break;
            }
          }
          // Filter users for dropdown
          List<Map<String, dynamic>> filteredUsers;
          if (currentUserRole == 'owner') {
            filteredUsers = allUsers;
          } else if (currentUserRole == 'manager') {
            filteredUsers = allUsers.where((user) {
              final role = user['role'] as String? ?? '';
              return role == 'manager' || role == 'distributor';
            }).toList();
          } else {
            filteredUsers = allUsers
                .where((user) => user['user_id'] == currentUser?.id)
                .toList();
          }
          // Dropdown items
          final userItems = <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
                value: null, child: Text('جميع المستخدمين')),
            ...filteredUsers.map((user) {
              final firstName = user['first_name'] as String? ?? '';
              final lastName = user['last_name'] as String? ?? '';
              final fullName = '$firstName $lastName'.trim();
              return DropdownMenuItem<String?>(
                  value: fullName, child: Text(fullName));
            })
          ];

          return salesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (allSales) {
              return paymentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading payments: $e')),
                data: (allPaymentsWithSales) {
                  return gallonsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text('Error loading gallons: $e')),
                    data: (allGallons) {
                      // Filter by user and date
                      List<ManagerSale> filteredSales = allSales.where((s) {
                        final d = s.date.toLocal();
                        final isSameDate = d.year == selectedDate.year &&
                            d.month == selectedDate.month &&
                            d.day == selectedDate.day;
                        final matchesUser = selectedUser == null ||
                            s.sellerName == selectedUser;
                        return isSameDate && matchesUser;
                      }).toList();
                      List<dynamic> filteredGallons = allGallons.where((g) {
                        final d = g.createdAt.toLocal();
                        final isSameDate = d.year == selectedDate.year &&
                            d.month == selectedDate.month &&
                            d.day == selectedDate.day;
                        final matchesUser = selectedUser == null ||
                            g.sellerName == selectedUser;
                        return isSameDate && matchesUser;
                      }).toList();
                      List<Map<String, dynamic>> filteredPayments =
                          allPaymentsWithSales.where((p) {
                        final paymentDateStr = p['payment_date'] as String?;
                        if (paymentDateStr == null) return false;
                        final paymentDate =
                            DateTime.parse(paymentDateStr).toLocal();
                        final isSameDate =
                            paymentDate.year == selectedDate.year &&
                                paymentDate.month == selectedDate.month &&
                                paymentDate.day == selectedDate.day;
                        final sale = p['sale'] as Map<String, dynamic>?;
                        final sellerProfile =
                            sale?['seller_profile'] as Map<String, dynamic>?;
                        final sellerName = sellerProfile != null
                            ? '${sellerProfile['first_name'] ?? ''} ${sellerProfile['last_name'] ?? ''}'
                                .trim()
                            : null;
                        final matchesUser =
                            selectedUser == null || sellerName == selectedUser;
                        return isSameDate && matchesUser;
                      }).toList();

                      // After getting filteredSales, filteredPayments, filteredGallons:
                      final allowedRoles = currentUserRole == 'owner'
                          ? ['owner', 'manager', 'distributor']
                          : ['manager', 'distributor'];

                      filteredSales = filteredSales
                          .where((s) => allowedRoles
                              .contains(s.sellerRole?.toLowerCase() ?? ''))
                          .toList();

                      filteredPayments = filteredPayments.where((p) {
                        final sale = p['sale'] as Map<String, dynamic>?;
                        // Try to get the role from the joined seller_profile
                        String role =
                            sale?['seller_profile']?['role']?.toLowerCase() ??
                                '';
                        if (role.isEmpty) {
                          // Fallback: look up by sold_by
                          final soldBy = sale?['sold_by'] as String?;
                          final user = allUsers
                              .firstWhereOrNull((u) => u['user_id'] == soldBy);
                          role = user?['role']?.toLowerCase() ?? '';
                        }
                        final keep = allowedRoles.contains(role);
                        if (!keep) {
                          print(
                              '[PAYMENT FILTERED OUT] id=[36m${p['id']}[0m, sellerRole=$role, allowedRoles=$allowedRoles');
                        }
                        return keep;
                      }).toList();

                      // --- DEBUG: Print classification for each payment ---
                      for (final p in filteredPayments) {
                        final note = (p['note'] as String? ?? '').toLowerCase();
                        final sale = p['sale'] as Map<String, dynamic>?;
                        final status =
                            sale?['payment_status']?.toLowerCase() ?? '';
                        final sellerProfile =
                            sale?['seller_profile'] as Map<String, dynamic>?;
                        final sellerRole =
                            sellerProfile?['role']?.toLowerCase() ?? '';
                        final amount = (p['amount'] as num?)?.toDouble() ?? 0;
                        final paymentId = p['id'] ?? 'no-id';
                        String classification;
                        if (note.contains('وديعة')) {
                          classification = 'deposit';
                        } else if (status == 'partial' ||
                            note.contains('جزئية') ||
                            note.contains('partial') ||
                            note.contains('دفعة من صفحة')) {
                          classification = 'partial';
                        } else {
                          classification = 'paid';
                        }
                        print(
                            '[PAYMENT CLASSIFY] id=$paymentId, amount=$amount, note="$note", status="$status", sellerRole="$sellerRole" => $classification');
                      }

                      filteredGallons = filteredGallons.where((g) {
                        // Look up the seller's role using sellerId and allUsers
                        final sellerId = g.sellerId;
                        final seller = allUsers
                            .firstWhereOrNull((u) => u['user_id'] == sellerId);
                        final role = seller?['role']?.toLowerCase() ?? '';
                        return allowedRoles.contains(role);
                      }).toList();

                      // --- CASHFLOW (MATCH DISTRIBUTOR PAGE LOGIC) ---
                      final totalCashInflow = filteredPayments.fold<double>(
                          0,
                          (sum, p) =>
                              sum + ((p['amount'] as num?)?.toDouble() ?? 0));

                      final partialPayments = filteredPayments.where((p) {
                        final note = (p['note'] as String? ?? '').toLowerCase();
                        final sale = p['sale'] as Map<String, dynamic>?;
                        final status =
                            sale?['payment_status']?.toLowerCase() ?? '';
                        return status == 'partial' ||
                            note.contains('جزئية') ||
                            note.contains('partial') ||
                            note.contains('دفعة من صفحة');
                      }).toList();

                      final depositPayments = filteredPayments.where((p) {
                        final note = p['note'] as String? ?? '';
                        return note.contains('وديعة');
                      }).toList();

                      final partialAmount = partialPayments.fold<double>(
                          0,
                          (sum, p) =>
                              sum + ((p['amount'] as num?)?.toDouble() ?? 0));
                      final depositAmount = depositPayments.fold<double>(
                          0,
                          (sum, p) =>
                              sum + ((p['amount'] as num?)?.toDouble() ?? 0));
                      final paidSalesTotal =
                          totalCashInflow - partialAmount - depositAmount;

                      // --- PRODUCT PERFORMANCE (NORMAL SALES ONLY) ---
                      final todayNormalSales = filteredSales
                          .where((s) => s.saleType?.toLowerCase() == 'normal')
                          .toList();
                      final Map<String, Map<String, int>> normalSalesByProduct =
                          {};
                      for (final sale in todayNormalSales) {
                        final product = sale.productName ?? 'غير محدد';
                        final status = sale.amountPaid >= sale.totalAmount &&
                                sale.totalAmount > 0
                            ? 'paid'
                            : sale.amountPaid > 0 &&
                                    sale.amountPaid < sale.totalAmount
                                ? 'partial'
                                : 'unpaid';
                        normalSalesByProduct.putIfAbsent(
                            product,
                            () => {
                                  'paid': 0,
                                  'unpaid': 0,
                                  'partial': 0,
                                  'total': 0
                                });
                        final productMap = normalSalesByProduct[product]!;
                        productMap[status] =
                            (productMap[status] ?? 0) + sale.quantity;
                        productMap['total'] =
                            (productMap['total'] ?? 0) + sale.quantity;
                      }

                      // --- GALLON TRANSACTIONS DETAILS ---
                      final List<String> gallonTransactionDetails = [];
                      for (final gallon in filteredGallons) {
                        final customerName = gallon.customerName ?? 'مجهول';
                        final productName = gallon.productName ?? 'جالون ماء';
                        final quantity = gallon.quantity;
                        final type = gallon.transactionType ?? 'unknown';
                        switch (type) {
                          case 'deposit':
                            gallonTransactionDetails.add(
                                '$customerName: أودع $quantity $productName');
                            break;
                          case 'purchase':
                            gallonTransactionDetails.add(
                                '$customerName: اشترى $quantity $productName');
                            break;
                          case 'return':
                            gallonTransactionDetails.add(
                                '$customerName: أرجع $quantity $productName');
                            break;
                          case 'paid':
                            gallonTransactionDetails.add(
                                '$customerName: دفع مقابل $quantity $productName');
                            break;
                          default:
                            gallonTransactionDetails.add(
                                '$customerName: $type $quantity $productName');
                        }
                      }

                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(managerSalesProvider);
                          ref.invalidate(paymentsWithSalesProvider);
                          ref.invalidate(gallonTransactionsProvider);
                          ref.invalidate(allUsersProvider);
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
                                // --- FILTERS ---
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String?>(
                                        value: selectedUser,
                                        decoration: const InputDecoration(
                                          labelText: 'المستخدم',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: userItems,
                                        onChanged: (value) => setState(
                                            () => selectedUser = value),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    InkWell(
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: selectedDate,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now(),
                                        );
                                        if (date != null) {
                                          setState(() => selectedDate = date);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          border:
                                              Border.all(color: Colors.grey),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.calendar_today,
                                                size: 18),
                                            const SizedBox(width: 8),
                                            Text(
                                                'التاريخ: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // --- CASHFLOW CARD ---
                                _EqualSizeCard(
                                  title: "💰 التدفق النقدي اليوم",
                                  children: [
                                    'إجمالي النقد المحصل: ${lbp.format(totalCashInflow)}',
                                    'من مبيعات مدفوعة: ${lbp.format(paidSalesTotal)}',
                                    'من دفعات ودائع: ${lbp.format(depositAmount)}',
                                    'من دفعات جزئية: ${lbp.format(partialAmount)}',
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // --- PRODUCT PERFORMANCE ---
                                if (normalSalesByProduct.isNotEmpty)
                                  _EqualSizeCard(
                                    title: "📦 أداء المبيعات العادية",
                                    children: [
                                      ...normalSalesByProduct.entries
                                          .map((entry) {
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
                                // --- GALLON TRANSACTIONS DETAILS ---
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
                                    ...filteredPayments.map((p) {
                                      final sale =
                                          p['sale'] as Map<String, dynamic>?;
                                      final customer = sale != null
                                          ? (sale['customer']
                                                  as Map<String, dynamic>? ??
                                              {})
                                          : {};
                                      final customerName =
                                          customer['name'] as String? ??
                                              'مجهول';
                                      final amount =
                                          (p['amount'] as num?)?.toDouble() ??
                                              0;
                                      final note = p['note'] as String? ?? '';
                                      String type = 'مدفوعة';
                                      if (note.contains('وديعة'))
                                        type = 'وديعة';
                                      if (note.contains('جزئية'))
                                        type = 'جزئية';
                                      return '$customerName: ${lbp.format(amount)} ($type)';
                                    }),
                                    if (filteredPayments.isEmpty)
                                      'لا يوجد دفعات اليوم',
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
        },
      ),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Icon(Icons.circle, size: 8, color: Colors.blue.shade300),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
