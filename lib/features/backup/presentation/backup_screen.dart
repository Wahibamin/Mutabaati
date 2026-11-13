import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'يمكنك أخذ نسخة احتياطية من جميع بياناتك (كالمتابعة، المصاريف، المواعيد) '
                'لحفظها في ملف آمن خارج التطبيق. لاسترجاع البيانات، اختر استعادة وحدد نفس الملف. '
                'سيتم استبدال جميع بياناتك الحالية بشكل كامل.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              try {
                // In a real app we use file picker or path provider.
                // For demonstration, simulating export.
                final path = '/storage/emulated/0/Download/mutabaati_backup.json';
                await ref.read(backupRepositoryProvider).exportData(path);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم الحفظ في: $path')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('نسخ احتياطي الآن'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تأكيد الاستعادة'),
                  content: const Text(
                    'سيتم استبدال جميع البيانات الحالية بالبيانات الموجودة في النسخة الاحتياطية. لا يمكن التراجع عن هذه الخطوة!',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('نعم، استعادة'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                try {
                  final path = '/storage/emulated/0/Download/mutabaati_backup.json';
                  await ref.read(backupRepositoryProvider).importData(path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم استعادة البيانات بنجاح.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل الاستعادة: $e')),
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.upload),
            label: const Text('استعادة البيانات'),
          ),
        ],
      ),
    );
  }
}
