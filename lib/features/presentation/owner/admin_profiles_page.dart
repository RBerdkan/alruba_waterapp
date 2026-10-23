import 'package:alruba_waterapp/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final profilesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final response = await SupabaseService.client
        .from('profiles')
        .select('*')
        .order('created_at', ascending: false);

    // Debug logging
    print('Profiles loaded: ${response.length}');
    for (final profile in response) {
      print(
          'Profile: ${profile['first_name']} ${profile['last_name']} - Role: ${profile['role']}');
    }

    return response;
  } catch (e) {
    throw Exception('Failed to load profiles: ${e.toString()}');
  }
});

class AdminProfilesPage extends ConsumerStatefulWidget {
  const AdminProfilesPage({super.key});

  @override
  ConsumerState<AdminProfilesPage> createState() => _AdminProfilesPageState();
}

class _AdminProfilesPageState extends ConsumerState<AdminProfilesPage> {
  final Map<String, String> _currentRoles = {};
  final Map<String, bool> _updatingStates = {};
  bool _isCurrentUserOwner = false;
  bool _loadingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentUserRole();
  }

  Future<void> _checkCurrentUserRole() async {
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null) {
      setState(() => _loadingPermissions = false);
      return;
    }

    try {
      final response = await SupabaseService.client
          .from('profiles')
          .select('role')
          .eq('user_id', currentUser.id)
          .single();
      final role = response['role'] as String?;
      _isCurrentUserOwner = role == 'owner';
      print('Current user role: $role, isOwner: $_isCurrentUserOwner');
    } finally {
      setState(() => _loadingPermissions = false);
    }
  }

  Future<void> _updateRole(String userId, String newRole) async {
    if (!_isCurrentUserOwner) return;
    setState(() => _updatingStates[userId] = true);

    try {
      await SupabaseService.client
          .from('profiles')
          .update({'role': newRole})
          .eq('user_id', userId)
          .select();

      _currentRoles[userId] = newRole;
      ref.invalidate(profilesProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update role: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _updatingStates[userId] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(profilesProvider),
          ),
        ],
      ),
      body: _loadingPermissions
          ? const Center(child: CircularProgressIndicator())
          : profilesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error: ${err.toString()}',
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(profilesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (profiles) {
                // Debug logging for roles
                final roleCounts = <String, int>{};
                for (final profile in profiles) {
                  final role = profile['role'] ?? 'unknown';
                  roleCounts[role] = (roleCounts[role] ?? 0) + 1;
                }
                print('Role distribution: $roleCounts');

                if (_currentRoles.isEmpty) {
                  for (final profile in profiles) {
                    final userId = profile['user_id'] ?? '';
                    _currentRoles[userId] = profile['role'] ?? 'viewer';
                  }
                }

                if (profiles.isEmpty) {
                  return const Center(child: Text('No users found'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final userId = profile['user_id'] ?? '';
                    final role = _currentRoles[userId] ?? 'viewer';
                    final isUpdating = _updatingStates[userId] ?? false;

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.teal.shade100,
                              child: Text(
                                (profile['first_name'] ?? 'U')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${profile['first_name'] ?? 'Unknown'} ${profile['last_name'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Created: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(profile['created_at']).toLocal())}',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            if (_isCurrentUserOwner)
                              _RoleDropdown(
                                currentRole: role,
                                isUpdating: isUpdating,
                                onRoleChanged: (newRole) =>
                                    _updateRole(userId, newRole),
                              )
                            else
                              Chip(
                                label: Text(role.toUpperCase()),
                                backgroundColor: _getRoleColor(role),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return Colors.deepPurple.shade100;
      case 'manager':
        return Colors.blue.shade100;
      case 'distributor':
        return Colors.green.shade100;
      case 'viewer':
        return Colors.grey.shade300;
      default:
        return Colors.orange.shade100;
    }
  }
}

class _RoleDropdown extends StatelessWidget {
  final String currentRole;
  final bool isUpdating;
  final Function(String) onRoleChanged;

  const _RoleDropdown({
    required this.currentRole,
    required this.isUpdating,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: currentRole,
      borderRadius: BorderRadius.circular(12),
      onChanged: isUpdating
          ? null
          : (value) {
              if (value != null && value != currentRole) {
                onRoleChanged(value);
              }
            },
      items: const [
        DropdownMenuItem(value: 'owner', child: Text('Owner')),
        DropdownMenuItem(value: 'manager', child: Text('Manager')),
        DropdownMenuItem(value: 'distributor', child: Text('Distributor')),
        DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
      ],
      underline: const SizedBox.shrink(),
      icon: isUpdating
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.arrow_drop_down),
    );
  }
}
