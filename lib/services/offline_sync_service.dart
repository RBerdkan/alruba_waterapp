//import 'dart:convert';                // for pretty JSON dumps
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';
import '../models/offline_sale.dart';
import '../models/offline_gallon_transaction.dart';

class OfflineSyncService {
  static const String _offlineSalesBox = 'offline_sales';
  static const String _localCustomersBox = 'offline_customers';
  static const String _offlineGallonTxBox = 'offline_gallon_transactions';

  final SupabaseClient client = Supabase.instance.client;

  /*───────────────────────────────────────────────────────────*/
  /*  PUBLIC ENTRY                                            */
  /*───────────────────────────────────────────────────────────*/
  Future<void> syncOfflineData() async {
    debugPrint('[OfflineSync] starting sync …');
    await _syncLocalCustomers();
    await _syncOfflineSales();
    await _syncGallonTransactions();

    debugPrint('[OfflineSync] finished.');
  }

  /*───────────────────────────────────────────────────────────*/
  /*  STEP 1 : customers                                      */
  /*───────────────────────────────────────────────────────────*/
  Future<void> _syncLocalCustomers() async {
    final box = await Hive.openBox<Customer>(_localCustomersBox);

    for (final key in box.keys) {
      final c = box.get(key);
      if (c == null) continue;

      try {
        final exists = await client
            .from('customers')
            .select('id')
            .eq('phone', c.phone)
            .maybeSingle();

        if (exists == null || exists.isEmpty) {
          final inserted = await client
              .from('customers')
              .insert({
                'name': c.name,
                'phone': c.phone,
                'type': c.type,
                'assigned_to': client.auth.currentUser?.id,
                'location_id': c.locationId,
                'precise_location': c.preciseLocation,
              })
              .select('id')
              .maybeSingle();

          if (inserted != null && inserted.isNotEmpty) {
            c.remoteId = inserted['id'] as String;
            await box.delete(key);
          }
        } else {
          c.remoteId = exists['id'] as String;
          await box.delete(key);
        }
      } catch (e) {
        debugPrint('[OfflineSync] customer-sync error: $e');
      }
    }
  }

  /*───────────────────────────────────────────────────────────*/
  /*  STEP 2 : sales                                          */
  /*───────────────────────────────────────────────────────────*/
  Future<void> _syncOfflineSales() async {
    final box = await Hive.openBox<OfflineSale>(_offlineSalesBox);
    final gallonTxBox =
        await Hive.openBox<OfflineGallonTransaction>(_offlineGallonTxBox);

    final Map<String, String> localToRemoteSaleIds = {};

    for (final key in box.keys) {
      final sale = box.get(key);
      if (sale == null) continue;

      try {
        // 1. Handle customer first
        if (sale.isNewCustomer && (sale.existingCustomerId?.isEmpty ?? true)) {
          await _attachOrCreateCustomerForSale(sale);
        }

        // 2. Insert sale and get generated ID
        final createdAtString = sale.createdAt.toUtc().toIso8601String();
        debugPrint(
            '[OfflineSync] Sending sale with created_at: $createdAtString');
        debugPrint('[OfflineSync] Original sale.createdAt: ${sale.createdAt}');
        debugPrint('[OfflineSync] UTC conversion: ${sale.createdAt.toUtc()}');

        final resp = await client
            .from('sales')
            .insert({
              'customer_id': sale.existingCustomerId!,
              'product_id': sale.productId,
              'quantity': sale.quantity,
              'price_per_unit': sale.pricePerUnit,
              'payment_status': sale.paymentStatus.toLowerCase(),
              'sold_by': sale.soldBy,
              'location_id': sale.locationId,
              'created_at': createdAtString,
              'sale_type': sale.saleType ?? 'normal',
              'amount_paid': sale.amountPaid,
            })
            .select('id')
            .single();

        if (resp.isNotEmpty) {
          final remoteSaleId = resp['id'] as String;

          // Insert payment record if sale is paid or partial and amountPaid > 0
          if ((sale.paymentStatus.toLowerCase() == 'paid' ||
                  sale.paymentStatus.toLowerCase() == 'partial') &&
              sale.amountPaid > 0) {
            final now = DateTime.now();
            final paymentDate = DateTime(now.year, now.month, now.day, now.hour,
                    now.minute, now.second)
                .toUtc()
                .toIso8601String();
            await client.from('payments').insert({
              'sale_id': remoteSaleId,
              'amount': sale.amountPaid,
              'payment_date': paymentDate,
              'note': 'دفع عند إنشاء البيع (مزامنة أوفلاين)',
            });
          }

          localToRemoteSaleIds[sale.localSaleId!] = remoteSaleId;
          // 3. Update related gallon transactions
          final relatedTransactions = gallonTxBox.values
              .where((tx) => tx.saleLocalId == sale.localSaleId)
              .toList();

          for (final tx in relatedTransactions) {
            // Create NEW instance with updated data
            final updatedTx = OfflineGallonTransaction(
              localTxId: tx.localTxId, // Keep original key
              saleLocalId: tx.saleLocalId,
              customerId: tx.customerId,
              productId: tx.productId,
              quantity: tx.quantity,
              transactionType: tx.transactionType,
              status: tx.status,
              amount: tx.amount,
              saleId: remoteSaleId, // Updated field
              createdAt: tx.createdAt,
            );

            // Replace old entry with new instance
            await gallonTxBox.put(updatedTx.localTxId, updatedTx);
          }

          // 4. Delete only after processing transactions
          //await box.delete(key);
          debugPrint('[OfflineSync] sale synced → $remoteSaleId');
        }
      } catch (e) {
        debugPrint('[OfflineSync] sale-sync error: $e');
      }
    }
  }

  Future<void> _maybeDeleteSaleAfterTxSync(
      Box<OfflineSale> salesBox, String saleLocalId) async {
    final txBox =
        await Hive.openBox<OfflineGallonTransaction>(_offlineGallonTxBox);

    final stillPending =
        txBox.values.any((tx) => tx.saleLocalId == saleLocalId);
    if (!stillPending) {
      final saleKey = salesBox.keys.firstWhere(
        (k) => salesBox.get(k)?.localSaleId == saleLocalId,
        orElse: () => null,
      );
      if (saleKey != null) {
        await salesBox.delete(saleKey);
        debugPrint(
            '[OfflineSync] Cleaned sale after all related gallon-tx synced.');
      }
    }
  }

  /* helper to guarantee customer id */
  Future<void> _attachOrCreateCustomerForSale(OfflineSale sale) async {
    final phone = sale.newCustomerPhone;
    if (phone == null || phone.isEmpty) return;

    final found = await client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    if (found != null && found.isNotEmpty) {
      sale.existingCustomerId = (found['id'] as String?) ?? '';
      return;
    }

    final inserted = await client
        .from('customers')
        .insert({
          'name': sale.customerName,
          'phone': phone,
          'type': 'regular',
          'assigned_to': client.auth.currentUser?.id,
          'location_id': sale.locationId,
          //'precise_location': sale.preciseLocation,
        })
        .select('id')
        .maybeSingle();

    if (inserted != null && inserted.isNotEmpty) {
      sale.existingCustomerId = inserted['id'] as String? ?? '';
    }
  }

  /*───────────────────────────────────────────────────────────*/
  /*  STEP 3 : gallon transactions                            */
  /*───────────────────────────────────────────────────────────*/
  Future<void> _syncGallonTransactions() async {
    // First, ensure all customers are synced
    await _syncLocalCustomers();
    final box =
        await Hive.openBox<OfflineGallonTransaction>(_offlineGallonTxBox);

    for (final key in box.keys) {
      final tx = box.get(key);
      if (tx == null) continue;

      try {
        debugPrint('[OfflineSync] Processing gallon tx: ${tx.localTxId}');
        debugPrint('[OfflineSync] - Type: ${tx.transactionType}');
        debugPrint('[OfflineSync] - Customer ID: ${tx.customerId}');
        debugPrint('[OfflineSync] - Sale ID: ${tx.saleId}');

        // Validate required fields - customerId is always required, saleId only for purchase transactions
        if ((tx.customerId?.isEmpty ?? true)) {
          debugPrint(
              '[OfflineSync] Skipping invalid gallon tx (no customer): ${tx.localTxId}');
          continue;
        }

        // For purchase transactions, saleId is required. For deposits and returns, it's optional
        if (tx.transactionType == 'purchase' && (tx.saleId?.isEmpty ?? true)) {
          debugPrint(
              '[OfflineSync] Skipping invalid purchase tx (no sale): ${tx.localTxId}');
          continue;
        }

        // Ensure customer exists in database (for new customers created during offline transactions)
        String finalCustomerId = tx.customerId!;
        if (tx.customerId!.length > 20) {
          // Likely a UUID, check if it exists
          final customerExists = await client
              .from('customers')
              .select('id')
              .eq('id', tx.customerId!)
              .maybeSingle();

          if (customerExists == null) {
            debugPrint(
                '[OfflineSync] Customer ${tx.customerId} not found, skipping transaction');
            continue;
          }
        }

        // Prepare insert data - only include sale_id if it exists
        final createdAtString = tx.createdAt.toIso8601String();
        debugPrint(
            '[OfflineSync] Sending gallon tx with created_at: $createdAtString');
        debugPrint('[OfflineSync] Original tx.createdAt: ${tx.createdAt}');

        final insertData = {
          'customer_id': finalCustomerId,
          'product_id': tx.productId,
          'quantity': tx.quantity,
          'transaction_type': tx.transactionType,
          'status': tx.status,
          'amount': tx.amount,
          'created_at': createdAtString,
          // Add seller information for standalone transactions
          'seller_id': client.auth.currentUser?.id,
        };

        // Only add sale_id if it exists (for purchase transactions)
        if (tx.saleId != null && tx.saleId!.isNotEmpty) {
          insertData['sale_id'] = tx.saleId;
        }

        final resp = await client
            .from('gallon_transactions')
            .insert(insertData)
            .select('id')
            .single();

        if (resp.isNotEmpty) {
          await box.delete(key);
          debugPrint('[OfflineSync] gallon-tx synced → ${resp['id']}');
        }
        // After syncing gallon transaction, check if we can now delete its related sale
        final salesBox = await Hive.openBox<OfflineSale>(_offlineSalesBox);
        await _maybeDeleteSaleAfterTxSync(salesBox, tx.saleLocalId);
      } catch (e) {
        debugPrint('[OfflineSync] gallon-tx error: $e');
        // Handle foreign key errors specifically
        if (e is PostgrestException && e.code == '23503') {
          debugPrint('''
            Missing reference for transaction ${tx.localTxId}.
            Sale ID: ${tx.saleId}
            Customer ID: ${tx.customerId}
          ''');
        }
      }
    }
  }
}
