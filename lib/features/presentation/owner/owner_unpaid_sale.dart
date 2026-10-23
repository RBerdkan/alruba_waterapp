// File: owner_unpaid_sales_page.dart

import 'package:alruba_waterapp/providers/distributor_sales_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as show;
import 'package:alruba_waterapp/providers/manager_slaes_provider.dart';
import 'package:alruba_waterapp/providers/location_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerUnpaidSalesPage extends ConsumerStatefulWidget {
  const OwnerUnpaidSalesPage({super.key});

  @override
  ConsumerState<OwnerUnpaidSalesPage> createState() =>
      _OwnerUnpaidSalesPageState();
}

class _OwnerUnpaidSalesPageState extends ConsumerState<OwnerUnpaidSalesPage> {
  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, TextEditingController> _paymentControllers = {};
  final Map<String, bool> _isProcessingMap = {};
  String? _globalErrorText;
  String? _selectedSeller;
  String? _selectedLocation;
  String _searchText = '';

  @override
  void dispose() {
    for (final controller in _paymentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _processPartialPayment(
    String customerName,
    List<ManagerSale> unpaidSales,
    double paymentAmount,
  ) async {
    setState(() {
      _isProcessingMap[customerName] = true;
      _globalErrorText = null;
    });

    try {
      double remainingPayment = paymentAmount;

      for (final sale in unpaidSales) {
        final double total = sale.totalAmount;
        final double paid = sale.amountPaid;
        final double balance = total - paid;

        if (balance <= 0) continue;

        double payNow = remainingPayment > balance ? balance : remainingPayment;
        remainingPayment -= payNow;

        double newAmountPaid = paid + payNow;
        String newStatus = newAmountPaid >= total ? 'paid' : 'partial';

        final now = DateTime.now();
        final paymentDate = DateTime(
                now.year, now.month, now.day, now.hour, now.minute, now.second)
            .toUtc()
            .toIso8601String();

        debugPrint('[OwnerUnpaid] Processing payment for sale: ${sale.saleId}');
        debugPrint('[OwnerUnpaid] Sale seller: ${sale.sellerId}');
        debugPrint(
            '[OwnerUnpaid] Current user: ${_client.auth.currentUser?.id}');
        debugPrint(
            '[OwnerUnpaid] Creating partial payment with date: $paymentDate');

        try {
          // Update the sale record
          await _client
              .from('sales')
              .update({
                'amount_paid': newAmountPaid,
                'payment_status': newStatus,
                'payment_date': paymentDate,
              })
              .eq('id', sale.saleId)
              .select();

          debugPrint('[OwnerUnpaid] Sale updated successfully');

          // Insert payment record
          await _client.from('payments').insert({
            'sale_id': sale.saleId,
            'amount': payNow,
            'payment_date': paymentDate,
            'note': 'دفعة من صفحة المالك',
          });

          debugPrint('[OwnerUnpaid] Payment record inserted successfully');
        } catch (e) {
          debugPrint('[OwnerUnpaid] Error processing sale ${sale.saleId}: $e');
          throw Exception('فشل في معالجة البيع ${sale.saleId}: $e');
        }

        if (remainingPayment <= 0) break;
      }

      // Refresh provider after update
      ref.invalidate(distributorSalesProvider);
      ref.invalidate(managerSalesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت معالجة الدفعة للعميل $customerName بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[OwnerUnpaid] Error in _processPartialPayment: $e');
      setState(() {
        _globalErrorText = 'حدث خطأ أثناء المعالجة: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingMap[customerName] = false;
        });
      }
    }
  }

  List<ManagerSale> _filterSales(List<ManagerSale> allSales) {
    debugPrint('[OwnerUnpaid] Filtering sales:');
    debugPrint('[OwnerUnpaid] - Selected seller: $_selectedSeller');
    debugPrint('[OwnerUnpaid] - Selected location: $_selectedLocation');
    debugPrint('[OwnerUnpaid] - Search text: $_searchText');

    return allSales.where((sale) {
      // Filter by payment status
      if (sale.paymentStatus != 'unpaid' && sale.paymentStatus != 'partial') {
        return false;
      }

      // Filter by search text
      if (_searchText.isNotEmpty) {
        final customerName = sale.customerName.toLowerCase();
        final productName = sale.productName.toLowerCase();
        if (!customerName.contains(_searchText.toLowerCase()) &&
            !productName.contains(_searchText.toLowerCase())) {
          return false;
        }
      }

      // Filter by seller
      if (_selectedSeller != null && sale.sellerId != _selectedSeller) {
        return false;
      }

      // Filter by location
      if (_selectedLocation != null && sale.location != _selectedLocation) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(managerSalesProvider);
    final locationsAsync = ref.watch(locationsProvider);
    final lbp = show.NumberFormat.currency(
        locale: 'ar_LB', symbol: 'ل.ل ', decimalDigits: 0);

    // Number formatter for input fields (with commas)
    final numberFormatter = show.NumberFormat('#,###', 'en_US');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المبيعات غير المدفوعة'),
          centerTitle: true,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00695C), Color(0xFF26A69A)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(managerSalesProvider);
          },
          child: salesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: Text('حدث خطأ: $err',
                  style: const TextStyle(color: Colors.red)),
            ),
            data: (allSales) {
              final filteredSales = _filterSales(allSales);
              final Map<String, List<ManagerSale>> salesByCustomer = {};

              for (final sale in filteredSales) {
                salesByCustomer
                    .putIfAbsent(sale.customerName, () => [])
                    .add(sale);
              }

              // Get unique sellers for filters
              final sellers = allSales
                  .where((s) =>
                      s.sellerId != null &&
                      s.sellerName != null &&
                      s.sellerName!.isNotEmpty)
                  .map((s) => {'id': s.sellerId, 'name': s.sellerName})
                  .fold<Map<String, Map<String, dynamic>>>(
                    {},
                    (map, seller) {
                      final id = seller['id'] as String;
                      if (!map.containsKey(id)) {
                        map[id] = seller;
                      }
                      return map;
                    },
                  )
                  .values
                  .toList();

              // Debug logging for sellers
              debugPrint('[OwnerUnpaid] Total sales: ${allSales.length}');
              debugPrint(
                  '[OwnerUnpaid] Sales with seller info: ${allSales.where((s) => s.sellerId != null && s.sellerName != null && s.sellerName!.isNotEmpty).length}');
              debugPrint(
                  '[OwnerUnpaid] Unique sellers found: ${sellers.length}');
              for (final seller in sellers) {
                debugPrint(
                    '[OwnerUnpaid] Seller: ${seller['id']} - ${seller['name']}');
              }

              return Column(
                children: [
                  // Filters Section - Always show this section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      border:
                          Border(bottom: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Column(
                      children: [
                        // Search Field
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'ابحث بالعميل أو المنتج...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onChanged: (value) =>
                              setState(() => _searchText = value),
                        ),
                        const SizedBox(height: 12),

                        // Seller and Location Filters
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                value: _selectedSeller,
                                decoration: InputDecoration(
                                  labelText: 'البائع',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('جميع البائعين'),
                                  ),
                                  ...sellers
                                      .map((seller) {
                                        final id = seller['id'] as String?;
                                        final name = seller['name'] as String?;
                                        if (id == null || name == null) {
                                          debugPrint(
                                              '[OwnerUnpaid] Invalid seller data: $seller');
                                          return null;
                                        }
                                        return DropdownMenuItem<String?>(
                                          value: id,
                                          child: Text(name),
                                        );
                                      })
                                      .where((item) => item != null)
                                      .cast<DropdownMenuItem<String?>>(),
                                ],
                                onChanged: (value) =>
                                    setState(() => _selectedSeller = value),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: locationsAsync.when(
                                loading: () => DropdownButtonFormField<String?>(
                                  value: null,
                                  decoration: InputDecoration(
                                    labelText: 'الموقع',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  items: [],
                                  onChanged: (value) {},
                                ),
                                error: (error, stack) =>
                                    DropdownButtonFormField<String?>(
                                  value: null,
                                  decoration: InputDecoration(
                                    labelText: 'الموقع (خطأ)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  items: [],
                                  onChanged: (value) {},
                                ),
                                data: (locations) {
                                  // Debug logging for locations
                                  debugPrint(
                                      '[OwnerUnpaid] Locations provider loaded: ${locations.length} locations');
                                  for (final location in locations) {
                                    debugPrint(
                                        '[OwnerUnpaid] Location: ${location.name}');
                                  }

                                  return DropdownButtonFormField<String?>(
                                    value: _selectedLocation,
                                    decoration: InputDecoration(
                                      labelText: 'الموقع',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('جميع المواقع'),
                                      ),
                                      ...locations.map((location) =>
                                          DropdownMenuItem<String?>(
                                            value: location.name,
                                            child: Text(location.name),
                                          )),
                                    ],
                                    onChanged: (value) => setState(
                                        () => _selectedLocation = value),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),

                        // Summary Stats
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatItem(
                                    'العملاء',
                                    salesByCustomer.length.toString(),
                                    Icons.people,
                                    Colors.blue,
                                  ),
                                  _buildStatItem(
                                    'المبيعات',
                                    filteredSales.length.toString(),
                                    Icons.receipt,
                                    Colors.orange,
                                  ),
                                  _buildStatItem(
                                    'المجموع المستحق',
                                    lbp.format(filteredSales.fold<double>(
                                      0,
                                      (sum, sale) =>
                                          sum +
                                          (sale.totalAmount - sale.amountPaid),
                                    )),
                                    Icons.attach_money,
                                    Colors.red,
                                  ),
                                ],
                              ),
                              // Clear Filters Button
                              if (_selectedSeller != null ||
                                  _selectedLocation != null ||
                                  _searchText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _selectedSeller = null;
                                        _selectedLocation = null;
                                        _searchText = '';
                                        _globalErrorText = null;
                                        // Clear all payment controllers
                                        for (final controller
                                            in _paymentControllers.values) {
                                          controller.clear();
                                        }
                                      });
                                    },
                                    icon: const Icon(Icons.clear, size: 16),
                                    label: const Text('مسح الفلاتر'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[300],
                                      foregroundColor: Colors.grey[700],
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sales List or Empty State
                  Expanded(
                    child: salesByCustomer.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  filteredSales.isEmpty && allSales.isNotEmpty
                                      ? Icons.search_off
                                      : Icons.check_circle_outline,
                                  size: 64,
                                  color: filteredSales.isEmpty &&
                                          allSales.isNotEmpty
                                      ? Colors.grey
                                      : Colors.green,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  filteredSales.isEmpty && allSales.isNotEmpty
                                      ? 'لا توجد نتائج للفلاتر المحددة'
                                      : 'لا توجد مبيعات غير مدفوعة',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  filteredSales.isEmpty && allSales.isNotEmpty
                                      ? 'جرب تغيير الفلاتر أو البحث'
                                      : 'جميع المبيعات مدفوعة بالكامل',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: salesByCustomer.entries.map((entry) {
                              final customerName = entry.key;
                              final customerSales = entry.value;

                              _paymentControllers.putIfAbsent(
                                  customerName, () => TextEditingController());
                              _isProcessingMap.putIfAbsent(
                                  customerName, () => false);

                              final totalOwed = customerSales.fold<double>(
                                0,
                                (sum, sale) =>
                                    sum + (sale.totalAmount - sale.amountPaid),
                              );

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 2,
                                child: ExpansionTile(
                                  title: Text(
                                    customerName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  subtitle: Text(
                                    'المجموع المستحق: ${lbp.format(totalOwed)}',
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  children: [
                                    ...customerSales.map((sale) {
                                      final total = sale.totalAmount;
                                      final paid = sale.amountPaid;
                                      final balance = total - paid;
                                      final saleDate = sale.date;
                                      final formattedDate = saleDate != null
                                          ? show.DateFormat('yyyy-MM-dd')
                                              .format(saleDate.toLocal())
                                          : '-';

                                      return ListTile(
                                        title: Text(sale.productName),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'الكمية: ${sale.quantity} - المدفوع: ${lbp.format(paid)} - المتبقي: ${lbp.format(balance)}',
                                            ),
                                            if (sale.sellerName != null &&
                                                sale.sellerName!.isNotEmpty)
                                              Text(
                                                'البائع: ${sale.sellerName}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            Text(
                                              'الموقع: ${sale.location}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              formattedDate,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: sale.paymentStatus ==
                                                        'partial'
                                                    ? Colors.orange[100]
                                                    : Colors.red[100],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                sale.paymentStatus == 'partial'
                                                    ? 'جزئي'
                                                    : 'غير مدفوع',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: sale.paymentStatus ==
                                                          'partial'
                                                      ? Colors.orange[800]
                                                      : Colors.red[800],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: TextField(
                                        controller:
                                            _paymentControllers[customerName],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          labelText:
                                              'ادخل مبلغ الدفع لهذا العميل',
                                          errorText: _globalErrorText,
                                          border: const OutlineInputBorder(),
                                          prefixIcon: const Icon(Icons.payment),
                                          hintText: 'مثال: 1000000',
                                        ),
                                        onChanged: (value) {
                                          if (value.isNotEmpty) {
                                            final number = int.tryParse(value);
                                            if (number != null) {
                                              final formatted = numberFormatter
                                                  .format(number);
                                              if (formatted != value) {
                                                _paymentControllers[
                                                        customerName]!
                                                    .text = formatted;
                                                _paymentControllers[
                                                            customerName]!
                                                        .selection =
                                                    TextSelection.fromPosition(
                                                  TextPosition(
                                                      offset: formatted.length),
                                                );
                                              }
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: ElevatedButton(
                                        onPressed: _isProcessingMap[
                                                customerName]!
                                            ? null
                                            : () {
                                                final input =
                                                    _paymentControllers[
                                                            customerName]!
                                                        .text
                                                        .trim();
                                                if (input.isEmpty) {
                                                  setState(() {
                                                    _globalErrorText =
                                                        'الرجاء إدخال مبلغ الدفع';
                                                  });
                                                  return;
                                                }
                                                // Remove commas and parse
                                                final normalized =
                                                    input.replaceAll(',', '');
                                                final paymentAmount =
                                                    double.tryParse(normalized);
                                                if (paymentAmount == null ||
                                                    paymentAmount <= 0) {
                                                  setState(() {
                                                    _globalErrorText =
                                                        'الرجاء إدخال مبلغ صحيح أكبر من صفر';
                                                  });
                                                  return;
                                                }
                                                if (paymentAmount > totalOwed) {
                                                  setState(() {
                                                    _globalErrorText =
                                                        'مبلغ الدفع أكبر من المجموع المستحق لهذا العميل';
                                                  });
                                                  return;
                                                }

                                                _processPartialPayment(
                                                    customerName,
                                                    customerSales,
                                                    paymentAmount);
                                              },
                                        style: ElevatedButton.styleFrom(
                                          minimumSize:
                                              const Size.fromHeight(48),
                                          backgroundColor:
                                              const Color(0xFF00695C),
                                        ),
                                        child: _isProcessingMap[customerName]!
                                            ? const CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white)
                                            : const Text('دفع لهذا العميل'),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
