import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// لوحة تحكم المالك - تعرض الأداء المالي الشهري واليومي
/// تمت ترجمة الواجهة بالكامل للغة العربية مع دعم التخطيط من اليمين لليسار
class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});

  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NumberFormat _currency =
      NumberFormat.currency(locale: 'ar_LB', symbol: 'ل.ل ', decimalDigits: 0);

  /// حوامل البيانات الخام -----------------------------------------------------
  List<Map<String, dynamic>> _allSales = [];
  List<Map<String, dynamic>> _allPayments = [];
  List<Map<String, dynamic>> _allGallons = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = true;
  Map<String, dynamic> _monthlyData = {};

  // ──────────────────────────────────────────────────────────────────────────
  // دورة الحياة
  // ──────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // جلب البيانات
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _fetchAllSales(),
        _fetchAllPayments(),
        _fetchAllGallons(),
        _fetchExpenses(),
      ]);
      _allSales = results[0];
      print('[DEBUG] Sales fetched: \\${_allSales.length}');
      _allPayments = results[1];
      print('[DEBUG] Payments fetched: \\${_allPayments.length}');
      _allGallons = results[2];
      print('[DEBUG] Gallons fetched: \\${_allGallons.length}');
      _expenses = results[3];
      print('[DEBUG] Expenses fetched: \\${_expenses.length}');
      _aggregateMonthly();
    } catch (e) {
      print('[DEBUG][ERROR] Data fetch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في تحميل البيانات: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllSales() async {
    final raw = await _supabase.from('sales').select(r'''
      id, created_at, payment_date, quantity, price_per_unit, total_amount, payment_status, sale_type,
      customer:customers!sales_customer_id_fkey(name, phone),
      product:products!sales_product_id_fkey(name, production_cost),
      location:locations!sales_location_id_fkey(name),
      sold_by,
      seller:profiles!sold_by (first_name, last_name)
    ''').order('payment_date', ascending: false);
    return (raw as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _fetchAllPayments() async {
    final raw = await _supabase.from('payments').select(r'''
      id, sale_id, amount, payment_date, note,
      sale:sales(
        id, payment_status, sale_type, customer:customers!sales_customer_id_fkey(name), 
        seller:profiles!sold_by (first_name, last_name)
      )
    ''').order('payment_date', ascending: false);
    return (raw as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _fetchAllGallons() async {
    try {
      final raw = await _supabase.from('gallon_transactions').select(r'''
        id, sale_id, product_id, created_at, amount, transaction_type, status, quantity,
        customer:customers!fk_gallon_customer(
          name,
          location_id,
          location:locations(name)
        ),
        product:products!gallon_transactions_product_id_fkey(name, production_cost),
        seller:profiles!gallon_transactions_seller_id_fkey(first_name, last_name)
      ''').order('created_at', ascending: false);
      print(
          '[DEBUG] Gallons query (full join) returned: \\${(raw as List).length}');
      return (raw as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('[DEBUG][WARNING] Gallons full join failed: $e');
      // Fallback to simpler query
      final raw = await _supabase.from('gallon_transactions').select(r'''
        id, sale_id, created_at, amount, transaction_type, status, quantity,
        customer:customers!fk_gallon_customer(name),
        product:products!gallon_transactions_product_id_fkey(name, production_cost),
        seller:profiles!gallon_transactions_seller_id_fkey(first_name, last_name)
      ''').order('created_at', ascending: false);
      print(
          '[DEBUG] Gallons query (fallback) returned: \\${(raw as List).length}');
      return (raw as List).cast<Map<String, dynamic>>();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchExpenses() async {
    final raw = await _supabase
        .from('expenses')
        .select('date, amount, description')
        .order('date', ascending: false);
    return (raw as List).cast<Map<String, dynamic>>();
  }

  void _aggregateMonthly() {
    // Group sales, payments, gallons, expenses by month and day
    final Map<String, dynamic> monthly = {};
    for (final sale in _allSales) {
      // Always group sales by their creation date
      final createdAtStr = sale['created_at'];
      if (createdAtStr == null) continue;
      final createdDt = DateTime.parse(createdAtStr).toLocal();
      final monthKey =
          '${createdDt.year}-${createdDt.month.toString().padLeft(2, '0')}';
      final dayKey = DateFormat('yyyy-MM-dd').format(createdDt);
      monthly.putIfAbsent(
          monthKey,
          () => {
                'sales': [],
                'payments': [],
                'gallons': [],
                'expenses': [],
                'days': {}
              });
      monthly[monthKey]['sales'].add(sale);
      monthly[monthKey]['days'].putIfAbsent(dayKey,
          () => {'sales': [], 'payments': [], 'gallons': [], 'expenses': []});
      monthly[monthKey]['days'][dayKey]['sales'].add(sale);
    }
    for (final payment in _allPayments) {
      final dateStr = payment['payment_date'];
      if (dateStr == null) continue;
      final dt = DateTime.parse(dateStr).toLocal();
      final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final dayKey = DateFormat('yyyy-MM-dd').format(dt);
      monthly.putIfAbsent(
          monthKey,
          () => {
                'sales': [],
                'payments': [],
                'gallons': [],
                'expenses': [],
                'days': {}
              });
      monthly[monthKey]['payments'].add(payment);
      monthly[monthKey]['days'].putIfAbsent(dayKey,
          () => {'sales': [], 'payments': [], 'gallons': [], 'expenses': []});
      monthly[monthKey]['days'][dayKey]['payments'].add(payment);
    }
    for (final gallon in _allGallons) {
      final dateStr = gallon['created_at'];
      if (dateStr == null) continue;
      final dt = DateTime.parse(dateStr).toLocal();
      final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final dayKey = DateFormat('yyyy-MM-dd').format(dt);
      monthly.putIfAbsent(
          monthKey,
          () => {
                'sales': [],
                'payments': [],
                'gallons': [],
                'expenses': [],
                'days': {}
              });
      monthly[monthKey]['gallons'].add(gallon);
      monthly[monthKey]['days'].putIfAbsent(dayKey,
          () => {'sales': [], 'payments': [], 'gallons': [], 'expenses': []});
      monthly[monthKey]['days'][dayKey]['gallons'].add(gallon);
    }
    for (final exp in _expenses) {
      final dateStr = exp['date'];
      if (dateStr == null) continue;
      final dt = DateTime.parse(dateStr).toLocal();
      final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final dayKey = DateFormat('yyyy-MM-dd').format(dt);
      monthly.putIfAbsent(
          monthKey,
          () => {
                'sales': [],
                'payments': [],
                'gallons': [],
                'expenses': [],
                'days': {}
              });
      monthly[monthKey]['expenses'].add(exp);
      monthly[monthKey]['days'].putIfAbsent(dayKey,
          () => {'sales': [], 'payments': [], 'gallons': [], 'expenses': []});
      monthly[monthKey]['days'][dayKey]['expenses'].add(exp);
    }
    setState(() => _monthlyData = monthly);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // واجهة المستخدم
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المالك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _monthlyData.isEmpty
              ? const Center(child: Text('لا توجد بيانات للعرض'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ..._monthlyData.entries.map((entry) {
                      final monthKey = entry.key;
                      final data = entry.value;
                      final monthDt = DateTime.parse('$monthKey-01');
                      final monthTitle =
                          DateFormat('MMMM yyyy', 'ar').format(monthDt);
                      // Aggregation for this month
                      final products = <String, Map<String, dynamic>>{};
                      double totalCollected = 0;
                      double productionCost = 0;
                      double expenses = 0;
                      double profit = 0;
                      final gallonSummary = <String, int>{
                        'deposit': 0,
                        'purchase': 0,
                        'return': 0
                      };
                      for (final sale in data['sales']) {
                        final product = sale['product']?['name'] ?? 'غير معروف';
                        final qty =
                            (sale['quantity'] as num?)?.toDouble() ?? 0.0;
                        final price =
                            (sale['price_per_unit'] as num?)?.toDouble() ?? 0.0;
                        final cost =
                            (sale['product']?['production_cost'] as num?)
                                    ?.toDouble() ??
                                0.0;
                        products.putIfAbsent(
                            product, () => {'quantity': 0.0, 'total': 0.0});
                        products[product]!['quantity'] += qty;
                        products[product]!['total'] += qty * price;
                        productionCost += qty * cost;
                      }
                      for (final p in data['payments']) {
                        totalCollected +=
                            (p['amount'] as num?)?.toDouble() ?? 0.0;
                      }
                      for (final g in data['gallons']) {
                        final type = g['transaction_type'] ?? 'unknown';
                        final qty = (g['quantity'] as num?)?.toInt() ?? 0;
                        if (gallonSummary.containsKey(type)) {
                          gallonSummary[type] =
                              (gallonSummary[type] ?? 0) + qty;
                        }
                      }
                      for (final e in data['expenses']) {
                        expenses += (e['amount'] as num?)?.toDouble() ?? 0.0;
                      }
                      profit = totalCollected - productionCost - expenses;
                      final List<MapEntry<String, dynamic>> sortedDayEntries =
                          (data['days'] as Map)
                              .entries
                              .map((e) => MapEntry(e.key.toString(), e.value))
                              .toList()
                            ..sort((a, b) => b.key.compareTo(a.key));
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ExpansionTile(
                          title: Text(monthTitle,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('المنتجات المباعة:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  ...products.entries.map((e) => Text(
                                      '${e.key}: ${e.value['quantity']} (${_currency.format(e.value['total'])})')),
                                  const SizedBox(height: 8),
                                  const Text('الجالونات:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text('إيداع: ${gallonSummary['deposit']}'),
                                  Text('شراء: ${gallonSummary['purchase']}'),
                                  Text('إرجاع: ${gallonSummary['return']}'),
                                  const SizedBox(height: 8),
                                  Text(
                                      'إجمالي المبلغ المحصل: ${_currency.format(totalCollected)}'),
                                  Text(
                                      'تكلفة الإنتاج: ${_currency.format(productionCost)}'),
                                  Text(
                                      'المصروفات: ${_currency.format(expenses)}'),
                                  Text('الربح: ${_currency.format(profit)}'),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.download),
                                    label: const Text('تصدير الشهر'),
                                    onPressed: () => _exportPeriodExcel(
                                        'month', data, 'month_$monthKey'),
                                  ),
                                ],
                              ),
                            ),
                            // Daily breakdown
                            // --- FIX: Sort days in descending order (most recent first) ---
                            ...sortedDayEntries.map<Widget>(
                                (MapEntry<String, dynamic> dayEntry) {
                              final dayKey = dayEntry.key;
                              final dayData = dayEntry.value;
                              final dayDt = DateTime.parse(dayKey);
                              final dayTitle =
                                  DateFormat('EEE, MMM d', 'ar').format(dayDt);
                              // Aggregation for this day
                              final dayProducts =
                                  <String, Map<String, dynamic>>{};
                              double dayCollected = 0;
                              // --- FIX: Always include production cost for all sales created on this day ---
                              double dayProductionCost = 0;
                              double dayExpenses = 0;
                              double dayProfit = 0;
                              final dayGallonSummary = <String, int>{
                                'deposit': 0,
                                'purchase': 0,
                                'return': 0
                              };
                              for (final sale in dayData['sales']) {
                                final product =
                                    sale['product']?['name'] ?? 'غير معروف';
                                final qty =
                                    (sale['quantity'] as num?)?.toDouble() ??
                                        0.0;
                                final price = (sale['price_per_unit'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final cost = (sale['product']
                                            ?['production_cost'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                dayProducts.putIfAbsent(product,
                                    () => {'quantity': 0.0, 'total': 0.0});
                                dayProducts[product]!['quantity'] += qty;
                                dayProducts[product]!['total'] += qty * price;
                                dayProductionCost +=
                                    qty * cost; // Always add cost
                              }
                              for (final p in dayData['payments']) {
                                dayCollected +=
                                    (p['amount'] as num?)?.toDouble() ?? 0.0;
                              }
                              for (final g in dayData['gallons']) {
                                final type = g['transaction_type'] ?? 'unknown';
                                final qty =
                                    (g['quantity'] as num?)?.toInt() ?? 0;
                                if (dayGallonSummary.containsKey(type)) {
                                  dayGallonSummary[type] =
                                      (dayGallonSummary[type] ?? 0) + qty;
                                }
                              }
                              for (final e in dayData['expenses']) {
                                dayExpenses +=
                                    (e['amount'] as num?)?.toDouble() ?? 0.0;
                              }
                              dayProfit = dayCollected - dayProductionCost;
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: ExpansionTile(
                                  title: Text(dayTitle,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('المنتجات المباعة:',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          ...dayProducts.entries.map((e) => Text(
                                              '${e.key}: ${e.value['quantity']} (${_currency.format(e.value['total'])})')),
                                          const SizedBox(height: 8),
                                          const Text('الجالونات:',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          Text(
                                              'إيداع: ${dayGallonSummary['deposit']}'),
                                          Text(
                                              'شراء: ${dayGallonSummary['purchase']}'),
                                          Text(
                                              'إرجاع: ${dayGallonSummary['return']}'),
                                          const SizedBox(height: 8),
                                          Text(
                                              'إجمالي المبلغ المحصل: ${_currency.format(dayCollected)}'),
                                          Text(
                                              'تكلفة الإنتاج: ${_currency.format(dayProductionCost)}'),
                                          Text(
                                              'الربح: ${_currency.format(dayProfit)}'),
                                          const SizedBox(height: 8),
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.download),
                                            label: const Text('تصدير اليوم'),
                                            onPressed: () => _exportPeriodExcel(
                                                'day', dayData, 'day_$dayKey'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
    );
  }

  String _translateEventType(String type, {String? saleType}) {
    if (type == 'sale') {
      if (saleType == 'deposit_given' || saleType == 'deposit') {
        return 'بيع كوديعة';
      } else if (saleType == 'deposit_paid') {
        return 'شراء من الوديعة';
      } else {
        return 'بيع';
      }
    } else if (type == 'payment') {
      return 'دفعة';
    } else if (type == 'gallon') {
      return 'معاملة جالون';
    }
    return type;
  }

  String _translateStatusFull(String status, {String? saleType}) {
    // Use the same logic as the dashboard for status translation
    switch (status.toLowerCase()) {
      case 'paid':
        if (saleType == 'deposit_given' || saleType == 'deposit') {
          return 'مدفوع (وديعة)';
        }
        return 'مدفوع';
      case 'unpaid':
        return 'غير مدفوع';
      case 'partial':
        return 'دفعة جزئية';
      case 'deposit':
        return 'عربون';
      case 'deposit_paid':
        return 'مدفوع من الوديعة';
      case 'purchase':
        return 'شراء من الوديعة';
      case 'return':
        return 'إرجاع وديعة';
      default:
        return status;
    }
  }

  String safeString(dynamic value, [String fallback = 'غير متوفر']) {
    if (value == null) return fallback;
    if (value is String) return value;
    print(
        '[EXPORT][WARNING] Expected String but got: \\${value.runtimeType} value=\\$value');
    return fallback;
  }

  DateTime? safeParseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value).toLocal();
      } catch (e) {
        print('[EXPORT][WARNING] Invalid date format: $value');
        return null;
      }
    }
    return null;
  }

  Future<void> _exportPeriodExcel(
      String period, Map<String, dynamic> data, String fileName) async {
    try {
      print('[EXPORT] Starting export for period: $period, file: $fileName');
      final excel = xls.Excel.createExcel();
      final sheet = excel['Sheet1'];
      final numberFormat = NumberFormat.decimalPattern('ar');
      // Header
      // --- FIX: Use correct date in header for daily export ---
      String? exportDay;
      if (period == 'day') {
        // fileName is like 'day_2025-07-08', extract the date
        final parts = fileName.split('_');
        if (parts.length > 1) exportDay = parts[1];
      }
      final today = (period == 'day' && exportDay != null)
          ? DateTime.parse(exportDay)
          : DateTime.now();
      sheet.appendRow(['التقرير اليومي']);
      sheet.appendRow(['التاريخ', DateFormat('yyyy-MM-dd').format(today)]);
      sheet.appendRow(['']);
      // Summary section
      double totalSales = 0;
      double totalProductionCost = 0;
      double totalPayments = 0;
      double monthExpenses = 0;
      final Map<String, double> productSummary = {};
      // Build unified event list as in manager dashboard
      final List<Map<String, dynamic>> events = [];
      final Set<String> shownDepositSales = {};
      final Set<String> fullyPaidDepositIds = {
        for (final payment in data['payments'] ?? [])
          if ((payment['sale']?['payment_status'] as String?)?.toLowerCase() ==
                  'paid' &&
              (payment['sale']?['sale_type'] as String?) == 'deposit_given')
            payment['sale']?['id'] as String? ?? ''
      };
      final Map<String, Map<String, dynamic>> fullyPaidDepositPayments = {
        for (final payment in data['payments'] ?? [])
          if ((payment['sale']?['payment_status'] as String?)?.toLowerCase() ==
                  'paid' &&
              (payment['sale']?['sale_type'] as String?) == 'deposit_given')
            (payment['sale']?['id'] as String? ?? ''): payment
      };
      // Build a map of saleId to total paid
      final Map<String, double> salePayments = {};
      for (final payment in data['payments'] ?? []) {
        final sale = payment['sale'] as Map<String, dynamic>?;
        if (sale == null) continue;
        final saleId = safeString(sale['id'], '');
        final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
        if (saleId.isNotEmpty) {
          salePayments[saleId] = (salePayments[saleId] ?? 0) + amount;
        }
      }
      // Add all sales events
      for (final sale in data['sales'] ?? []) {
        final saleId = safeString(sale['id'], '');
        if (saleId.isEmpty) {
          print('[EXPORT][WARNING] sale: id is null or empty: $saleId');
          continue;
        }
        if (fullyPaidDepositIds.contains(saleId)) continue;
        final saleType = safeString(sale['sale_type'], '');
        final paymentStatus = safeString(sale['payment_status'], '');
        final dateStr = safeString(
            sale['payment_date'], safeString(sale['created_at'], ''));
        final dt = safeParseDate(dateStr);
        if (dateStr.isNotEmpty && dt == null) {
          print('[EXPORT][WARNING] Could not parse date for sale: $dateStr');
        }
        if (paymentStatus == 'deposit') {
          if (!shownDepositSales.contains(saleId)) {
            events.add({
              'type': 'sale',
              'datetime': dt,
              'data': sale,
              'saleType': saleType,
              'paymentStatus': paymentStatus,
            });
            shownDepositSales.add(saleId);
          }
        } else {
          events.add({
            'type': 'sale',
            'datetime': dt,
            'data': sale,
            'saleType': saleType,
            'paymentStatus': paymentStatus,
          });
        }
      }
      // Add merged event for fully paid deposits
      for (final entry in fullyPaidDepositPayments.entries) {
        final payment = entry.value;
        final sale = payment['sale'] as Map<String, dynamic>;
        final saleId = safeString(sale['id'], '');
        if (saleId.isEmpty) {
          print(
              '[EXPORT][WARNING] fullyPaidDepositPayments: sale id is null or empty: $saleId');
          continue;
        }
        final paymentDate = safeString(payment['payment_date'], '');
        final paymentDt = safeParseDate(paymentDate);
        if (paymentDate.isNotEmpty && paymentDt == null) {
          print('[EXPORT][WARNING] Could not parse payment date: $paymentDate');
        }
        events.add({
          'type': 'sale',
          'datetime': paymentDt,
          'data': sale,
          'saleType': 'deposit_paid',
          'paymentStatus': 'deposit_paid',
          'payment': payment,
        });
      }
      // Step 1: Build a set of sale IDs paid at creation
      final Set<String> paidAtCreationSaleIds = {};
      for (final sale in data['sales'] ?? []) {
        final saleId = safeString(sale['id'], '');
        if (saleId.isEmpty) continue;
        if (safeString(sale['payment_status'], '') == 'paid') {
          final saleDate = safeParseDate(sale['created_at']);
          for (final payment in data['payments'] ?? []) {
            if (payment['sale']?['id'] == saleId) {
              final paymentDate = safeParseDate(payment['payment_date']);
              if (saleDate != null && paymentDate != null) {
                final diff = paymentDate.difference(saleDate).inSeconds.abs();
                if (diff <= 60) {
                  paidAtCreationSaleIds.add(saleId);
                  break;
                }
              }
            }
          }
        }
      }
      // Build location map for accurate location resolution
      final locationsRaw = await _supabase.from('locations').select('id, name');
      final locationMap = <String, String>{};
      for (final location in locationsRaw) {
        locationMap[location['id']] = location['name'];
      }

      // Add events for payments (only for late/partial payments, not instant payments)
      // Group payments by saleId
      final Map<String, List<Map<String, dynamic>>> paymentsBySale = {};
      for (final payment in data['payments'] ?? []) {
        final sale = payment['sale'] as Map<String, dynamic>?;
        if (sale == null) continue;
        final saleId = safeString(sale['id'], '');
        if (saleId.isEmpty) continue;
        if (!paymentsBySale.containsKey(saleId)) {
          paymentsBySale[saleId] = [];
        }
        paymentsBySale[saleId]!.add(payment);
      }
      for (final saleId in paymentsBySale.keys) {
        // Skip if this sale is paid at creation
        if (paidAtCreationSaleIds.contains(saleId)) continue;
        final salePaymentsList = paymentsBySale[saleId]!;
        // Sort payments by payment_date
        salePaymentsList.sort((a, b) => safeParseDate(a['payment_date'])!
            .compareTo(safeParseDate(b['payment_date'])!));
        double cumulativePaid = 0.0;
        final sale = salePaymentsList.first['sale'] as Map<String, dynamic>;
        final saleTotal = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
        for (int i = 0; i < salePaymentsList.length; i++) {
          final payment = salePaymentsList[i];
          final paymentDate = safeParseDate(payment['payment_date']);
          if (paymentDate == null) continue;
          final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
          cumulativePaid += amount;
          String paymentEventType = '';
          String paymentStatus = '';
          if (i == salePaymentsList.length - 1 &&
              (cumulativePaid >= saleTotal)) {
            paymentEventType = 'دفعة كاملة (تسوية متأخرة)';
            paymentStatus = 'دفعة كاملة (تسوية متأخرة)';
          } else {
            paymentEventType = 'دفعة جزئية (تسوية متأخرة)';
            paymentStatus = 'دفعة جزئية (تسوية متأخرة)';
          }
          final productName = sale['product']?['name'] != null
              ? safeString(sale['product']?['name'])
              : '';
          final qty = sale['quantity'] != null
              ? numberFormat.format(sale['quantity'])
              : '';
          final priceCol = (payment['amount'] as num?) != null
              ? numberFormat.format((payment['amount'] as num?)?.toDouble())
              : '';
          const totalCol = 'تسوية بيع قديم';
          // Use payment's own seller if available, else sale's seller
          String seller = '';
          if (payment['seller'] != null &&
              payment['seller']['first_name'] != null &&
              payment['seller']['last_name'] != null) {
            seller = '${safeString(payment['seller']['first_name'])} ${safeString(payment['seller']['last_name'])}';
          } else if (sale['seller'] != null &&
              sale['seller']['first_name'] != null &&
              sale['seller']['last_name'] != null) {
            seller = '${safeString(sale['seller']['first_name'])} ${safeString(sale['seller']['last_name'])}';
          }
          // Get location using location_id if available
          String location = '';
          if (sale['location'] != null && sale['location']['name'] != null) {
            location = safeString(sale['location']['name']);
          } else if (sale['customer'] != null &&
              sale['customer']['location_id'] != null) {
            location =
                locationMap[sale['customer']['location_id']] ?? 'غير متوفر';
          } else if (sale['customer'] != null &&
              sale['customer']['location'] != null) {
            location = safeString(sale['customer']['location']);
          }
          if (location.isEmpty) location = 'غير متوفر';
          events.add({
            'type': 'payment',
            'datetime': paymentDate,
            'data': payment,
            'saleType': safeString(sale['sale_type'], ''),
            'paymentStatus': paymentStatus,
            'eventTypeCol': paymentEventType,
            'transactionTypeCol': paymentEventType,
            'productName': productName,
            'qty': qty,
            'priceCol': priceCol,
            'totalCol': totalCol,
            'seller': seller,
            'location': location,
            'customerName': sale['customer']?['name'] ?? '',
          });
        }
      }
      // Add all gallon transactions (not linked to normal sales)
      for (final g in data['gallons'] ?? []) {
        final saleId = safeString(g['sale_id'], '');
        if (saleId.isNotEmpty) {
          print('[EXPORT][DEBUG] Skipping gallon with sale_id: $saleId');
          continue;
        }
        final dateStr = safeString(g['created_at'], '');
        final dt = safeParseDate(dateStr);
        if (dateStr.isNotEmpty && dt == null) {
          print(
              '[EXPORT][WARNING] Could not parse gallon created_at: $dateStr');
        }
        // Get location using customer's location_id
        String location = '';
        if (g['customer'] != null) {
          final customer = g['customer'];
          if (customer['location_id'] != null) {
            location = locationMap[customer['location_id']] ?? 'غير متوفر';
          } else if (customer['location'] != null) {
            if (customer['location'] is Map &&
                customer['location']['name'] != null) {
              location = safeString(customer['location']['name']);
            } else if (customer['location'] is String) {
              location = safeString(customer['location']);
            }
          }
        }
        if (location.isEmpty) {
          location = 'غير متوفر';
        }

        events.add({
          'type': 'gallon',
          'datetime': dt,
          'data': g,
          'saleType': null,
          'paymentStatus': safeString(g['status'], ''),
          'location': location,
        });
      }
      // Sort all events by datetime
      events.sort((a, b) {
        final adt = a['datetime'] as DateTime?;
        final bdt = b['datetime'] as DateTime?;
        if (adt == null && bdt == null) return 0;
        if (adt == null) return 1;
        if (bdt == null) return -1;
        return adt.compareTo(bdt);
      });
      // Calculate summary values and product summary
      if (period == 'day') {
        final Map<String, List<Map<String, dynamic>>> eventsByDay = {};
        for (final event in events) {
          final dt = event['datetime'] as DateTime?;
          if (dt == null) continue;
          final dayKey = DateFormat('yyyy-MM-dd').format(dt);
          if (!eventsByDay.containsKey(dayKey)) {
            eventsByDay[dayKey] = [];
          }
          eventsByDay[dayKey]!.add(event);
        }
        final dayKey = DateFormat('yyyy-MM-dd').format(today);
        final dayEvents = eventsByDay[dayKey] ?? [];
        // Track sale IDs already counted (to avoid double counting)
        final Set<String> countedSaleIds = {};
        // 1. Include paid-at-creation sales
        for (final event in dayEvents) {
          if (event['type'] == 'sale') {
            final sale = event['data'] as Map<String, dynamic>;
            final saleId = safeString(sale['id'], '');
            final paymentStatus = safeString(sale['payment_status'], '');
            // Paid at creation: sale is paid and there is no payment event for this sale on this day
            if (paymentStatus == 'paid') {
              // Check if there is a payment event for this sale on this day
              final hasPaymentEvent = dayEvents.any((e) =>
                  e['type'] == 'payment' &&
                  (e['data']['sale']?['id'] ?? '') == saleId);
              if (!hasPaymentEvent && !countedSaleIds.contains(saleId)) {
                final qty = (sale['quantity'] as num?)?.toDouble() ?? 0.0;
                final cost =
                    (sale['product']?['production_cost'] as num?)?.toDouble() ??
                        0.0;
                final total = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
                final productName = safeString(sale['product']?['name']);
                totalSales += total;
                totalProductionCost += qty * cost;
                productSummary[productName] =
                    (productSummary[productName] ?? 0) + qty;
                countedSaleIds.add(saleId);
              }
            }
          }
        }
        // 2. Include payments made on this day (late/partial payments)
        for (final event in dayEvents) {
          if (event['type'] == 'payment') {
            final p = event['data'] as Map<String, dynamic>;
            final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
            final sale = p['sale'] as Map<String, dynamic>?;
            final saleId = sale != null ? safeString(sale['id'], '') : '';
            // Avoid double counting if already counted as paid-at-creation
            if (saleId.isNotEmpty && countedSaleIds.contains(saleId)) continue;
            if (sale != null) {
              final qty = (sale['quantity'] as num?)?.toDouble() ?? 0.0;
              final cost =
                  (sale['product']?['production_cost'] as num?)?.toDouble() ??
                      0.0;
              final total = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
              if (total > 0) {
                final paidRatio = amount / total;
                totalProductionCost += qty * cost * paidRatio;
                final productName = safeString(sale['product']?['name']);
                productSummary[productName] =
                    (productSummary[productName] ?? 0) + (qty * paidRatio);
              }
            }
            totalSales += amount;
            countedSaleIds.add(saleId);
          }
        }
        // --- FIX: Always include production cost for all sales created on this day ---
        final List<Map<String, dynamic>> salesOnDay = [];
        for (final sale in data['sales'] ?? []) {
          final createdAt = safeString(sale['created_at'], '');
          if (createdAt.isNotEmpty) {
            final createdDate = DateFormat('yyyy-MM-dd')
                .format(DateTime.parse(createdAt).toLocal());
            if (createdDate == dayKey) {
              salesOnDay.add(sale);
            }
          }
        }
        for (final sale in salesOnDay) {
          final qty = (sale['quantity'] as num?)?.toDouble() ?? 0.0;
          final cost =
              (sale['product']?['production_cost'] as num?)?.toDouble() ?? 0.0;
          // Only add the cost if it hasn't already been counted (avoid double counting paid-at-creation sales)
          final saleId = safeString(sale['id'], '');
          if (!countedSaleIds.contains(saleId)) {
            totalProductionCost += qty * cost;
          }
        }
        // Expenses for the day
        for (final e in data['expenses'] ?? []) {
          final dateStr = safeString(e['date'], '');
          if (dateStr == dayKey) {
            monthExpenses += (e['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
      } else {
        // --- FIX: For monthly export, keep the current logic ---
        for (final event in events) {
          if (event['type'] == 'sale') {
            final sale = event['data'] as Map<String, dynamic>;
            final qty = (sale['quantity'] as num?)?.toDouble() ?? 0.0;
            final price = (sale['price_per_unit'] as num?)?.toDouble() ?? 0.0;
            final cost =
                (sale['product']?['production_cost'] as num?)?.toDouble() ??
                    0.0;
            final total = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
            final productName = safeString(sale['product']?['name']);
            totalSales += total;
            totalProductionCost += qty * cost;
            productSummary[productName] =
                (productSummary[productName] ?? 0) + qty;
          } else if (event['type'] == 'payment') {
            final p = event['data'] as Map<String, dynamic>;
            final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
            totalPayments += amount;
          }
        }
        for (final e in data['expenses'] ?? []) {
          monthExpenses += (e['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      // Summary section rows
      sheet.appendRow(['الملخص اليومي']);
      sheet.appendRow(['الإيرادات', numberFormat.format(totalSales)]);
      sheet.appendRow(
          ['تكلفة الصناعة', numberFormat.format(totalProductionCost)]);
      sheet.appendRow([
        'صافي الربح',
        numberFormat.format(totalSales - totalProductionCost)
      ]);
      sheet.appendRow(['المصروفات', numberFormat.format(monthExpenses)]);
      sheet.appendRow([
        'صافي الربح بعد المصروفات',
        numberFormat.format(totalSales - totalProductionCost - monthExpenses)
      ]);
      sheet.appendRow(['']);
      // Product summary table
      sheet.appendRow(['المنتج', 'الكمية', 'المجموع']);
      for (final entry in productSummary.entries) {
        // Find total per product
        double totalPerProduct = 0;
        for (final event in events) {
          if (event['type'] == 'sale') {
            final sale = event['data'] as Map<String, dynamic>;
            final productName = safeString(sale['product']?['name']);
            if (productName == entry.key) {
              final total = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
              totalPerProduct += total;
            }
          }
        }
        sheet.appendRow([
          entry.key,
          numberFormat.format(entry.value),
          numberFormat.format(totalPerProduct),
        ]);
      }
      sheet.appendRow(['']);
      // Details table header
      sheet.appendRow([
        'نوع الحدث',
        'نوع المعاملة',
        'الوقت',
        'العميل',
        'المنتج',
        'الكمية',
        'السعر',
        'المجموع',
        'حالة الدفع',
        'البائع'
      ]);

      // Group events by day
      final Map<String, List<Map<String, dynamic>>> eventsByDay = {};
      for (final event in events) {
        final dt = event['datetime'] as DateTime?;
        if (dt == null) continue;
        final dayKey = DateFormat('yyyy-MM-dd').format(dt);
        if (!eventsByDay.containsKey(dayKey)) {
          eventsByDay[dayKey] = [];
        }
        eventsByDay[dayKey]!.add(event);
      }

      // --- FIX: For daily export, always show all sales created on this day in the details table ---
      if (period == 'day') {
        final dayKey = DateFormat('yyyy-MM-dd').format(today);
        // 1. Gather all sales created on this day
        final List<Map<String, dynamic>> salesOnDay = [];
        for (final sale in data['sales'] ?? []) {
          final createdAt = safeString(sale['created_at'], '');
          if (createdAt.isNotEmpty) {
            final createdDate = DateFormat('yyyy-MM-dd')
                .format(DateTime.parse(createdAt).toLocal());
            if (createdDate == dayKey) {
              salesOnDay.add(sale);
            }
          }
        }
        // 2. Gather all payment and gallon events for this day (as before)
        final List<Map<String, dynamic>> dayEvents = eventsByDay[dayKey] ?? [];
        // 3. Build a set of sale IDs that have a payment/gallon event on this day (to avoid duplicate rows)
        final Set<String> eventSaleIds = {
          for (final e in dayEvents)
            if (e['type'] == 'payment' && e['data']['sale'] != null)
              safeString(e['data']['sale']['id'], '')
        };
        // 4. Write all sales created on this day (regardless of payment status)
        for (final sale in salesOnDay) {
          final saleId = safeString(sale['id'], '');
          final qty = (sale['quantity'] as num?)?.toDouble();
          final price = (sale['price_per_unit'] as num?)?.toDouble();
          final total = (sale['total_amount'] as num?)?.toDouble();
          final productName = safeString(sale['product']?['name']);
          final seller = sale['seller'] != null &&
                  sale['seller']['first_name'] != null &&
                  sale['seller']['last_name'] != null
              ? '${safeString(sale['seller']['first_name'])} ${safeString(sale['seller']['last_name'])}'
              : '';
          // Get location using location_id if available
          String location = '';
          if (sale['location'] != null && sale['location']['name'] != null) {
            location = safeString(sale['location']['name']);
          } else if (sale['customer'] != null &&
              sale['customer']['location_id'] != null) {
            location =
                locationMap[sale['customer']['location_id']] ?? 'غير متوفر';
          } else if (sale['customer'] != null &&
              sale['customer']['location'] != null) {
            location = safeString(sale['customer']['location']);
          }
          if (location.isEmpty) location = 'غير متوفر';
          // --- FIX: For details table, use current payment status (all payments up to now) ---
          double paid = 0.0;
          for (final payment in data['payments'] ?? []) {
            final paymentSale = payment['sale'] as Map<String, dynamic>?;
            if (paymentSale == null) continue;
            final paymentSaleId = safeString(paymentSale['id'], '');
            if (paymentSaleId != saleId) continue;
            paid += (payment['amount'] as num?)?.toDouble() ?? 0.0;
          }
          String paymentStatus = 'غير مدفوع';
          if (paid == 0) {
            paymentStatus = 'غير مدفوع';
          } else if (paid > 0 && paid < (total ?? 0.0)) {
            paymentStatus = 'مدفوع جزئياً';
          } else if (paid >= (total ?? 0.0)) {
            paymentStatus = 'مدفوع';
          }
          sheet.appendRow([
            _translateEventType('sale',
                saleType: safeString(sale['sale_type'], '')),
            '',
            DateFormat('HH:mm')
                .format(DateTime.parse(safeString(sale['created_at']))),
            safeString(sale['customer']?['name']),
            productName,
            qty != null ? numberFormat.format(qty) : '',
            price != null ? numberFormat.format(price) : '',
            total != null ? numberFormat.format(total) : '',
            paymentStatus,
            seller,
          ]);
        }
        // 5. Write all other events for this day (payments, gallons, etc.)
        for (final event in dayEvents) {
          final type = safeString(event['type'], '');
          if (type == 'sale') continue; // already handled above
          final dt = event['datetime'] as DateTime?;
          final timeCol = dt != null ? DateFormat('HH:mm').format(dt) : '';
          final eventTypeCol =
              _translateEventType(type, saleType: event['saleType']);
          String transactionTypeCol = '';
          if (type == 'gallon') {
            final g = event['data'] as Map<String, dynamic>;
            final txType = safeString(g['transaction_type'], '');
            switch (txType) {
              case 'deposit':
                transactionTypeCol = 'إيداع';
                break;
              case 'purchase':
                transactionTypeCol = 'شراء';
                break;
              case 'return':
                transactionTypeCol = 'إرجاع';
                break;
              default:
                transactionTypeCol = 'معاملة جالون';
            }
          } else if (type == 'payment') {
            final p = event['data'] as Map<String, dynamic>;
            final sale = p['sale'] as Map<String, dynamic>?;
            final saleId = sale != null ? safeString(sale['id'], '') : '';
            double paid = salePayments[saleId] ?? 0.0;
            double saleTotal =
                (sale?['total_amount'] as num?)?.toDouble() ?? 0.0;
            if (paid < saleTotal) {
              transactionTypeCol = 'دفعة جزئية (تسوية متأخرة)';
            } else {
              transactionTypeCol = 'دفعة كاملة (تسوية متأخرة)';
            }
          } else {
            transactionTypeCol = '';
          }
          if (type == 'payment') {
            sheet.appendRow([
              event['eventTypeCol'],
              event['transactionTypeCol'],
              timeCol,
              event['customerName'],
              event['productName'],
              event['qty'],
              event['priceCol'],
              event['totalCol'],
              event['paymentStatus'],
              event['seller'],
            ]);
          } else if (type == 'gallon') {
            final g = event['data'] as Map<String, dynamic>;
            final qty = (g['quantity'] as num?)?.toDouble();
            final amount = (g['amount'] as num?)?.toDouble();
            String productName = '';
            if (g['product'] != null && g['product']['name'] != null) {
              productName = safeString(g['product']['name']);
            } else if (g['product_name'] != null) {
              productName = safeString(g['product_name']);
            }
            final location = event['location'] as String? ?? 'غير متوفر';
            final seller = g['seller'] != null &&
                    g['seller']['first_name'] != null &&
                    g['seller']['last_name'] != null
                ? '${safeString(g['seller']['first_name'])} ${safeString(g['seller']['last_name'])}'
                : '';
            String price = '';
            String total = '';
            if (g['product'] != null &&
                g['product']['production_cost'] != null) {
              price = numberFormat
                  .format((g['product']['production_cost'] as num?) ?? 0);
              if (qty != null && g['product']['production_cost'] != null) {
                total = numberFormat
                    .format((g['product']['production_cost'] as num) * qty);
              } else {
                total = '';
              }
            } else if (g['amount'] != null) {
              total = numberFormat.format(amount ?? 0);
            }
            String gallonStatus = _translateStatusFull(
                safeString(g['status'], ''),
                saleType: transactionTypeCol);
            if (transactionTypeCol == 'إرجاع') {
              gallonStatus = 'إرجاع';
            }
            sheet.appendRow([
              eventTypeCol,
              transactionTypeCol,
              timeCol,
              g['customer']?['name'] ?? '',
              productName,
              qty != null ? numberFormat.format(qty) : '',
              price,
              total,
              gallonStatus,
              seller,
            ]);
          }
        }
      } else {
        // ... existing code for month ...
      }
      final fileBytes = excel.encode();
      // Set export path for all platforms
      String savePath;
      if (Platform.isAndroid) {
        final downloads =
            Directory('/storage/emulated/0/Download/AlrubaReports');
        if (!await downloads.exists()) await downloads.create(recursive: true);
        savePath = '${downloads.path}/$fileName.xlsx';
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        final appFolder = Directory('${docsDir.path}/AlrubaReports');
        if (!await appFolder.exists()) await appFolder.create(recursive: true);
        savePath = '${appFolder.path}/$fileName.xlsx';
      }
      print('[EXPORT][DEBUG] Will write file to: $savePath');
      final file = File(savePath)..createSync(recursive: true);
      print('[EXPORT][DEBUG] File created: ${file.path}');
      file.writeAsBytesSync(fileBytes!);
      print('[EXPORT][DEBUG] File written: ${file.path}');
      if (mounted) {
        print('[EXPORT][DEBUG] Widget is mounted, showing SnackBar');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تصدير الملف إلى: $savePath')),
        );
      } else {
        print('[EXPORT][WARNING] Widget is not mounted, cannot show SnackBar');
      }
      print('[EXPORT][DEBUG] Export function completed');
    } catch (e, st) {
      print('[EXPORT][ERROR] $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }
}
