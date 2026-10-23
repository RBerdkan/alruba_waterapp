import 'package:alruba_waterapp/models/gallon_transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final gallonTransactionsProvider =
    FutureProvider.autoDispose<List<GallonTransaction>>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return [];

  // Fetch all gallon transactions with sales and product joins
  // For deposits (no sale), we need to get them directly
  // For purchases/returns (with sale), we filter by sold_by
  final response =
      await Supabase.instance.client.from('gallon_transactions').select('''
      *,
      product:products!gallon_transactions_product_id_fkey(name),
      seller_profile:profiles!gallon_transactions_seller_id_fkey(first_name, last_name),
      sale:sales(
        id,
        sold_by,
          seller_profile:profiles!sales_sold_by_fkey(first_name, last_name),
          product:products!fk_sales_product(name)
      )
      ''').order('created_at', ascending: false);

  // Filter transactions for current user
  final filteredResponse = response.where((tx) {
    // For deposits (no sale), include them (they're created by current user)
    if (tx['sale_id'] == null) return true;

    // For transactions with sales, check if sale was by current user
    final sale = tx['sale'] as Map<String, dynamic>?;
    return sale != null && sale['sold_by'] == userId;
  }).toList();

  // Extract all unique customer IDs
  final customerIds = filteredResponse
      .map((t) => t['customer_id'] as String?)
      .where((id) => id != null)
      .toSet()
      .toList();

  // Fetch all customers in one query
  final customersMap = <String, String>{};
  if (customerIds.isNotEmpty) {
    final customerList = await Supabase.instance.client
        .from('customers')
        .select('id, name')
        .inFilter('id', customerIds);

    customersMap.addAll(
        {for (var c in customerList) c['id'] as String: c['name'] as String});
  }

  // Map the data with proper customer names and seller info
  final mapped = filteredResponse.map((e) {
    final customerId = e['customer_id'] as String?;
    final customerName =
        customerId != null ? (customersMap[customerId] ?? customerId) : 'مجهول';

    // Extract seller info from sale
    final sale = e['sale'] as Map<String, dynamic>?;
    String? sellerName;
    String? sellerId;

    if (sale != null) {
      sellerId = sale['sold_by'] as String?;
      final profile = sale['seller_profile'] as Map<String, dynamic>?;
      if (profile != null) {
        final firstName = profile['first_name'] as String? ?? '';
        final lastName = profile['last_name'] as String? ?? '';
        sellerName = '$firstName $lastName'.trim();
      }
    }

    // For standalone transactions (deposits), get seller info from the transaction's seller profile
    if (sellerId == null && e['seller_id'] != null) {
      sellerId = e['seller_id'] as String?;
    }
    if (sellerName == null) {
      // Try to get seller name from standalone transaction's seller profile
      final standaloneSellerProfile =
          e['seller_profile'] as Map<String, dynamic>?;
      if (standaloneSellerProfile != null) {
        final firstName =
            standaloneSellerProfile['first_name'] as String? ?? '';
        final lastName = standaloneSellerProfile['last_name'] as String? ?? '';
        sellerName = '$firstName $lastName'.trim();
      }
    }

    // Debug: Log seller info extraction
    if (e['transaction_type'] == 'deposit' && sellerName == null) {
      print('DEBUG: Deposit transaction ${e['id']} has no seller name');
      print('  - seller_id: ${e['seller_id']}');
      print('  - seller_profile: ${e['seller_profile']}');
      print('  - sale: ${e['sale']}');
    }

    // Debug: Log seller info extraction for return transactions
    if (e['transaction_type'] == 'return' && sellerName == null) {
      print('DEBUG: Return transaction ${e['id']} has no seller name');
      print('  - seller_id: ${e['seller_id']}');
      print('  - seller_profile: ${e['seller_profile']}');
      print('  - sale: ${e['sale']}');
      print('  - transaction_type: ${e['transaction_type']}');
    }

    // Extract product info - prioritize direct product relationship for standalone transactions
    final product = e['product'] as Map<String, dynamic>?;
    String? productName;
    if (product != null) {
      productName = product['name'] as String?;
    } else if (sale != null) {
      // Fallback to product info from sale
      final saleProduct = sale['product'] as Map<String, dynamic>?;
      if (saleProduct != null) {
        productName = saleProduct['name'] as String?;
      }
    }

    // Add customer info to the map
    e['customer'] = {'name': customerName};
    e['seller_id'] = sellerId;
    e['seller_name'] = sellerName;
    e['product_name'] = productName;

    return GallonTransaction.fromMap(e);
  }).toList();

  // Debug output
  if (mapped.isNotEmpty) {
    print('Gallon transactions loaded: ${mapped.length}');
    print('First transaction customer: ${mapped.first.customerName}');
    print('First transaction seller: ${mapped.first.sellerName}');
  }

  return mapped;
});

// Provider for managers/owners to see all gallon transactions
final allGallonTransactionsProvider =
    FutureProvider.autoDispose<List<GallonTransaction>>((ref) async {
  // Fetch all gallon transactions with sales and product joins
  // Try with the expected foreign key constraint name first
  final response =
      await Supabase.instance.client.from('gallon_transactions').select('''
      *,
      product:products!gallon_transactions_product_id_fkey(name),
      seller_profile:profiles!gallon_transactions_seller_id_fkey(first_name, last_name),
      sale:sales(
        id,
        sold_by,
          seller_profile:profiles!sales_sold_by_fkey(first_name, last_name),
          product:products!fk_sales_product(name)
      )
      ''').order('created_at', ascending: false);

  // Extract all unique customer IDs
  final customerIds = response
      .map((t) => t['customer_id'] as String?)
      .where((id) => id != null)
      .toSet()
      .toList();

  // Fetch all customers with location info in one query
  final customersMap = <String, Map<String, dynamic>>{};
  if (customerIds.isNotEmpty) {
    final customerList =
        await Supabase.instance.client.from('customers').select('''
          id, 
          name, 
          location:locations(name)
        ''').inFilter('id', customerIds);

    customersMap.addAll({
      for (var c in customerList)
        c['id'] as String: {
          'name': c['name'] as String,
          'location': c['location']?['name'] as String? ?? 'Unknown'
        }
    });
  }

  // Map the data with proper customer names and seller info
  final mapped = response.map((e) {
    final customerId = e['customer_id'] as String?;
    final customerData = customerId != null ? customersMap[customerId] : null;
    final customerName = customerData?['name'] ?? customerId ?? 'مجهول';
    final customerLocation = customerData?['location'] ?? 'Unknown';

    // Extract seller info from sale
    final sale = e['sale'] as Map<String, dynamic>?;
    String? sellerName;
    String? sellerId;

    if (sale != null) {
      sellerId = sale['sold_by'] as String?;
      final profile = sale['seller_profile'] as Map<String, dynamic>?;
      if (profile != null) {
        final firstName = profile['first_name'] as String? ?? '';
        final lastName = profile['last_name'] as String? ?? '';
        sellerName = '$firstName $lastName'.trim();
      }
    }

    // For standalone transactions (deposits), get seller info from the transaction's seller profile
    if (sellerId == null && e['seller_id'] != null) {
      sellerId = e['seller_id'] as String?;
    }
    if (sellerName == null) {
      // Try to get seller name from standalone transaction's seller profile
      final standaloneSellerProfile =
          e['seller_profile'] as Map<String, dynamic>?;
      if (standaloneSellerProfile != null) {
        final firstName =
            standaloneSellerProfile['first_name'] as String? ?? '';
        final lastName = standaloneSellerProfile['last_name'] as String? ?? '';
        sellerName = '$firstName $lastName'.trim();
      }
    }

    // Debug: Log seller info extraction
    if (e['transaction_type'] == 'deposit' && sellerName == null) {
      print('DEBUG: Deposit transaction ${e['id']} has no seller name');
      print('  - seller_id: ${e['seller_id']}');
      print('  - seller_profile: ${e['seller_profile']}');
      print('  - sale: ${e['sale']}');
    }

    // Debug: Log seller info extraction for return transactions
    if (e['transaction_type'] == 'return' && sellerName == null) {
      print('DEBUG: Return transaction ${e['id']} has no seller name');
      print('  - seller_id: ${e['seller_id']}');
      print('  - seller_profile: ${e['seller_profile']}');
      print('  - sale: ${e['sale']}');
      print('  - transaction_type: ${e['transaction_type']}');
    }

    // Extract product info - prioritize direct product relationship for standalone transactions
    final product = e['product'] as Map<String, dynamic>?;
    String? productName;
    if (product != null) {
      productName = product['name'] as String?;
    } else if (sale != null) {
      // Fallback to product info from sale
      final saleProduct = sale['product'] as Map<String, dynamic>?;
      if (saleProduct != null) {
        productName = saleProduct['name'] as String?;
      }
    }

    // Add customer info to the map
    e['customer'] = {'name': customerName, 'location': customerLocation};
    e['seller_id'] = sellerId;
    e['seller_name'] = sellerName;
    e['product_name'] = productName;

    return GallonTransaction.fromMap(e);
  }).toList();

  // Debug output
  if (mapped.isNotEmpty) {
    print('All gallon transactions loaded: ${mapped.length}');
    print('First transaction customer: ${mapped.first.customerName}');
    print('First transaction seller: ${mapped.first.sellerName}');
    print('First transaction seller ID: ${mapped.first.sellerId}');

    // Debug: Check return transactions specifically
    final returnTransactions =
        mapped.where((t) => t.transactionType == 'return').toList();
    print('Return transactions count: ${returnTransactions.length}');
    for (final rt in returnTransactions) {
      print('Return transaction: ${rt.id}');
      print('  - seller_id: ${rt.sellerId}');
      print('  - seller_name: ${rt.sellerName}');
      print('  - transaction_type: ${rt.transactionType}');
    }
  }

  return mapped;
});
