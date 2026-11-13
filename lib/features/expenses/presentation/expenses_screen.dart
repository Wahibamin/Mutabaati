import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../custom_fields/presentation/custom_field_inputs.dart';
import '../domain/expense_draft.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localDate = localDateKey();
    final settings = ref.watch(appSettingsProvider).value;
    final categories = ref.watch(expenseCategoriesProvider);
    final expenses = ref.watch(expensesForDateProvider(localDate));
    final fractionDigits = settings?.currencyFractionDigits ?? 2;
    final currencyCode = settings?.currencyCode ?? 'SAR';
    return Scaffold(
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('تعذر تحميل التصنيفات.')),
        data: (categoryRows) => expenses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('تعذر تحميل المصاريف.')),
          data: (rows) {
            final categoryNames = {
              for (final category in categoryRows) category.id: category.name,
            };
            final total = rows.fold(0, (sum, row) => sum + row.amountMinor);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.yMMMMEEEEd('ar').format(DateTime.now()),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'إجمالي المصروف: ${MoneyParser.formatMinorUnits(total, fractionDigits: fractionDigits)} $currencyCode',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (categoryRows.isEmpty)
                  const _EmptyExpenses(
                    message: 'أضف تصنيفًا أولًا، مثل الطعام أو المواصلات.',
                  )
                else if (rows.isEmpty)
                  const _EmptyExpenses(
                    message: 'لا توجد مصاريف مسجلة لهذا اليوم.',
                  )
                else
                  ...rows.map(
                    (row) => _ExpenseCard(
                      expense: row,
                      categoryName:
                          categoryNames[row.categoryId] ?? 'تصنيف مؤرشف',
                      fractionDigits: fractionDigits,
                      onDelete: () => _confirmDelete(context, ref, row.id),
                      onEdit: () => _showExpenseDialog(
                        context,
                        ref,
                        fractionDigits,
                        existing: row,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: categories.value?.isEmpty ?? true
          ? FloatingActionButton.extended(
              onPressed: () => _showCategoryDialog(context, ref),
              icon: const Icon(Icons.category_outlined),
              label: const Text('إضافة تصنيف'),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'fab_category',
                  mini: true,
                  onPressed: () => _showCategoryDialog(context, ref),
                  tooltip: 'إضافة تصنيف',
                  child: const Icon(Icons.category_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'fab_expense',
                  onPressed: () =>
                      _showExpenseDialog(context, ref, fractionDigits),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مصروف'),
                ),
              ],
            ),
    );
  }

  Future<void> _showCategoryDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصنيف جديد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم التصنيف'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      await ref.read(expenseRepositoryProvider).addCategory(result);
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _showExpenseDialog(
    BuildContext context,
    WidgetRef ref,
    int fractionDigits, {
    dynamic existing,
  }) async {
    final categories = ref.read(expenseCategoriesProvider).value ?? [];
    if (categories.isEmpty) return;

    // جلب تعريفات الحقول المخصصة للمصاريف
    final customFieldDefs = await ref
        .read(customFieldsRepositoryProvider)
        .getDefinitions('expense');

    // جلب القيم الموجودة إن كان تعديلاً
    Map<String, dynamic> initialValueMap = {};
    if (existing != null && customFieldDefs.isNotEmpty) {
      final values = await ref
          .read(customFieldsRepositoryProvider)
          .getValuesForOwner(ownerType: 'expense', ownerId: existing.id as String);
      initialValueMap = {for (final v in values) v.definitionId: v};
    }

    if (!context.mounted) return;

    final amount = TextEditingController(
      text: existing != null
          ? MoneyParser.formatMinorUnits(
              existing.amountMinor as int,
              fractionDigits: fractionDigits,
            )
          : '',
    );
    final note = TextEditingController(text: existing?.note ?? '');
    var categoryId = (existing?.categoryId as String?) ?? categories.first.id;
    final formKey = GlobalKey<CustomFieldFormState>();

    final draft = await showDialog<ExpenseDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: Text(existing == null ? 'مصروف جديد' : 'تعديل المصروف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => categoryId = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'المبلغ *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختيارية)',
                  ),
                ),
                if (customFieldDefs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  CustomFieldForm(
                    key: formKey,
                    definitions: customFieldDefs,
                    initialValues: {
                      for (final e in initialValueMap.entries)
                        e.key: e.value,
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final amountMinor = MoneyParser.parseToMinorUnits(
                    amount.text,
                    fractionDigits: fractionDigits,
                  );
                  Navigator.pop(
                    dialogContext,
                    ExpenseDraft(
                      id: existing?.id as String?,
                      categoryId: categoryId,
                      amountMinor: amountMinor,
                      localDate: localDateKey(),
                      note: note.text,
                    ),
                  );
                } on FormatException catch (error) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
    if (draft == null) return;

    // حفظ المصروف
    await ref.read(expenseRepositoryProvider).save(draft);
    final savedId = draft.id ?? await _getLastInsertedExpenseId(ref);

    // حفظ قيم الحقول المخصصة
    if (customFieldDefs.isNotEmpty && savedId != null) {
      final entries = formKey.currentState?.collectEntries() ?? [];
      final repo = ref.read(customFieldsRepositoryProvider);
      for (final entry in entries) {
        if (entry.isEmpty && !entry.definition.isRequired) continue;
        await repo.saveValue(
          definitionId: entry.definition.id,
          ownerType: 'expense',
          ownerId: savedId,
          valueText: entry.valueText,
          valueInteger: entry.valueInteger,
          valueBoolean: entry.valueBoolean,
          valueDate: entry.valueDate,
        );
      }
    }
  }

  /// يعيد آخر مصروف محفوظ لليوم الحالي (لتحديد ID عند الإنشاء الجديد).
  Future<String?> _getLastInsertedExpenseId(WidgetRef ref) async {
    final rows = await ref
        .read(expenseRepositoryProvider)
        .watchForLocalDate(localDateKey())
        .first;
    return rows.isNotEmpty ? rows.first.id : null;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المصروف؟'),
        content: const Text('لا يمكن التراجع عن الحذف من هذه الشاشة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(expenseRepositoryProvider).delete(id);
  }
}

// ─── بطاقة المصروف ─────────────────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.categoryName,
    required this.fractionDigits,
    required this.onDelete,
    required this.onEdit,
  });

  final dynamic expense;
  final String categoryName;
  final int fractionDigits;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(categoryName),
      subtitle: (expense.note == null || (expense.note as String).isEmpty)
          ? null
          : Text(expense.note as String),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            MoneyParser.formatMinorUnits(
              expense.amountMinor as int,
              fractionDigits: fractionDigits,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'تعديل',
            onPressed: onEdit,
          ),
        ],
      ),
      onLongPress: onDelete,
    ),
  );
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.receipt_long_outlined, size: 52),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}
