import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/local_db/app_database.dart';
import '../../suppliers/presentation/suppliers_screen.dart';
import '../../customers/presentation/customers_screen.dart';
import '../../sales/presentation/sales_screen.dart';
import 'home_screen.dart';

final selectedBottomTabProvider = StateProvider<int>((ref) => 0);

/// الهيكل الرئيسي للتطبيق (Main Shell) مع شريط التنقل السفلي (Bottom Navigation Bar)
/// يضم الأقسام الأربعة الرئيسية كما في المخطط (صفحة 1 و 10):
/// 1) الشاشة الرئيسية | 2) موردين | 3) زبائن | 4) مبيعات
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  bool _isUnlocked = false;
  bool _checkedLock = false;
  final TextEditingController _pinController = TextEditingController();
  String? _pinError;
  bool _isVerifyingPin = false;

  final List<Widget> _pages = const [
    HomeScreen(),
    SuppliersScreen(),
    CustomersScreen(),
    SalesScreen(),
  ];

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricUnlock() async {
    try {
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      if (!canCheck) return;
      final authenticated = await auth.authenticate(
        localizedReason: 'يرجى تأكيد البصمة لفتح حسابات تطبيق مقوتي',
      );
      if (authenticated && mounted) {
        setState(() {
          _isUnlocked = true;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final currentTab = ref.watch(selectedBottomTabProvider);

    return settingsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        body: Center(child: Text('حدث خطأ في تحميل الإعدادات: $err')),
      ),
      data: (settings) {
        final hasPin =
            settings.pinCode != null && settings.pinCode!.trim().isNotEmpty;
        if (!hasPin) {
          _isUnlocked = true;
        } else if (!_checkedLock) {
          _checkedLock = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _tryBiometricUnlock());
        }

        if (hasPin && !_isUnlocked) {
          return _buildLockScreen();
        }

        return Scaffold(
          body: IndexedStack(
            index: currentTab,
            children: _pages,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentTab,
            onDestinationSelected: (idx) {
              ref.read(selectedBottomTabProvider.notifier).state = idx;
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon:
                    Icon(Icons.dashboard, color: AppColors.primaryGreen),
                label: 'الشاشة الرئيسية',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_shipping_outlined),
                selectedIcon:
                    Icon(Icons.local_shipping, color: AppColors.primaryGreen),
                label: 'موردين',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_alt_outlined),
                selectedIcon:
                    Icon(Icons.people_alt, color: AppColors.primaryGreen),
                label: 'زبائن',
              ),
              NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon:
                    Icon(Icons.point_of_sale, color: AppColors.primaryGreen),
                label: 'مبيعات',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: AppColors.primaryGreen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 56, color: AppColors.primaryGreen),
                    const SizedBox(height: 12),
                    const Text(
                      'تطبيق مقوتي محمي برمز PIN',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل رمز الحماية السري أو استخدم البصمة للدخول إلى الحسابات',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: 'رمز الحماية (PIN)',
                        errorText: _pinError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isVerifyingPin
                          ? null
                          : () async {
                              setState(() => _isVerifyingPin = true);
                              final verified = await ref
                                  .read(appDatabaseProvider)
                                  .verifyPin(_pinController.text);
                              if (!mounted) return;
                              if (verified) {
                                setState(() {
                                  _isUnlocked = true;
                                  _pinError = null;
                                  _isVerifyingPin = false;
                                });
                              } else {
                                setState(() {
                                  _pinError = 'رمز PIN غير صحيح، حاول مرة أخرى';
                                  _isVerifyingPin = false;
                                });
                              }
                            },
                      icon: const Icon(Icons.login),
                      label: const Text('فتح التطبيق'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _tryBiometricUnlock,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('فتح عبر بصمة الإصبع'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
