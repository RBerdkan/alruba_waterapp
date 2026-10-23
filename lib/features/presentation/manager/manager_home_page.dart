// lib/features/presentation/manager/manager_home_page.dart

import 'package:alruba_waterapp/features/presentation/logout_button.dart';
import 'package:alruba_waterapp/features/presentation/owner/owner_unpaid_sale.dart';
import 'package:alruba_waterapp/providers/manager_slaes_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sale_form.dart';
import 'package:alruba_waterapp/features/presentation/manager/manager_cashflow_page.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/sales_queue_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/gallon_transaction_status_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/customer_details_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/manager_dashboard_page.dart';

const _primaryGradient = LinearGradient(
  colors: [Color(0xFF00695C), Color(0xFF26A69A)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class ManagerHomePage extends ConsumerStatefulWidget {
  const ManagerHomePage({super.key});

  @override
  ConsumerState<ManagerHomePage> createState() => _ManagerHomePageState();
}

class _ManagerHomePageState extends ConsumerState<ManagerHomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const ManagerDashboardPage(),
    const SalesQueuePage(),
    const GallonTransactionStatusPage(),
    const CustomerDetailsPage(),
    const ManagerCashflowPage(),
  ];

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    _NavItem(icon: Icons.queue_outlined, label: 'Queue'),
    _NavItem(icon: Icons.local_drink_outlined, label: 'Gallon'),
    _NavItem(icon: Icons.group_outlined, label: 'Customers'),
    _NavItem(icon: Icons.attach_money_outlined, label: 'Cashflow'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: _primaryGradient)),
        elevation: 2,
        actions: [
          const LogoutButton(fullWidth: false),
          const SizedBox(width: 10),
          const Text('Manager',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20)),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.money_off, color: Colors.white),
            tooltip: 'Unpaid customers',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const OwnerUnpaidSalesPage(),
              ));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: KeyedSubtree(
            key: ValueKey<int>(_currentIndex),
            child: _pages[_currentIndex],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const MakeSalePage()),
          );
          if (created == true) ref.invalidate(managerSalesProvider);
        },
        backgroundColor: const Color(0xFF00695C),
        elevation: 6,
        tooltip: 'Add New Sale',
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.colorScheme.surface,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        showUnselectedLabels: true,
        elevation: 8,
        items: _navItems.map((item) {
          final index = _navItems.indexOf(item);
          final isSelected = index == _currentIndex;
          return BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, size: 24),
            ),
            label: item.label,
          );
        }).toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
