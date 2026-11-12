import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/main_shell_screen.dart';
import '../../features/home/presentation/settings_and_backup_screen.dart';
import '../../features/home/presentation/user_info_screen.dart';
import '../../features/home/presentation/recent_operations_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/suppliers/presentation/supplier_detail_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShellScreen(),
      ),
      GoRoute(
        path: '/user-info',
        builder: (context, state) => const UserInfoScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsAndBackupScreen(),
      ),
      GoRoute(
        path: '/recent-operations',
        builder: (context, state) => const RecentOperationsScreen(),
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) {
          final initialTab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return ExpensesScreen(initialTabIndex: initialTab);
        },
      ),
      GoRoute(
        path: '/supplier/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return SupplierDetailScreen(supplierId: id, initialTabIndex: tab);
        },
      ),
      GoRoute(
        path: '/customer/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return CustomerDetailScreen(customerId: id);
        },
      ),
    ],
  );
});
