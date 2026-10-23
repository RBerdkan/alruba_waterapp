// lib/features/presentation/owner/owner_home_page.dart

import 'package:alruba_waterapp/features/presentation/distrubutor/sale_form.dart';
import 'package:alruba_waterapp/features/presentation/distrubutor/sales/widgets/sales_queue_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/customer_details_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/manager_cashflow_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/admin_profiles_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/owner_unpaid_sale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alruba_waterapp/features/presentation/logout_button.dart';
import 'package:alruba_waterapp/features/presentation/manager/Gallon_transaction_status_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/manager_dashboard_page.dart';

import 'package:alruba_waterapp/features/presentation/owner/expenses/expense_list_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/owner_dashboard_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/owner_management_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/products/products_list.dart';
import 'package:alruba_waterapp/services/supabase_service.dart';

/*=============================================================================
 *  الصفحة الرئيسية للمالك
 *============================================================================*/
class OwnerHomePage extends ConsumerStatefulWidget {
  const OwnerHomePage({super.key});

  @override
  ConsumerState<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends ConsumerState<OwnerHomePage> {
  /* -------------------------------------------------------------------------
   * عناصر التنقل السفلي (ملاحة قائمة على الفهرس)
   * -----------------------------------------------------------------------*/
  int _currentIndex = 0;
  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.inventory_2_outlined, label: 'المنتجات'),
    _NavItem(icon: Icons.receipt_long_outlined, label: 'المصروفات'),
    _NavItem(icon: Icons.shopping_bag_outlined, label: 'المبيعات'),
    _NavItem(icon: Icons.local_drink_outlined, label: 'البراميل'),
    _NavItem(icon: Icons.sell_outlined, label: 'الأرباح'),
  ];

  final List<Widget> _pages = [
    const ProductListPage(),
    const ExpensesScreen(),
    const ManagerDashboardPage(),
    const GallonTransactionStatusPage(),
    const OwnerDashboardPage(),
  ];

  /* -------------------------------------------------------------------------
   * عناصر قائمة الجانبية (شاشات مستقلة تماماً)
   * -----------------------------------------------------------------------*/
  final List<_DrawerEntry> _drawerItems = const [
    _DrawerEntry(
        icon: Icons.add_circle_outline_sharp,
        label: 'إجراء مبيعات',
        page: MakeSalePage()),
    _DrawerEntry(
        icon: Icons.query_builder,
        label: 'قائمة الانتظار للمبيعات',
        page: SalesQueuePage()),
    _DrawerEntry(
        icon: Icons.person,
        label: 'الملفات الشخصية',
        page: AdminProfilesPage()),
    _DrawerEntry(
        icon: Icons.money_off,
        label: 'طلبات غير مدفوعة',
        page: OwnerUnpaidSalesPage()),
    _DrawerEntry(
        icon: Icons.money, label: 'التدفق النقدي', page: ManagerCashflowPage()),
    _DrawerEntry(
        icon: Icons.group, label: 'العملاء', page: CustomerDetailsPage()),

    //_DrawerEntry(icon: Icons.dashboard, label: 'لوحة تحكم العمال', page: OwnerDashboardPage2()),
  ];

  /* -------------------------------------------------------------------------
   * طبقة تحميل بيانات
   * -----------------------------------------------------------------------*/
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchInitialData());
  }

  Future<void> _fetchInitialData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await Future.wait([
        SupabaseService.client.from('products').select('*'),
        SupabaseService.client.from('locations').select('*'),
      ]);
    } catch (e) {
      _showErrorSnackbar('فشل تحميل البيانات: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackbar(String message) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      });

  /* -------------------------------------------------------------------------
   * بناء الواجهة
   * -----------------------------------------------------------------------*/
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      /* ---------------- شريط التطبيق ---------------- */
      appBar: AppBar(
        title: const Text('الصفحة الرئيسية للمالك',
            style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),

      /* ---------------- القائمة الجانبية ---------------- */
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text('لوحة المالك',
                    style: TextStyle(color: cs.onPrimary, fontSize: 20)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _drawerItems.length,
                itemBuilder: (_, i) {
                  final d = _drawerItems[i];
                  return ListTile(
                    leading: Icon(d.icon),
                    title: Text(d.label),
                    onTap: () {
                      Navigator.pop(context); // إغلاق القائمة الجانبية
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => d.page),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 0),
            const Padding(
              padding: EdgeInsets.all(12),
              child: LogoutButton(fullWidth: true),
            ),
          ],
        ),
      ),

      /* ---------------- جسم الصفحة مع طبقة التحميل ---------------- */
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _pages),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              ),
            ),
        ],
      ),

      /* ---------------- شريط التنقل السفلي ---------------- */
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: cs.surface,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurface.withValues(alpha: 0.6),
        showUnselectedLabels: true,
        elevation: 8,
        items: [
          for (final item in _navItems)
            BottomNavigationBarItem(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------
 * هياكل بيانات صغيرة
 * -----------------------------------------------------------------------*/
class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _DrawerEntry {
  final IconData icon;
  final String label;
  final Widget page;
  const _DrawerEntry(
      {required this.icon, required this.label, required this.page});
}
