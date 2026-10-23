import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final ownerNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final response = await Supabase.instance.client
      .from('profiles')
      .select('user_id, first_name, last_name')
      .eq('role', 'owner');

  final Map<String, String> map = {};
  for (final row in response) {
    final id = row['user_id'] as String?;
    final firstName = row['first_name'] as String? ?? '';
    final lastName = row['last_name'] as String? ?? '';
    if (id != null) {
      map[id] = '$firstName $lastName'.trim();
    }
  }

  return map;
});

// Provider for managers and distributors only
final managerDistributorNamesProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final response = await Supabase.instance.client
      .from('profiles')
      .select('user_id, first_name, last_name, role')
      .inFilter('role', ['manager', 'distributor']);

  final Map<String, String> map = {};
  for (final row in response) {
    final id = row['user_id'] as String?;
    final firstName = row['first_name'] as String? ?? '';
    final lastName = row['last_name'] as String? ?? '';
    final role = row['role'] as String? ?? '';
    if (id != null) {
      map[id] = '$firstName $lastName ($role)'.trim();
    }
  }

  return map;
});
