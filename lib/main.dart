import 'package:alruba_waterapp/features/presentation/distrubutor/distributor_home_page.dart';
import 'package:alruba_waterapp/features/presentation/login_page.dart';
import 'package:alruba_waterapp/features/presentation/manager/manager_home_page.dart';
import 'package:alruba_waterapp/features/presentation/owner/owner_home_page.dart';
import 'package:alruba_waterapp/features/presentation/signup_page.dart';
import 'package:alruba_waterapp/models/customer.dart';
import 'package:alruba_waterapp/models/offline_gallon_transaction.dart';
import 'package:alruba_waterapp/models/offline_sale.dart';
import 'package:alruba_waterapp/viewer_homepage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'constants/app_colors.dart';
import 'constants/app_text_styles.dart';
import 'providers/auth_provider.dart';
import 'providers/role_provider.dart';
import 'services/supabase_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar', null); // Initialize Arabic locale data
  await dotenv.load(); // 👈 Load .env file

  await Hive.initFlutter();
  Hive.registerAdapter(OfflineGallonTransactionAdapter());
  Hive.registerAdapter(CustomerAdapter());
  Hive.registerAdapter(OfflineSaleAdapter());
  await Hive.openBox<OfflineSale>('offline_sales');
  await Hive.openBox<OfflineGallonTransaction>('offline_gallon_transactions');

  await SupabaseService.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(roleSyncProvider); // Initialize role syncing

    return MaterialApp.router(
      title: 'Water Distribution',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          headlineMedium: AppTextStyles.headline,
          bodyLarge: AppTextStyles.body,
        ),
      ),
      locale: const Locale('ar'), // Arabic language
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
    );
  }
}

final roleSyncProvider = Provider((ref) {
  final supabase = SupabaseService.client;
  supabase.auth.onAuthStateChange.listen((event) {
    if (event.session?.user != null) {
      ref.invalidate(roleProvider); // Force role refresh on auth change
    }
  });
});

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull != null;
      final path = state.uri.path;

      debugPrint('Redirect check: Auth=$isAuthenticated, Path=$path');
      debugPrint(
          'Current user: ${SupabaseService.client.auth.currentUser?.id}');

      if (!isAuthenticated && path != '/login' && path != '/signup') {
        return '/login';
      }
      if (isAuthenticated && (path == '/login' || path == '/signup')) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const RoleBasedWrapper(),
      ),
    ],
  );
});

class RoleBasedWrapper extends ConsumerWidget {
  const RoleBasedWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(roleProvider);

    // Listen for auth changes to refresh role
    ref.listen(authStateProvider, (_, state) {
      if (state.valueOrNull != null) {
        ref.invalidate(roleProvider);
      }
    });

    return roleAsync.when(
      data: (role) {
        final normalizedRole = role.trim().toLowerCase();
        debugPrint('ROLE RESOLVED: $normalizedRole');

        if (normalizedRole.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(authProvider.notifier).signOut();
            context.go('/login');
          });
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return _buildLayout(
            context, ref, normalizedRole); // Pass context and ref
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) {
        debugPrint('Role error: $error\n$stack');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(authProvider.notifier).signOut();
          context.go('/login');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }

  // FIXED: Added context and ref parameters
  Widget _buildLayout(BuildContext context, WidgetRef ref, String role) {
    switch (role) {
      case 'owner':
        return const OwnerHomePage();
      case 'manager':
        return const ManagerHomePage();
      case 'distributor':
        return const DistributorHomePage();
      case 'viewer':
        debugPrint('Navigating to ViewerWaitingPage');
        return const ViewerWaitingPage();
      default:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Invalid role: $role',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    ref.read(authProvider.notifier).signOut();
                    context.go('/login');
                  },
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        );
    }
  }
}
