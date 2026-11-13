import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/custom_fields_repository.dart';

class CustomFieldsScreen extends ConsumerWidget {
  const CustomFieldsScreen({super.key});

  static const ownerType = 'expense';

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('الحقول المخصصة للمصاريف')),
    body: StreamBuilder(
      stream: ref
          .watch(customFieldsRepositoryProvider)
          .watchDefinitions(ownerType),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final fields = snapshot.data!;
        if (fields.isEmpty) {
          return const Center(child: Text('لا توجد حقول مخصصة.'));
        }
        return ListView.builder(
          itemCount: fields.length,
          itemBuilder: (context, index) {
            final field = fields[index];
            return ListTile(
              title: Text(field.label),
              subtitle: Text(field.fieldType),
              trailing: IconButton(
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'أرشفة',
                onPressed: () => ref
                    .read(customFieldsRepositoryProvider)
                    .archiveDefinition(field.id),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _add(context, ref),
      tooltip: 'إضافة حقل',
      child: const Icon(Icons.add),
    ),
  );

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final label = TextEditingController();
    var type = CustomFieldType.shortText;
    final result = await showDialog<_FieldInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('حقل مخصص'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
              DropdownButtonFormField<CustomFieldType>(
                initialValue: type,
                items: CustomFieldType.values
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item.name)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => type = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FieldInput(label.text, type)),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    if (result == null) return;
    await ref
        .read(customFieldsRepositoryProvider)
        .createDefinition(
          ownerType: ownerType,
          label: result.label,
          type: result.type,
          sortOrder: 0,
        );
  }
}

class _FieldInput {
  const _FieldInput(this.label, this.type);
  final String label;
  final CustomFieldType type;
}
