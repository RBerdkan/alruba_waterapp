import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment.dart';

final paymentsTodayProvider =
    FutureProvider.autoDispose<List<Payment>>((ref) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final rows = await Supabase.instance.client
      .from('payments')
      .select()
      .gte('payment_date', start.toIso8601String())
      .lte('payment_date', end.toIso8601String());

  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map((m) => Payment.fromMap(m))
      .toList();
});
