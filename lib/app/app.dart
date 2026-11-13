import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/expenses/presentation/expenses_screen.dart';
import '../features/custom_fields/presentation/custom_fields_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/organizer/presentation/organizer_screen.dart';
import '../features/settings/presentation/notification_diagnostics_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/today/presentation/today_screen.dart';
import '../features/tracking/presentation/tracking_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import 'providers.dart';

class MutabaatiApp extends ConsumerWidget {
  const MutabaatiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'متابعتي',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: _router,
  );
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const AppGate()),
    GoRoute(path: '/home', builder: (_, _) => const AppShell(index: 0)),
    GoRoute(path: '/tracking', builder: (_, _) => const AppShell(index: 1)),
    GoRoute(path: '/expenses', builder: (_, _) => const AppShell(index: 2)),
    GoRoute(path: '/organizer', builder: (_, _) => const AppShell(index: 3)),
    GoRoute(path: '/reports', builder: (_, _) => const AppShell(index: 4)),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/custom-fields',
      builder: (_, _) => const CustomFieldsScreen(),
    ),
    GoRoute(
      path: '/notification-diagnostics',
      builder: (_, _) => const NotificationDiagnosticsScreen(),
    ),
    GoRoute(
      path: '/backup',
      builder: (_, _) => const BackupScreen(),
    ),
  ],
);

class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(appSettingsProvider)
      .when(
        loading: () => const _LoadingScreen(),
        error: (_, _) => const _StartupErrorScreen(),
        data: (settings) => settings.isOnboarded
            ? const AppShell(index: 0)
            : const OnboardingScreen(),
      );
}

class AppShell extends StatelessWidget {
  const AppShell({required this.index, super.key});

  final int index;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.today_outlined),
      selectedIcon: Icon(Icons.today),
      label: 'اليوم',
    ),
    NavigationDestination(
      icon: Icon(Icons.checklist_outlined),
      selectedIcon: Icon(Icons.checklist),
      label: 'المتابعة',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'المصاريف',
    ),
    NavigationDestination(
      icon: Icon(Icons.event_note_outlined),
      selectedIcon: Icon(Icons.event_note),
      label: 'المنظم',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'التقارير',
    ),
  ];

  static const _titles = [
    'اليوم',
    'المتابعة',
    'المصاريف',
    'المنظم',
    'التقارير',
  ];
  static const _paths = [
    '/home',
    '/tracking',
    '/expenses',
    '/organizer',
    '/reports',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayScreen(),
      const TrackingScreen(),
      const ExpensesScreen(),
      const OrganizerScreen(),
      const ReportsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[index]),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: _destinations,
        onDestinationSelected: (selected) => context.go(_paths[selected]),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'تعذر فتح البيانات المحلية.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'لم تُحذف أي بيانات. أعد تشغيل التطبيق، ثم اطلب المساعدة إن استمرت المشكلة.',
            ),
          ],
        ),
      ),
    ),
  );
}




