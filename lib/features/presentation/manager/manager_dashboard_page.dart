// File: manager_sales_page.dart
import 'package:alruba_waterapp/models/gallon_transaction.dart';
import 'package:alruba_waterapp/providers/gallon_transactionprovider.dart';
import 'package:alruba_waterapp/providers/manager_slaes_provider.dart';
import 'package:alruba_waterapp/providers/location_provider.dart';
import 'package:alruba_waterapp/providers/role_provider.dart';
import 'package:alruba_waterapp/providers/owner_name_provider.dart';
import 'package:alruba_waterapp/providers/payments_provider.dart';
import 'package:alruba_waterapp/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Internal event type for grouping sales and payments by day
class _DayEvent {
  final ManagerSale? sale;
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

/// Provider for all users from profiles table (for owner access)
final allUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final response = await SupabaseService.client
        .from('profiles')
        .select('user_id, first_name, last_name, role')
        .order('first_name', ascending: true);

    return response;
  } catch (e) {
    throw Exception('Failed to load users: ${e.toString()}');
  }
});

/// Provider for payments with sales data for proper filtering
final managerPaymentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await SupabaseService.client.from('payments').select(r'''
        id,
        sale_id,
        amount,
        payment_date,
        note,
        sale:sales(
          id,
          created_at,
          sold_by,
          payment_status,
          quantity,
          price_per_unit,
          total_amount,
          amount_paid,
          sale_type,
          product:products!fk_sales_product(name),
          customer:customers!fk_sales_customer(
            name,
            phone,
            precise_location,
            location:locations(name)
          ),
          seller_profile:profiles!sales_sold_by_fkey(role, first_name, last_name)
        )
      ''').order('payment_date', ascending: false);

  return (response as List).cast<Map<String, dynamic>>();
});

class ManagerDashboardPage extends ConsumerStatefulWidget {
  const ManagerDashboardPage({super.key});

  @override
  ConsumerState<ManagerDashboardPage> createState() =>
      _ManagerDashboardPageState();
}

class _ManagerDashboardPageState extends ConsumerState<ManagerDashboardPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchText = '';
  String? _locationFilter;
  String? _selectedSeller;

  final _lbpFormat = NumberFormat.currency(
    locale: 'ar_LB',
    symbol: 'LBP ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(managerSalesProvider);
    final gallonsAsync = ref.watch(allGallonTransactionsProvider);
    final paymentsAsync = ref.watch(managerPaymentsProvider);
    final locationsAsync = ref.watch(locationsProvider);
    final roleAsync = ref.watch(roleProvider);
    final allUsersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم')),
      body: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('خطأ: $err')),
        data: (allSales) {
          return gallonsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('خطأ في الجالون: $err')),
            data: (allGallonsRaw) {
              final allGallons = {
                for (var g in allGallonsRaw)
                  if (g.id != null) g.id: g
              }.values.toList();
              return paymentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) =>
                    Center(child: Text('خطأ في المدفوعات: $err')),
                data: (allPayments) {
                  return roleAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) =>
                        Center(child: Text('خطأ في الدور: $err')),
                    data: (role) {
                      return allUsersAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, _) =>
                            Center(child: Text('خطأ في الأسماء: $err')),
                        data: (allUsers) {
                          final filteredSales =
                              _applyFilters(allSales, allUsers, role);
                          final filteredGallons =
                              _applyGallonFilters(allGallons, allUsers, role);
                          final filteredPayments =
                              _applyPaymentFilters(allPayments, allUsers, role);

                          if (filteredSales.isEmpty &&
                              filteredGallons.isEmpty &&
                              filteredPayments.isEmpty) {
                            return const Center(
                                child: Text('لا توجد سجلات مطابقة.'));
                          }

                          // Build the slivers for each day
                          final Map<String, List<_DayEvent>> eventsByDay = {};
                          final Set<String> shownDepositSales = {};
                          final Set<String> fullyPaidDepositIds = {
                            for (final payment in filteredPayments)
                              if ((payment['sale']?['payment_status']
                                              as String?)
                                          ?.toLowerCase() ==
                                      'paid' &&
                                  (payment['sale']?['sale_type'] as String?) ==
                                      'deposit_given')
                                payment['sale']?['id'] as String
                          };
                          final Map<String, Map<String, dynamic>>
                              fullyPaidDepositPayments = {
                            for (final payment in filteredPayments)
                              if ((payment['sale']?['payment_status']
                                              as String?)
                                          ?.toLowerCase() ==
                                      'paid' &&
                                  (payment['sale']?['sale_type'] as String?) ==
                                      'deposit_given')
                                (payment['sale']?['id'] as String): payment
                          };
                          for (final sale in filteredSales) {
                            if (fullyPaidDepositIds.contains(sale.saleId))
                              continue;
                            final saleDate = sale.date.toLocal();
                            final saleKey =
                                DateFormat('yyyy-MM-dd').format(saleDate);
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
                          for (final entry
                              in fullyPaidDepositPayments.entries) {
                            final payment = entry.value;
                            final sale =
                                payment['sale'] as Map<String, dynamic>;
                            final paymentDate =
                                DateTime.parse(payment['payment_date'])
                                    .toLocal();
                            final payKey =
                                DateFormat('yyyy-MM-dd').format(paymentDate);
                            final mergedEvent = _DayEvent.payment(
                              ManagerSale(
                                saleId: sale['id'] as String,
                                date: DateTime.parse(
                                    sale['created_at'] as String),
                                paymentDate: paymentDate,
                                paymentStatus: 'deposit_paid',
                                quantity:
                                    (sale['quantity'] as num?)?.toInt() ?? 0,
                                pricePerUnit: (sale['price_per_unit'] as num?)
                                        ?.toDouble() ??
                                    0.0,
                                totalAmount: (sale['total_amount'] as num?)
                                        ?.toDouble() ??
                                    0.0,
                                productName:
                                    sale['product']?['name'] as String? ??
                                        'Unknown Item',
                                customerName:
                                    sale['customer']?['name'] as String? ??
                                        'Unknown',
                                phone:
                                    sale['customer']?['phone'] as String? ?? '',
                                location: sale['customer']?['location']?['name']
                                        as String? ??
                                    'Unknown',
                                preciseLocation: sale['customer']
                                    ?['precise_location'] as String?,
                                amountPaid:
                                    (payment['amount'] as num?)?.toDouble() ??
                                        0.0,
                                sellerName: null,
                                sellerRole: null,
                                sellerId: sale['sold_by'] as String?,
                                saleType: sale['sale_type'] as String?,
                              ),
                              paymentDate,
                            );
                            eventsByDay
                                .putIfAbsent(payKey, () => [])
                                .add(mergedEvent);
                          }
                          for (final payment in filteredPayments) {
                            final sale =
                                payment['sale'] as Map<String, dynamic>?;
                            if (sale == null) continue;
                            final paymentStatus =
                                sale['payment_status'] as String? ?? '';
                            final saleCreatedAt =
                                DateTime.parse(sale['created_at'] as String);
                            final paymentDate =
                                DateTime.parse(payment['payment_date'])
                                    .toLocal();
                            final timeDifference =
                                paymentDate.difference(saleCreatedAt).abs();
                            if (timeDifference.inMinutes <= 1) {
                              continue;
                            }
                            final payKey =
                                DateFormat('yyyy-MM-dd').format(paymentDate);
                            final paymentAmount =
                                (payment['amount'] as num?)?.toDouble() ?? 0.0;
                            final partialEvent = _DayEvent.payment(
                              ManagerSale(
                                saleId: sale['id'] as String,
                                date: DateTime.parse(
                                    sale['created_at'] as String),
                                paymentDate: paymentDate,
                                paymentStatus: paymentStatus,
                                quantity:
                                    (sale['quantity'] as num?)?.toInt() ?? 0,
                                pricePerUnit: (sale['price_per_unit'] as num?)
                                        ?.toDouble() ??
                                    0.0,
                                totalAmount: (sale['total_amount'] as num?)
                                        ?.toDouble() ??
                                    0.0,
                                productName:
                                    sale['product']?['name'] as String? ??
                                        'Unknown Item',
                                customerName:
                                    sale['customer']?['name'] as String? ??
                                        'Unknown',
                                phone:
                                    sale['customer']?['phone'] as String? ?? '',
                                location: sale['customer']?['location']?['name']
                                        as String? ??
                                    'Unknown',
                                preciseLocation: sale['customer']
                                    ?['precise_location'] as String?,
                                amountPaid: paymentAmount,
                                sellerName: null,
                                sellerRole: null,
                                sellerId: sale['sold_by'] as String?,
                                saleType: sale['sale_type'] as String?,
                              ),
                              paymentDate,
                            );
                            eventsByDay
                                .putIfAbsent(payKey, () => [])
                                .add(partialEvent);
                          }
                          for (final gallon in filteredGallons) {
                            if (gallon.saleId != null &&
                                gallon.saleId!.isNotEmpty) {
                              continue;
                            }
                            final gallonDate = gallon.createdAt;
                            final gallonKey =
                                DateFormat('yyyy-MM-dd').format(gallonDate);
                            eventsByDay.putIfAbsent(gallonKey, () => []).add(
                                _DayEvent.gallon(
                                    gallon, gallon.createdAt.toLocal()));
                          }
                          final days = eventsByDay.keys.toList()
                            ..sort((b, a) => a.compareTo(b));

                          return RefreshIndicator(
                            onRefresh: () async {
                              ref.refresh(managerSalesProvider);
                              ref.refresh(allGallonTransactionsProvider);
                              ref.refresh(managerPaymentsProvider);
                              ref.refresh(locationsProvider);
                              ref.refresh(roleProvider);
                              ref.refresh(allUsersProvider);
                              await Future.delayed(
                                  const Duration(milliseconds: 500));
                            },
                            child: CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(
                                    child: _buildFilterSection(context,
                                        locationsAsync, allUsersAsync)),
                                ...days.map((day) {
                                  final events = eventsByDay[day]!
                                    ..sort((b, a) => a.time.compareTo(b.time));
                                  return SliverList(
                                    delegate: SliverChildListDelegate([
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        child: Card(
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          elevation: 2,
                                          child: _CollapsibleDayEvents(
                                            day: day,
                                            events: events,
                                            allUsers: allUsers,
                                            payments: filteredPayments,
                                            lbpFormat: _lbpFormat,
                                            getUserNameById: _getUserNameById,
                                            showSaleDetailsDialog:
                                                _showSaleDetailsDialog,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
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

  List<GallonTransaction> _applyGallonFilters(
      List<GallonTransaction> allGallons,
      List<Map<String, dynamic>> allUsers,
      String role) {
    return allGallons.where((g) {
      if (_searchText.isNotEmpty) {
        final customerName = g.customerName?.toLowerCase() ?? '';
        if (!customerName.contains(_searchText.toLowerCase())) {
          return false;
        }
      }

      if (_locationFilter != null && _locationFilter!.trim().isNotEmpty) {
        final location = (g.customerLocation ?? '').toLowerCase().trim();
        if (!location.contains(_locationFilter!.toLowerCase().trim())) {
          return false;
        }
      }

      if (_selectedSeller != null && g.sellerId != _selectedSeller) {
        return false;
      }

      if (_startDate != null && _endDate != null) {
        final d = g.createdAt.toLocal();
        if (d.isBefore(_startDate!) || d.isAfter(_endDate!)) return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _applyPaymentFilters(
      List<Map<String, dynamic>> allPayments,
      List<Map<String, dynamic>> allUsers,
      String role) {
    return allPayments.where((payment) {
      final sale = payment['sale'] as Map<String, dynamic>?;
      if (sale == null) return false;

      final customer = sale['customer'] as Map<String, dynamic>? ?? {};
      final customerName = customer['name'] as String? ?? '';

      if (_searchText.isNotEmpty) {
        if (!customerName.toLowerCase().contains(_searchText.toLowerCase())) {
          return false;
        }
      }

      if (_locationFilter != null && _locationFilter!.trim().isNotEmpty) {
        final location = customer['location']?['name'] as String? ?? '';
        if (!location
            .toLowerCase()
            .contains(_locationFilter!.toLowerCase().trim())) {
          return false;
        }
      }

      if (_selectedSeller != null && sale['sold_by'] != _selectedSeller) {
        return false;
      }

      if (_startDate != null && _endDate != null) {
        final paymentDate = DateTime.parse(payment['payment_date'] as String);
        if (paymentDate.isBefore(_startDate!) ||
            paymentDate.isAfter(_endDate!)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _getUserNameById(String? userId, List<Map<String, dynamic>> allUsers) {
    if (userId == null) return 'غير محدد';

    for (final user in allUsers) {
      if (user['user_id'] == userId) {
        final firstName = user['first_name'] as String? ?? '';
        final lastName = user['last_name'] as String? ?? '';
        final role = user['role'] as String? ?? '';
        return '$firstName $lastName ($role)'.trim();
      }
    }
    return 'غير محدد';
  }

  Widget _buildFilterSection(BuildContext ctx, AsyncValue<List<dynamic>> locs,
      AsyncValue<List<Map<String, dynamic>>> allUsers) {
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
            _buildLocationDropdown(locs),
            const SizedBox(height: 12),
            _buildSellerDropdown(allUsers),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.date_range),
              label: const Text('نطاق التاريخ'),
              onPressed: () => _pickDateRange(ctx),
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

  Widget _buildSellerDropdown(AsyncValue<List<Map<String, dynamic>>> allUsers) {
    return allUsers.when(
      data: (users) {
        // Get current user's role to determine what users to show in filter
        final currentUser = SupabaseService.client.auth.currentUser;
        String? currentUserRole;

        // Find current user in the users list
        for (final user in users) {
          if (user['user_id'] == currentUser?.id) {
            currentUserRole = user['role'] as String?;
            break;
          }
        }

        // Filter users based on current user's role
        List<Map<String, dynamic>> filteredUsers;
        String defaultFilterText;

        if (currentUserRole == 'owner') {
          // Owner can see all users (owners, managers, distributors)
          filteredUsers = users;
          defaultFilterText = 'جميع المستخدمين';
        } else if (currentUserRole == 'manager') {
          // Manager can see managers and distributors (no owners)
          filteredUsers = users.where((user) {
            final role = user['role'] as String? ?? '';
            return role == 'manager' || role == 'distributor';
          }).toList();
          defaultFilterText = 'جميع المدراء والموزعين';
        } else {
          // Distributor can only see themselves
          filteredUsers = users.where((user) {
            return user['user_id'] == currentUser?.id;
          }).toList();
          defaultFilterText = 'المستخدم الحالي';
        }

        final items = <DropdownMenuItem<String?>>[
          DropdownMenuItem<String?>(
            value: null,
            child: Text(defaultFilterText),
          ),
        ];

        // Add filtered users as seller options
        for (final user in filteredUsers) {
          final userId = user['user_id'] as String?;
          final firstName = user['first_name'] as String? ?? '';
          final lastName = user['last_name'] as String? ?? '';
          final role = user['role'] as String? ?? '';
          final fullName = '$firstName $lastName'.trim();

          if (userId != null && fullName.isNotEmpty) {
            items.add(DropdownMenuItem<String?>(
              value: userId,
              child: Text('$fullName ($role)'),
            ));
          }
        }

        return DropdownButtonFormField<String?>(
          value: _selectedSeller,
          items: items,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => setState(() => _selectedSeller = v),
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

  List<ManagerSale> _applyFilters(
      List<ManagerSale> all, List<Map<String, dynamic>> allUsers, String role) {
    return all.where((s) {
      if (_searchText.isNotEmpty &&
          !s.customerName.toLowerCase().contains(_searchText)) {
        return false;
      }
      if (_locationFilter != null &&
          !s.location.toLowerCase().contains(_locationFilter!.toLowerCase())) {
        return false;
      }
      if (_selectedSeller != null && s.sellerId != _selectedSeller) {
        return false;
      }
      if (_startDate != null && _endDate != null) {
        final d = s.date.toLocal();
        if (d.isBefore(_startDate!) || d.isAfter(_endDate!)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Widget _buildCombinedEventsList(
      List<ManagerSale> sales,
      List<GallonTransaction> gallons,
      List<Map<String, dynamic>> payments,
      List<Map<String, dynamic>> allUsers) {
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

    // Add all sales events
    for (final sale in sales) {
      // Skip all events for fully paid deposits (will show merged event below)
      if (fullyPaidDepositIds.contains(sale.saleId)) continue;

      final saleDate = sale.date.toLocal();
      final saleKey = DateFormat('yyyy-MM-dd').format(saleDate);

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
        ManagerSale(
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
          sellerName: null,
          sellerRole: null,
          sellerId: sale['sold_by'] as String?,
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
        ManagerSale(
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
          sellerName: null,
          sellerRole: null,
          sellerId: sale['sold_by'] as String?,
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
            child: _CollapsibleDayEvents(
              day: day,
              events: events,
              allUsers: allUsers,
              payments: payments,
              lbpFormat: _lbpFormat,
              getUserNameById: _getUserNameById,
              showSaleDetailsDialog: _showSaleDetailsDialog,
            ),
          ),
        );
      },
    );
  }

  void _showSaleDetailsDialog(ManagerSale sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل البيع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('العميل: ${sale.customerName}'),
            Text('المنتج: ${sale.productName}'),
            Text('الكمية: ${sale.quantity}'),
            Text('السعر: ${_lbpFormat.format(sale.pricePerUnit)}'),
            Text('المجموع: ${_lbpFormat.format(sale.totalAmount)}'),
            Text('الحالة: ${sale.paymentStatus}'),
            if (sale.amountPaid > 0)
              Text('المدفوع: ${_lbpFormat.format(sale.amountPaid)}'),
            if (sale.sellerName != null && sale.sellerName!.isNotEmpty)
              Text('البائع: ${sale.sellerName}'),
            Text(
                'التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(sale.date)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _CollapsibleDayEvents extends StatefulWidget {
  final String day;
  final List<_DayEvent> events;
  final List<Map<String, dynamic>> allUsers;
  final List<Map<String, dynamic>> payments;
  final NumberFormat lbpFormat;
  final String Function(String?, List<Map<String, dynamic>>) getUserNameById;
  final void Function(ManagerSale) showSaleDetailsDialog;
  const _CollapsibleDayEvents({
    required this.day,
    required this.events,
    required this.allUsers,
    required this.payments,
    required this.lbpFormat,
    required this.getUserNameById,
    required this.showSaleDetailsDialog,
    Key? key,
  }) : super(key: key);

  @override
  State<_CollapsibleDayEvents> createState() => _CollapsibleDayEventsState();
}

class _CollapsibleDayEventsState extends State<_CollapsibleDayEvents> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        DateFormat('MMM dd, yyyy', 'ar').format(DateTime.parse(widget.day)),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      initiallyExpanded: expanded,
      onExpansionChanged: (val) => setState(() => expanded = val),
      children: [
        ...(expanded || events.length <= 2 ? events : events.take(2))
            .map((e) => _buildEventTile(
                  e,
                  widget.allUsers,
                  widget.payments,
                  widget.lbpFormat,
                  widget.getUserNameById,
                  widget.showSaleDetailsDialog,
                ))
            .toList(),
        if (!expanded && events.length > 2)
          TextButton(
            onPressed: () => setState(() => expanded = true),
            child: const Text('عرض المزيد'),
          ),
      ],
    );
  }
}

Widget _buildEventTile(
  _DayEvent e,
  List<Map<String, dynamic>> allUsers,
  List<Map<String, dynamic>> payments,
  NumberFormat _lbpFormat,
  String Function(String?, List<Map<String, dynamic>>) _getUserNameById,
  void Function(ManagerSale) _showSaleDetailsDialog,
) {
  if (e.isSale && !e.isPayment) {
    final s = e.sale!;
    IconData icon;
    Color color;
    String subtitleText;

    // Special handling for deposit sales
    if ((s.saleType == 'deposit_given' || s.saleType == 'deposit') &&
        (s.paymentStatus == 'paid' || s.paymentStatus == 'deposit_paid')) {
      icon = Icons.account_balance_wallet;
      color = Colors.green;
      subtitleText =
          '${s.customerName} اشترى ${s.quantity} جالون كوديعة (مدفوع)';
    } else if ((s.saleType == 'deposit_given' || s.saleType == 'deposit')) {
      icon = Icons.account_balance_wallet;
      color = Colors.orange;
      subtitleText =
          '${s.customerName} اشترى ${s.quantity} جالون كوديعة (غير مدفوع)';
    } else if (s.paymentStatus == 'paid' && s.saleType == 'deposit_paid') {
      // Sales paid from deposit
      icon = Icons.local_drink;
      color = Colors.green;
      subtitleText =
          '${s.customerName} اشترى ${s.quantity} ${s.productName} (مدفوع من الوديعة)';
    } else if (s.paymentStatus == 'paid') {
      // Normal paid sales
      icon = Icons.check;
      color = Colors.green;
      subtitleText = '${s.productName} • الكمية: ${s.quantity} • مدفوع';
    } else if (s.paymentStatus == 'partial' ||
        (s.amountPaid > 0 && s.amountPaid < s.totalAmount)) {
      icon = Icons.account_balance_wallet;
      color = Colors.orange;
      subtitleText =
          '${s.productName} • الكمية: ${s.quantity} • دفعة جزئية (${s.amountPaid.toStringAsFixed(0)} من ${s.totalAmount.toStringAsFixed(0)})';
    } else {
      icon = Icons.hourglass_empty;
      color = Colors.orange;
      subtitleText = '${s.productName} • الكمية: ${s.quantity} • غير مدفوع';
    }

    return ListTile(
      leading: CircleAvatar(
          backgroundColor: color, child: Icon(icon, color: Colors.white)),
      title: Text(s.customerName,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitleText),
          if (s.sellerName != null && s.sellerName!.isNotEmpty)
            Text(
              'البائع: ${s.sellerName}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _lbpFormat.format(s.totalAmount),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            DateFormat('HH:mm').format(e.time.toLocal()),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
      onTap: () => _showSaleDetailsDialog(s),
    );
  } else if (e.isSale && e.isPayment) {
    final s = e.sale!;
    // Special merged event for fully paid deposit
    if (s.paymentStatus == 'deposit_paid') {
      return ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.local_drink, color: Colors.white),
        ),
        title: Text(
            'تم دفع وديعة بقيمة ${_lbpFormat.format(s.totalAmount)} مقابل ${s.quantity} جالون كوديعة',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.customerName} • ${s.productName}'),
            if (s.sellerName != null && s.sellerName!.isNotEmpty)
              Text(
                'البائع: ${s.sellerName}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            // Show who processed the payment
            Text(
              'تمت المعالجة بواسطة: ${_getUserNameById(s.sellerId, allUsers)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _lbpFormat.format(s.totalAmount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              DateFormat('HH:mm').format(e.time.toLocal()),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
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
        final thisPaymentDate = DateTime.parse(paymentDateStr).toLocal();
        if (thisPaymentDate.isBefore(paymentDate!) ||
            thisPaymentDate.isAtSameMomentAs(paymentDate!)) {
          cumulativeAmount += (payment['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    final isFinalPayment = cumulativeAmount >= totalSaleAmount;
    IconData icon = Icons.attach_money;
    Color color = isFinalPayment ? Colors.green : Colors.orange;
    final paymentLabel = isFinalPayment ? 'دفع كامل' : 'دفعة جزئية';
    final individualPaymentAmount = _lbpFormat.format(paymentAmount);
    final totalAmount = _lbpFormat.format(totalSaleAmount);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text('$paymentLabel من قبل ${s.customerName}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تم الدفع $individualPaymentAmount من $totalAmount'),
          if (s.sellerName != null && s.sellerName!.isNotEmpty)
            Text(
              'البائع: ${s.sellerName}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          // Show who processed the payment
          Text(
            'تمت المعالجة بواسطة: ${_getUserNameById(s.sellerId, allUsers)}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            individualPaymentAmount,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            DateFormat('HH:mm').format(e.time.toLocal()),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  } else {
    final g = e.gallonTransaction!;
    IconData icon;
    String subtitleText;
    Color iconColor;

    if (g.transactionType == 'return') {
      icon = Icons.swap_horiz;
      iconColor = Colors.green;
      subtitleText = '${g.customerName} أرجع ${g.quantity} جالون كوديعة';
    } else if (g.transactionType == 'purchase') {
      icon = Icons.water_drop;
      iconColor = Colors.blue;
      subtitleText = '${g.customerName} أخذ ${g.quantity} جالون كوديعة';
    } else if (g.transactionType == 'deposit') {
      icon = Icons.account_balance_wallet;
      iconColor = Colors.purple;
      subtitleText = '${g.customerName} أودع ${g.quantity} جالون كوديعة';
    } else {
      icon = Icons.local_drink;
      iconColor = Colors.grey;
      subtitleText = '${g.transactionType} ${g.quantity} جالون';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor,
        child: Icon(icon, color: Colors.white),
      ),
      title: const Text('عملية جالون',
          style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitleText),
          if (g.sellerName != null && g.sellerName!.isNotEmpty)
            Text(
              'البائع: ${g.sellerName}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${g.quantity} جالون',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            DateFormat('HH:mm').format(e.time.toLocal()),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
