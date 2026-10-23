import 'package:alruba_waterapp/models/gallon_transaction.dart';
import 'package:alruba_waterapp/providers/gallon_transactionprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:alruba_waterapp/providers/distributor_sales_provider.dart';
import 'package:alruba_waterapp/providers/location_provider.dart';

/// Internal event type for grouping sales and payments by day
class _DayEvent {
  final DistributorSale? sale;
  final GallonTransaction? gallonTransaction;
  final DateTime time;
  final bool isSale;
  final bool isPayment;

  _DayEvent.sale(this.sale, this.time)
      : gallonTransaction = null,
        isSale = true,
        isPayment = false;

  _DayEvent.payment(this.sale, this.time)
      : gallonTransaction = null,
        isSale = true,
        isPayment = true;

  _DayEvent.gallon(this.gallonTransaction, this.time)
      : sale = null,
        isSale = false,
        isPayment = false;
}

class DistributorSalesPage extends ConsumerStatefulWidget {
  const DistributorSalesPage({super.key});

  @override
  ConsumerState<DistributorSalesPage> createState() =>
      _DistributorSalesPageState();
}

class _DistributorSalesPageState extends ConsumerState<DistributorSalesPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchText = '';
  String? _locationFilter;

  final _lbpFormat = NumberFormat.currency(
    locale: 'ar_LB',
    symbol: 'LBP ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(distributorSalesProvider);
    final gallonsAsync = ref.watch(gallonTransactionsProvider);
    final paymentsAsync = ref.watch(distributorPaymentsProvider);
    final locationsAsync = ref.watch(locationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('مبيعاتي')),
      body: Column(
        children: [
          _buildFilterSection(context, locationsAsync),
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('خطأ: $err')),
              data: (allSales) {
                return gallonsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) =>
                      Center(child: Text('خطأ في الجالون: $err')),
                  data: (allGallonsRaw) {
                    // Deduplicate gallon transactions by remote id
                    final allGallons = {
                      for (var g in allGallonsRaw)
                        if (g.id != null) g.id: g
                    }.values.toList();

                    return paymentsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) =>
                          Center(child: Text('خطأ في الدفعات: $err')),
                      data: (allPayments) {
                        final filteredSales = _applyFilters(allSales);
                        final filteredGallons = _applyGallonFilters(allGallons);
                        final filteredPayments = allPayments.where((p) {
                          final sale = p['sale'] as Map<String, dynamic>?;
                          if (sale == null) return false;
                          if (_searchText.isNotEmpty &&
                              !(sale['customer']?['name'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(_searchText)) {
                            return false;
                          }
                          if (_locationFilter != null &&
                              !(sale['customer']?['location']?['name'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(_locationFilter!.toLowerCase())) {
                            return false;
                          }
                          if (_startDate != null && _endDate != null) {
                            final d = DateTime.parse(p['payment_date']);
                            if (d.isBefore(_startDate!) ||
                                d.isAfter(_endDate!)) {
                              return false;
                            }
                          }
                          return true;
                        }).toList();

                        if (filteredSales.isEmpty &&
                            filteredGallons.isEmpty &&
                            filteredPayments.isEmpty) {
                          return const Center(
                              child: Text('لا توجد سجلات مطابقة.'));
                        }

                        return RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(distributorSalesProvider);
                            ref.invalidate(gallonTransactionsProvider);
                            ref.invalidate(distributorPaymentsProvider);
                            ref.invalidate(locationsProvider);
                          },
                          child: _buildCombinedEventsList(
                              filteredSales, filteredGallons, filteredPayments),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<GallonTransaction> _applyGallonFilters(
      List<GallonTransaction> allGallons) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return allGallons.where((g) {
      // For deposits (no sale), include them (they're created by current user)
      // For transactions with sales, check if sale was by current user
      if (g.saleId != null) {
        // Transaction with sale - check seller
        if (g.sellerId != currentUserId) {
          return false;
        }
      }
      // For deposits (no sale), include them (they're created by current user)

      // Apply location filter to gallon transactions
      if (_locationFilter != null && _locationFilter!.trim().isNotEmpty) {
        final location = (g.customerLocation ?? '').toLowerCase().trim();
        if (!location.contains(_locationFilter!.toLowerCase().trim())) {
          return false;
        }
      }

      if (_startDate != null && _endDate != null) {
        final d = g.createdAt.toLocal();
        if (d.isBefore(_startDate!) || d.isAfter(_endDate!)) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildFilterSection(BuildContext ctx, AsyncValue<List<dynamic>> locs) {
    return Card(
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم العميل...',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) =>
                  setState(() => _searchText = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildLocationDropdown(locs)),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: const Text('نطاق التاريخ'),
                  onPressed: () => _pickDateRange(ctx),
                ),
              ],
            ),
            if (_startDate != null && _endDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${DateFormat('MMM dd, yyyy', 'ar').format(_startDate!)} — ${DateFormat('MMM dd, yyyy', 'ar').format(_endDate!)}',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationDropdown(AsyncValue<List<dynamic>> locs) {
    return locs.when(
      data: (locations) {
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
              value: null, child: Text('جميع المواقع')),
          ...locations.map((l) =>
              DropdownMenuItem<String?>(value: l.name, child: Text(l.name))),
        ];
        return DropdownButtonFormField<String?>(
          value: _locationFilter,
          items: items,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => setState(() => _locationFilter = v),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('خطأ: $e'),
    );
  }

  Future<void> _pickDateRange(BuildContext ctx) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: ctx,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)), end: now),
      locale: const Locale('ar'),
    );
    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  List<DistributorSale> _applyFilters(List<DistributorSale> all) {
    return all.where((s) {
      if (_searchText.isNotEmpty &&
          !s.customerName.toLowerCase().contains(_searchText)) return false;
      if (_locationFilter != null &&
          !s.location.toLowerCase().contains(_locationFilter!.toLowerCase()))
        return false;
      if (_startDate != null && _endDate != null) {
        final d = s.date.toLocal();
        if (d.isBefore(_startDate!) || d.isAfter(_endDate!)) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildCombinedEventsList(List<DistributorSale> sales,
      List<GallonTransaction> gallons, List<Map<String, dynamic>> payments) {
    final Map<String, List<_DayEvent>> eventsByDay = {};
    final Set<String> shownDepositSales =
        {}; // Track deposit sale IDs already shown
    // Track fully paid deposits and their payment dates
    final Set<String> fullyPaidDepositIds = {
      for (final payment in payments)
        if ((payment['sale']?['payment_status'] as String?)?.toLowerCase() ==
                'paid' &&
            (payment['sale']?['sale_type'] as String?) == 'deposit_given')
          payment['sale']?['id'] as String
    };
    final Map<String, Map<String, dynamic>> fullyPaidDepositPayments = {
      for (final payment in payments)
        if ((payment['sale']?['payment_status'] as String?)?.toLowerCase() ==
                'paid' &&
            (payment['sale']?['sale_type'] as String?) == 'deposit_given')
          (payment['sale']?['id'] as String): payment
    };

    // Create a map of sale ID to corresponding gallon transaction for merging
    final Map<String, GallonTransaction> saleToGallonMap = {
      for (final gallon in gallons)
        if (gallon.saleId != null &&
            (gallon.transactionType == 'deposit' ||
                gallon.transactionType == 'purchase'))
          gallon.saleId!: gallon
    };

    // Build a set of unique hashes for all sales
    final Set<String> saleHashes = {
      for (final sale in sales)
        sale.saleId.isNotEmpty
            ? 'id:${sale.saleId}'
            : 'fallback:${sale.customerName.toLowerCase()}|${sale.productName.toLowerCase()}|${sale.quantity}|${sale.date.toIso8601String().substring(0, 16)}'
    };

    for (final sale in sales) {
      // Skip all events for fully paid deposits (will show merged event below)
      if (fullyPaidDepositIds.contains(sale.saleId)) continue;
      final saleDate = sale.date.toLocal();
      final saleKey = DateFormat('yyyy-MM-dd').format(saleDate);

      // Check if this sale has a corresponding gallon transaction
      final correspondingGallon = saleToGallonMap[sale.saleId];

      if (sale.paymentStatus == 'deposit') {
        if (!shownDepositSales.contains(sale.saleId)) {
          eventsByDay
              .putIfAbsent(saleKey, () => [])
              .add(_DayEvent.sale(sale, saleDate));
          shownDepositSales.add(sale.saleId);
        }
      } else {
        eventsByDay
            .putIfAbsent(saleKey, () => [])
            .add(_DayEvent.sale(sale, saleDate));
      }
    }

    // Add merged event for fully paid deposits
    for (final entry in fullyPaidDepositPayments.entries) {
      final payment = entry.value;
      final sale = payment['sale'] as Map<String, dynamic>;
      final customer = sale['customer'] as Map<String, dynamic>? ?? {};
      final product = sale['product'] as Map<String, dynamic>? ?? {};
      final paymentDate = DateTime.parse(payment['payment_date']).toLocal();
      final payKey = DateFormat('yyyy-MM-dd').format(paymentDate);
      final mergedEvent = _DayEvent.payment(
        DistributorSale(
          saleId: sale['id'] as String,
          date: DateTime.parse(sale['created_at'] as String),
          paymentDate: paymentDate,
          paymentStatus: 'deposit_paid',
          quantity: (sale['quantity'] as num?)?.toInt() ?? 0,
          pricePerUnit: (sale['price_per_unit'] as num?)?.toDouble() ?? 0.0,
          totalAmount: (sale['total_amount'] as num?)?.toDouble() ?? 0.0,
          productName: product['name'] as String? ?? 'Unknown Item',
          customerName: customer['name'] as String? ?? 'Unknown',
          phone: customer['phone'] as String? ?? '',
          location: customer['location']?['name'] as String? ?? 'Unknown',
          preciseLocation: customer['precise_location'] as String?,
          amountPaid: (payment['amount'] as num?)?.toDouble() ?? 0.0,
          saleType: sale['sale_type'] as String?,
        ),
        paymentDate,
      );
      eventsByDay.putIfAbsent(payKey, () => []).add(mergedEvent);
    }

    // Add events for all partial payments
    for (final payment in payments) {
      final sale = payment['sale'] as Map<String, dynamic>?;
      if (sale == null) continue;
      final paymentStatus = sale['payment_status'] as String? ?? '';

      // Skip payments that were created at the same time as the sale (normal paid sales)
      final saleCreatedAt = DateTime.parse(sale['created_at'] as String);
      final paymentDate = DateTime.parse(payment['payment_date']).toLocal();
      final timeDifference = paymentDate.difference(saleCreatedAt).abs();

      // If payment was made within 1 minute of sale creation, skip it (it's a normal paid sale)
      if (timeDifference.inMinutes <= 1) {
        continue;
      }

      // Show payment events for partial payments made after sale creation
      final customer = sale['customer'] as Map<String, dynamic>? ?? {};
      final product = sale['product'] as Map<String, dynamic>? ?? {};
      final payKey = DateFormat('yyyy-MM-dd').format(paymentDate);
      final paymentAmount = (payment['amount'] as num?)?.toDouble() ?? 0.0;

      final partialEvent = _DayEvent.payment(
        DistributorSale(
          saleId: sale['id'] as String,
          date: DateTime.parse(sale['created_at'] as String),
          paymentDate: paymentDate,
          paymentStatus: paymentStatus,
          quantity: (sale['quantity'] as num?)?.toInt() ?? 0,
          pricePerUnit: (sale['price_per_unit'] as num?)?.toDouble() ?? 0.0,
          totalAmount: (sale['total_amount'] as num?)?.toDouble() ?? 0.0,
          productName: product['name'] as String? ?? 'Unknown Item',
          customerName: customer['name'] as String? ?? 'Unknown',
          phone: customer['phone'] as String? ?? '',
          location: customer['location']?['name'] as String? ?? 'Unknown',
          preciseLocation: customer['precise_location'] as String?,
          amountPaid: paymentAmount,
          saleType: sale['sale_type'] as String?,
        ),
        paymentDate,
      );
      eventsByDay.putIfAbsent(payKey, () => []).add(partialEvent);
    }

    // Show all gallon transactions including deposits (trust gallons)
    for (final gallon in gallons) {
      // Skip gallon transactions that are linked to normal sales (refillable products)
      // These are already shown as part of the sale event
      if (gallon.saleId != null && gallon.saleId!.isNotEmpty) {
        continue;
      }

      final gallonDate = gallon.createdAt;
      final gallonKey = DateFormat('yyyy-MM-dd').format(gallonDate);
      eventsByDay
          .putIfAbsent(gallonKey, () => [])
          .add(_DayEvent.gallon(gallon, gallon.createdAt.toLocal()));
    }

    final days = eventsByDay.keys.toList()..sort((b, a) => a.compareTo(b));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: days.length,
      itemBuilder: (ctx, idx) {
        final day = days[idx];
        final events = eventsByDay[day]!
          ..sort((b, a) => a.time.compareTo(b.time));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                DateFormat('MMM dd, yyyy', 'ar').format(DateTime.parse(day)),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              children: events.map((e) {
                if (e.isSale && !e.isPayment) {
                  final s = e.sale!;
                  IconData icon;
                  Color color;
                  String subtitleText;

                  // Special handling for deposit sales
                  if ((s.saleType == 'deposit_given' ||
                          s.saleType == 'deposit') &&
                      (s.paymentStatus == 'paid' ||
                          s.paymentStatus == 'deposit_paid')) {
                    icon = Icons.account_balance_wallet;
                    color = Colors.green;
                    subtitleText =
                        '${s.customerName} اشترى ${s.quantity} جالون كوديعة (مدفوع)';
                  } else if ((s.saleType == 'deposit_given' ||
                      s.saleType == 'deposit')) {
                    icon = Icons.account_balance_wallet;
                    color = Colors.orange;
                    subtitleText =
                        '${s.customerName} اشترى ${s.quantity} جالون كوديعة (غير مدفوع)';
                  } else if (s.paymentStatus == 'paid' &&
                      s.saleType == 'deposit_paid') {
                    // Sales paid from deposit
                    icon = Icons.local_drink;
                    color = Colors.green;
                    subtitleText =
                        '${s.customerName} اشترى ${s.quantity} ${s.productName} (مدفوع من الوديعة)';
                  } else if (s.paymentStatus == 'paid') {
                    // Normal paid sales
                    icon = Icons.check;
                    color = Colors.green;
                    subtitleText =
                        '${s.productName} • الكمية: ${s.quantity} • مدفوع';
                  } else if (s.paymentStatus == 'partial' ||
                      (s.amountPaid > 0 && s.amountPaid < s.totalAmount)) {
                    icon = Icons.account_balance_wallet;
                    color = Colors.orange;
                    subtitleText =
                        '${s.productName} • الكمية: ${s.quantity} • دفعة جزئية (${s.amountPaid.toStringAsFixed(0)} من ${s.totalAmount.toStringAsFixed(0)})';
                  } else {
                    icon = Icons.hourglass_empty;
                    color = Colors.orange;
                    subtitleText =
                        '${s.productName} • الكمية: ${s.quantity} • غير مدفوع';
                  }

                  return ListTile(
                    leading: CircleAvatar(
                        backgroundColor: color,
                        child: Icon(icon, color: Colors.white)),
                    title: Text(s.customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(subtitleText),
                    trailing: Text(_lbpFormat.format(s.totalAmount)),
                    onTap: () => _showSaleDetailsDialog(s),
                  );
                } else if (e.isSale && e.isPayment) {
                  final s = e.sale!;
                  // Special merged event for fully paid deposit
                  if (s.paymentStatus == 'deposit_paid') {
                    return ListTile(
                      leading:
                          const Icon(Icons.local_drink, color: Colors.green),
                      title: Text(
                          'تم دفع وديعة بقيمة ${_lbpFormat.format(s.totalAmount)} مقابل ${s.quantity} جالون كوديعة'),
                      subtitle: Text('${s.customerName} • ${s.productName}'),
                      trailing:
                          Text(DateFormat('HH:mm').format(e.time.toLocal())),
                    );
                  }

                  // Get the individual payment amount from the payment record
                  final paymentAmount =
                      s.amountPaid; // This is now the individual payment amount
                  final totalSaleAmount = s.totalAmount;

                  // Check if this payment completes the sale
                  // We need to check if the cumulative amount up to this payment equals or exceeds the total
                  final saleId = s.saleId;
                  final paymentDate = s.paymentDate;

                  // Find all payments for this sale up to this payment date
                  double cumulativeAmount = 0.0;
                  for (final payment in payments) {
                    final paymentSaleId = payment['sale']?['id'] as String?;
                    final paymentDateStr = payment['payment_date'] as String?;
                    if (paymentSaleId == saleId && paymentDateStr != null) {
                      final thisPaymentDate =
                          DateTime.parse(paymentDateStr).toLocal();
                      if (thisPaymentDate.isBefore(paymentDate!) ||
                          thisPaymentDate.isAtSameMomentAs(paymentDate!)) {
                        cumulativeAmount +=
                            (payment['amount'] as num?)?.toDouble() ?? 0.0;
                      }
                    }
                  }

                  final isFinalPayment = cumulativeAmount >= totalSaleAmount;
                  IconData icon = Icons.attach_money;
                  Color color = isFinalPayment ? Colors.green : Colors.orange;
                  final paymentLabel =
                      isFinalPayment ? 'دفع كامل' : 'دفعة جزئية';
                  final individualPaymentAmount =
                      _lbpFormat.format(paymentAmount);
                  final totalAmount = _lbpFormat.format(totalSaleAmount);

                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text('$paymentLabel من قبل ${s.customerName}'),
                    subtitle: Text(
                        'تم الدفع $individualPaymentAmount من $totalAmount بواسطة المستخدم'),
                    trailing:
                        Text(DateFormat('HH:mm').format(e.time.toLocal())),
                  );
                } else {
                  final g = e.gallonTransaction!;
                  IconData icon;
                  String subtitleText;
                  Color iconColor;

                  if (g.transactionType == 'return') {
                    icon = Icons.swap_horiz;
                    iconColor = Colors.green;
                    subtitleText =
                        '${g.customerName} أرجع ${g.quantity} جالون كوديعة';
                  } else if (g.transactionType == 'purchase') {
                    icon = Icons.water_drop;
                    iconColor = Colors.blue;
                    subtitleText =
                        '${g.customerName} أخذ ${g.quantity} جالون كوديعة';
                  } else if (g.transactionType == 'deposit') {
                    icon = Icons.account_balance_wallet;
                    iconColor = Colors.purple;
                    subtitleText =
                        '${g.customerName} أودع ${g.quantity} جالون كوديعة';
                  } else {
                    icon = Icons.local_drink;
                    iconColor = Colors.grey;
                    subtitleText = '${g.transactionType} ${g.quantity} جالون';
                  }

                  return ListTile(
                    leading: Icon(icon, color: iconColor),
                    title: const Text('عملية جالون'),
                    subtitle: Text(subtitleText),
                    trailing:
                        Text(DateFormat('HH:mm').format(e.time.toLocal())),
                  );
                }
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showSaleDetailsDialog(DistributorSale sale) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('البيع لـ ${sale.customerName}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(sale.date.toLocal())}'),
                const SizedBox(height: 4),
                Text('المنتج: ${sale.productName}'),
                const SizedBox(height: 4),
                Text('الكمية: ${sale.quantity}'),
                const SizedBox(height: 4),
                Text('السعر للوحدة: ${_lbpFormat.format(sale.pricePerUnit)}'),
                const SizedBox(height: 4),
                Text('الإجمالي: ${_lbpFormat.format(sale.totalAmount)}'),
                const SizedBox(height: 4),
                Text('الحالة: ${sale.paymentStatus.toUpperCase()}'),
                const SizedBox(height: 4),
                Text(
                    'تم الدفع في: ${sale.paymentDate != null ? DateFormat('yyyy-MM-dd HH:mm').format(sale.paymentDate!) : '—'}'),
                const SizedBox(height: 4),
                Text('الموقع: ${sale.location}'),
                const SizedBox(height: 12),
                if (sale.phone.isNotEmpty)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.call),
                    label: const Text('اتصل بالعميل'),
                    onPressed: () => _openDialer(sale.phone),
                  ),
                if (sale.preciseLocation != null)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text('افتح في الخرائط'),
                    onPressed: () => _openInMaps(sale.preciseLocation!),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))
          ],
        );
      },
    );
  }

  Future<void> _openDialer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openInMaps(String loc) async {
    final googleUri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$loc');
    if (await canLaunchUrl(googleUri)) await launchUrl(googleUri);
  }
}
