import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/customer_location_field.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/payment_section.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/pricing_section.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/product_dropdown.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/sale_form_submit_button.dart';
import 'package:alruba_waterapp/models/customer.dart';
import 'package:alruba_waterapp/models/offline_gallon_transaction.dart';
import 'package:alruba_waterapp/models/offline_sale.dart';
import 'package:alruba_waterapp/models/product.dart';
import 'package:alruba_waterapp/providers/customers_provider.dart';
import 'package:alruba_waterapp/providers/location_provider.dart';
import 'package:alruba_waterapp/providers/products_provider.dart';
import 'package:alruba_waterapp/services/offline_gallon_queue.dart';
import 'package:alruba_waterapp/services/offline_sales_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class MakeSalePage extends ConsumerStatefulWidget {
  const MakeSalePage({super.key});

  @override
  ConsumerState<MakeSalePage> createState() => _MakeSalePageState();
}

class _MakeSalePageState extends ConsumerState<MakeSalePage> {
  final _formKey = GlobalKey<FormState>();

  // ---------------------------- Customer Fields ----------------------------
  bool _isNewCustomer = false;
  String? _existingCustomerId;
  String? _existingCustomerName;
  String? _existingCustomerPhone;
  String? _existingCustomerLocation;
  String? _existingCustomerType;

  String? _newCustomerName;
  String? _newCustomerPhone;
  String? _newCustomerType;
  String? _newCustomerLocation;
  String? _preciseLocation;

  final List<String> _placeholderTypes = ['distributor', 'regular'];

  // ---------------------------- Product & Pricing ----------------------------
  Product? _selectedProduct;
  final TextEditingController _priceController =
      TextEditingController(text: '0.00');
  final TextEditingController _quantityController =
      TextEditingController(text: '0');
  double _totalPrice = 0.0;

  // ---------------------------- Payment ----------------------------
  String _paymentStatus = 'Paid';
  List<String> _paymentOptions = ['Paid', 'Unpaid'];
  final TextEditingController _partialPaymentController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _priceController.addListener(_updateTotalPrice);
    _quantityController.addListener(_updateTotalPrice);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    _partialPaymentController.dispose();
    super.dispose();
  }

  void _updateTotalPrice() {
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final qty = int.tryParse(_quantityController.text) ?? 0;
    setState(() {
      _totalPrice = price * qty;
    });
  }

  void _autoFillPrice() {
    if (_selectedProduct == null) return;

    // Determine if customer is distributor
    bool isDist = false;
    if (_isNewCustomer) {
      isDist = _newCustomerType == 'distributor';
    } else {
      isDist = _existingCustomerType == 'distributor';
    }

    final price =
        isDist ? _selectedProduct!.marketPrice : _selectedProduct!.homePrice;
    _priceController.text = price.toStringAsFixed(2);
    _updateTotalPrice();

    _paymentOptions = _selectedProduct!.isRefillable
        ? ['Paid', 'Unpaid', 'Deposit']
        : ['Paid', 'Unpaid'];
    if (!_paymentOptions.contains(_paymentStatus)) {
      setState(() => _paymentStatus = _paymentOptions.first);
    }
  }

  String _defaultLocationId() => '17c1cb39-7b97-494b-be85-bae7290cd54c';

  Future<void> _submitSale() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    // 1) Validate required fields
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار منتج')),
      );
      return;
    }

    if (_isNewCustomer && (_newCustomerName?.isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم العميل')),
      );
      return;
    }

    if (_isNewCustomer && (_newCustomerPhone?.isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم الهاتف')),
      );
      return;
    }

    // 2) Get location ID
    final locationsAsync = ref.read(locationsProvider);
    final locationId = await locationsAsync.when(
      data: (locations) => locations.isNotEmpty ? locations.first.id : null,
      loading: () => null,
      error: (_, __) => null,
    );

    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ في تحميل المواقع')),
      );
      return;
    }

    // 3) Handle customer (create new or use existing)
    String? customerId;
    if (_isNewCustomer) {
      // Create new customer
      try {
        final response = await Supabase.instance.client
            .from('customers')
            .insert({
              'name': _newCustomerName,
              'phone': _newCustomerPhone,
              'type': _newCustomerType ?? 'regular',
              'assigned_to': Supabase.instance.client.auth.currentUser?.id,
              'location_id': locationId,
              'precise_location': _preciseLocation,
            })
            .select('id')
            .single();
        customerId = response['id'] as String;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء العميل: $e')),
        );
        return;
      }
    } else {
      customerId = _existingCustomerId;
    }

    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ في تحديد العميل')),
      );
      return;
    }

    // 4) Handle deposit (trust) logic
    if (_paymentStatus.toLowerCase() == 'deposit') {
      // Only create a gallon_transaction with transaction_type = 'deposit'
      try {
        final localTxId = const Uuid().v4();

        final gallonTx = OfflineGallonTransaction(
          localTxId: localTxId,
          saleLocalId: '', // No sale for deposit
          customerId: customerId,
          productId: _selectedProduct!.id,
          quantity: int.tryParse(_quantityController.text) ?? 0,
          transactionType: 'deposit',
          status: 'deposit',
          amount: 0.0,
          saleId: null,
          customerName:
              _isNewCustomer ? _newCustomerName : _existingCustomerName,
          productName: _selectedProduct!.name,
          createdAt: DateTime.now().toUtc(),
        );
        await OfflineGallonQueue.addTransaction(gallonTx);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الجالونات كوديعة (ثقة) للعميل'),
            backgroundColor: Colors.orange,
          ),
        );
        _formKey.currentState!.reset();
        setState(() {
          _selectedProduct = null;
          _existingCustomerId = null;
          _existingCustomerName = null;
          _existingCustomerPhone = null;
          _existingCustomerType = null;
          _newCustomerName = null;
          _newCustomerPhone = null;
          _newCustomerType = null;
          _preciseLocation = null;
          _totalPrice = 0.0;
        });
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تسجيل الوديعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // 5) Handle normal paid/unpaid sale
    double amountPaid = 0.0;
    if (_paymentStatus.toLowerCase() == 'paid') {
      amountPaid = _totalPrice;
    } else if (_paymentStatus.toLowerCase() == 'unpaid') {
      amountPaid = 0.0;
    }

    try {
      final localSaleId = const Uuid().v4();

      final offlineSale = OfflineSale(
        isNewCustomer: _isNewCustomer,
        newCustomerPhone: _isNewCustomer ? _newCustomerPhone : null,
        existingCustomerId: !_isNewCustomer ? _existingCustomerId : null,
        customerName: _isNewCustomer ? _newCustomerName : _existingCustomerName,
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.name,
        pricePerUnit: double.tryParse(_priceController.text) ?? 0.0,
        quantity: int.tryParse(_quantityController.text) ?? 0,
        totalPrice: _totalPrice,
        paymentStatus: _paymentStatus.toLowerCase(),
        createdAt: DateTime.now().toUtc(),
        customerPhone:
            _isNewCustomer ? _newCustomerPhone : _existingCustomerPhone,
        soldBy: Supabase.instance.client.auth.currentUser?.id ?? '',
        locationId: locationId,
        localSaleId: localSaleId,
        saleType: 'normal',
        amountPaid: amountPaid,
      );
      await OfflineSalesQueue.addSale(offlineSale);

      // If product is refillable, queue a gallon transaction for purchase
      if (_selectedProduct?.isRefillable == true) {
        final localTxId = const Uuid().v4();

        final gallonTx = OfflineGallonTransaction(
          localTxId: localTxId,
          saleLocalId: localSaleId,
          customerId: customerId,
          productId: _selectedProduct!.id,
          quantity: int.tryParse(_quantityController.text) ?? 0,
          transactionType: 'purchase',
          status: _paymentStatus.toLowerCase(),
          amount: _totalPrice,
          saleId: null, // Will be set after sync
          createdAt: DateTime.now().toUtc(),
        );
        await OfflineGallonQueue.addTransaction(gallonTx);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة البيع إلى قائمة الانتظار (غير متزامن بعد)'),
          backgroundColor: Colors.orange,
        ),
      );

      // Clear form
      _formKey.currentState!.reset();
      setState(() {
        _selectedProduct = null;
        _existingCustomerId = null;
        _existingCustomerName = null;
        _existingCustomerPhone = null;
        _existingCustomerType = null;
        _newCustomerName = null;
        _newCustomerPhone = null;
        _newCustomerType = null;
        _preciseLocation = null;
        _totalPrice = 0.0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إضافة البيع إلى قائمة الانتظار: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final customersAsync = ref.watch(customersProvider);
    ref.watch(productsProvider);
    final locationsAsync = ref.watch(locationsProvider);

    // ➤ Only enable submit if existing customer or precise location ready
    final canSubmit = !_isNewCustomer || (_preciseLocation != null);

    return Scaffold(
      appBar: AppBar(title: const Text('إجراء بيع')),
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ── Customer Info Card ─────────────────────────────────────────────
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // New vs Existing switch
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 20),
                          const SizedBox(width: 8),
                          Text('معلومات العميل',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(_isNewCustomer ? 'جديد' : 'موجود'),
                          Switch(
                            value: _isNewCustomer,
                            onChanged: (val) {
                              setState(() {
                                _isNewCustomer = val;
                                _existingCustomerId = null;
                                _existingCustomerName = null;
                                _existingCustomerPhone = null;
                                _existingCustomerLocation = null;
                                _existingCustomerType = null;
                                _newCustomerName = null;
                                _newCustomerPhone = null;
                                _newCustomerType = null;
                                _newCustomerLocation = null;
                                _preciseLocation = null;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Existing customer picker
                      if (!_isNewCustomer)
                        customersAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Text('Error: $err'),
                          data: (list) {
                            final mapped = list
                                .map((c) => {
                                      'id': c['id'].toString(),
                                      'name': c['name'].toString(),
                                      'phone': c['phone'].toString(),
                                      'locationId': c['location_id'].toString(),
                                      'type': c['type'].toString(),
                                    })
                                .toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.people_alt),
                                  label: Text(_existingCustomerName ??
                                      'اختر عميلًا موجودًا'),
                                  onPressed: () async {
                                    final chosen = await showModalBottomSheet<
                                        Map<String, String>>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      enableDrag: true,
                                      isDismissible: true,
                                      builder: (ctx) => Padding(
                                        padding: EdgeInsets.only(
                                          bottom: MediaQuery.of(context)
                                              .viewInsets
                                              .bottom,
                                        ),
                                        child: _CustomerSearchSheet(
                                          customers: mapped,
                                        ),
                                      ),
                                    );
                                    if (chosen != null) {
                                      setState(() {
                                        _existingCustomerId = chosen['id'];
                                        _existingCustomerName = chosen['name'];
                                        _existingCustomerPhone =
                                            chosen['phone'];
                                        _existingCustomerLocation =
                                            chosen['locationId'];
                                        _existingCustomerType = chosen['type'];
                                      });
                                      // Auto-fill price based on customer type
                                      _autoFillPrice();
                                    }
                                  },
                                ),
                                const SizedBox(height: 8),
                                if (_existingCustomerId != null)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person_pin),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(_existingCustomerName!,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text('(${_existingCustomerPhone!})',
                                            style: theme.textTheme.bodySmall),
                                        const SizedBox(width: 8),
                                        Chip(
                                          label: Text(
                                            (_existingCustomerType ==
                                                    'distributor')
                                                ? 'موزع'
                                                : (_existingCustomerType ==
                                                        'regular')
                                                    ? 'عادي'
                                                    : 'غير معروف',
                                          ),
                                          backgroundColor: theme
                                              .colorScheme.secondary
                                              .withAlpha(26),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                      // New customer inputs
                      if (_isNewCustomer) ...[
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'الاسم الكامل',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          onSaved: (v) => _newCustomerName = v,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                          onSaved: (v) => _newCustomerPhone = v,
                          validator: (v) =>
                              v == null || v.isEmpty ? 'أدخل رقم الهاتف' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'نوع العميل',
                            border: OutlineInputBorder(),
                          ),
                          value: _newCustomerType,
                          items: _placeholderTypes
                              .map((type) => DropdownMenuItem(
                                  value: type, child: Text(type)))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _newCustomerType = v;
                              _autoFillPrice();
                            });
                          },
                          validator: (v) =>
                              v == null ? 'الرجاء اختيار نوع' : null,
                        ),
                        const SizedBox(height: 16),
                        locationsAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Text('Error: $err'),
                          data: (locList) => CustomerLocationDropdown(
                            selectedLocation: _newCustomerLocation,
                            onLocationChanged: (v) =>
                                setState(() => _newCustomerLocation = v),
                            locations: locList
                                .map((loc) => {'id': loc.id, 'name': loc.name})
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ExactLocationWidget(
                          onLocationSelected: (val) =>
                              setState(() => _preciseLocation = val),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Product & Pricing Card ──────────────────────────────────────────
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.shopping_bag_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text('المنتج والتسعير',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 16),
                      ref.watch(productsProvider).when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (err, _) => Text('خطأ في المنتج: $err'),
                            data: (prodList) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ProductDropdown(
                                  selectedProduct: _selectedProduct,
                                  onProductChanged: (prod) {
                                    setState(() {
                                      _selectedProduct = prod;
                                      _autoFillPrice();
                                    });
                                  },
                                  products: prodList,
                                ),
                                const SizedBox(height: 24),
                                PricingSection(
                                  priceController: _priceController,
                                  quantityController: _quantityController,
                                  totalPrice: _totalPrice,
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),

              // ── Payment Card ─────────────────────────────────────────────────────
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.payment_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text('تفاصيل الدفع',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 16),
                      PaymentSection(
                        paymentStatus: _paymentStatus,
                        paymentOptions: _paymentOptions,
                        onPaymentStatusChanged: (val) {
                          setState(() {
                            _paymentStatus = val ?? 'Paid';
                          });
                        },
                      ),
                      if (_paymentStatus.toLowerCase() == 'partial')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: TextFormField(
                            controller: _partialPaymentController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'المبلغ المدفوع جزئياً',
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (_paymentStatus.toLowerCase() == 'partial') {
                                final v = double.tryParse(val ?? '');
                                if (v == null || v <= 0 || v >= _totalPrice) {
                                  return 'يرجى إدخال مبلغ جزئي صحيح أقل من المجموع';
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Submit Button ───────────────────────────────────────────────────
              SaleFormSubmitButton(
                onPressed: canSubmit
                    ? _submitSale
                    : () {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text(
                              'يرجى الانتظار حتى يتم تحميل الموقع الدقيق بالكامل.'),
                        ));
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet for selecting existing customer ─────────────────────────────
class _CustomerSearchSheet extends StatefulWidget {
  final List<Map<String, String>> customers;
  const _CustomerSearchSheet({required this.customers});

  @override
  State<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends State<_CustomerSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<Map<String, String>> _filteredCustomers;

  @override
  void initState() {
    super.initState();
    _filteredCustomers = widget.customers;
    _searchCtrl.addListener(_filterList);
  }

  void _filterList() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredCustomers = q.isEmpty
          ? widget.customers
          : widget.customers
              .where((c) =>
                  c['name']!.toLowerCase().contains(q) ||
                  c['phone']!.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;

    return Container(
      height: screenHeight * 0.8, // Fixed height instead of draggable
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Title with close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'اختر عميلًا',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'إغلاق',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'ابحث عن العميل',
                border: OutlineInputBorder(),
              ),
              autofocus: true, // Auto focus the search field
            ),
          ),
          const SizedBox(height: 8),

          // Customer list
          Expanded(
            child: _filteredCustomers.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد نتائج',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _filteredCustomers.length,
                    itemBuilder: (context, i) {
                      final cust = _filteredCustomers[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.primary.withOpacity(0.1),
                            child: Icon(
                              Icons.person,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            cust['name']!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            cust['phone']!,
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: Chip(
                            label: Text(
                              (cust['type'] == 'distributor') ? 'موزع' : 'عادي',
                            ),
                            backgroundColor:
                                theme.colorScheme.secondary.withAlpha(26),
                          ),
                          onTap: () => Navigator.pop(context, cust),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom padding to account for keyboard
          SizedBox(height: keyboardHeight > 0 ? keyboardHeight * 0.1 : 16),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
