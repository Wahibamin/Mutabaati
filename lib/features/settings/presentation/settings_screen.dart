import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('الإعدادات')),
    body: ref
        .watch(appSettingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('تعذر تحميل الإعدادات.')),
          data: (settings) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('العملة'),
                      subtitle: Text(
                        '${settings.currencyCode} • ${settings.currencyFractionDigits} منازل عشرية',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('المنطقة الزمنية'),
                      subtitle: Text(settings.timezoneId),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      title: Text('بداية الأسبوع'),
                      subtitle: Text('السبت'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('الحقول المخصصة'),
                  subtitle: const Text('إضافة وأرشفة حقول المصاريف.'),
                  onTap: () => context.push('/custom-fields'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('تشخيص التنبيهات'),
                  subtitle: const Text('حالة الإذن واختبار تنبيه تجريبي.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notification-diagnostics'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('النسخ الاحتياطي والاستعادة'),
                  subtitle: const Text('حفظ بياناتك أو استعادتها.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/backup'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حول التطبيق',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'متابعتي هو تطبيق شخصي يعمل بالكامل دون إنترنت. لا يتم مزامنة أو جمع بياناتك إطلاقاً، وتظل محفوظة في هذا الهاتف فقط.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
  );
}
