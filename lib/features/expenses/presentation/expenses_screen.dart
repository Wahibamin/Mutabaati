import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/custom_numeric_keypad.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';

/// شاشة المصاريف وتقاريرها (صفحة 4 وصفحة 7 - TC-05):
/// - تبويب 1: مصاريف العمل (أكياس، ثلج، ماء، إيجار، نقل/فرزة، عمال) وتُخصم من ربح العمل.
/// - تبويب 2: مصاريف شخصية (مقاضي البيت، التزامات) وتُخصم من الصندوق النقدي مع فصلها في تقرير الأرباح.
/// - تبويب 3: تقارير المصاريف (عرض ومقارنة مصاريف العمل والمصاريف الشخصية).
class ExpensesScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const ExpensesScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  double _amount = 0;
  String _paymentMethod = 'CASH';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveExpense(String categoryType) async {
    if (_isSaving) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى إدخال أو اختيار بند المصروف'),
            backgroundColor: AppColors.debtRed),
      );
      return;
    }
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى إدخال مبلغ المصروف أكبر من صفر'),
            backgroundColor: AppColors.debtRed),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(appDatabaseProvider).recordExpense(
            categoryType: categoryType,
            title: _titleController.text.trim(),
            amount: _amount,
            paymentMethod: _paymentMethod,
            notes: _notesController.text.trim(),
          );
      if (mounted) {
        setState(() {
          _titleController.clear();
          _notesController.clear();
          _amount = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              categoryType == 'WORK'
                  ? 'تم تسجيل مصروف العمل بنجاح'
                  : 'تم تسجيل المصروف الشخصي بنجاح',
            ),
            backgroundColor: AppColors.cashGreen,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesStreamProvider);
    final currency =
        ref.watch(appSettingsStreamProvider).valueOrNull?.currency ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصاريف وتقاريرها'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'مصاريف العمل'),
            Tab(text: 'مصاريف شخصية'),
            Tab(text: 'تقارير المصاريف'),
          ],
        ),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (allExpenses) {
          final workList =
              allExpenses.where((e) => e.categoryType == 'WORK').toList();
          final personalList =
              allExpenses.where((e) => e.categoryType == 'PERSONAL').toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildExpenseEntryTab(
                categoryType: 'WORK',
                headerNote:
                    'تُخصم مصاريف العمل (أكياس، ثلج، ماء، إيجار، نقل) من صافي ربح العمل اليومي.',
                quickItems: AppConstants.commonWorkExpenses,
                records: workList,
                currency: currency,
              ),
              _buildExpenseEntryTab(
                categoryType: 'PERSONAL',
                headerNote:
                    'تُخصم المصاريف الشخصية (مقاضي المنزل) من الصندوق وتُفصل عن أرباح القات.',
                quickItems: AppConstants.commonPersonalExpenses,
                records: personalList,
                currency: currency,
              ),
              _buildExpensesReportTab(workList, personalList, currency),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpenseEntryTab({
    required String categoryType,
    required String headerNote,
    required List<String> quickItems,
    required List<ExpenseEntity> records,
    required String currency,
  }) {
    final isWork = categoryType == 'WORK';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isWork ? AppColors.cashGreenBg : AppColors.warningOrangeBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            headerNote,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isWork ? AppColors.primaryGreen : AppColors.warningOrange,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختيار سريع للبند:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickItems.map((item) {
                    return ActionChip(
                      label: Text(item),
                      onPressed: () =>
                          setState(() => _titleController.text = item),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'بند / وصف المصروف',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final val = await CustomNumericKeypad.show(
                      context,
                      title: 'إدخال مبلغ المصروف',
                      initialValue: _amount,
                    );
                    if (val != null) setState(() => _amount = val);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'المبلغ (اضغط لفتح لوحة الأرقام السريعة)',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    child: Text(
                      _amount > 0
                          ? AppFormatters.formatMoney(_amount,
                              currency: currency)
                          : 'اضغط لإدخال المبلغ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _amount > 0
                            ? AppColors.primaryGreen
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Text('طريقة الصرف:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ChoiceChip(
                      label: const Text('نقد من الصندوق'),
                      selected: _paymentMethod == 'CASH',
                      onSelected: (_) =>
                          setState(() => _paymentMethod = 'CASH'),
                    ),
                    ChoiceChip(
                      label: const Text('حوالة / محفظة'),
                      selected: _paymentMethod == 'TRANSFER',
                      onSelected: (_) =>
                          setState(() => _paymentMethod = 'TRANSFER'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isWork
                        ? AppColors.primaryGreen
                        : AppColors.warningOrange,
                    minimumSize: const Size(double.infinity, 50),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onPressed:
                      _isSaving ? null : () => _saveExpense(categoryType),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save_outlined),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isWork ? 'حفظ مصروف العمل' : 'حفظ المصروف الشخصي',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'سجل ${isWork ? 'مصاريف العمل' : 'المصاريف الشخصية'} (${records.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final exp in records)
          Card(
            child: ListTile(
              title: Text(exp.title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${exp.paymentMethod == 'CASH' ? 'نقد' : 'حوالة'} • ${AppFormatters.formatDateTime(exp.createdAt)}',
              ),
              trailing: Text(
                AppFormatters.formatMoney(exp.amount, currency: currency),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.debtRed,
                    fontSize: 15),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExpensesReportTab(
    List<ExpenseEntity> workList,
    List<ExpenseEntity> personalList,
    String currency,
  ) {
    final totalWork = workList.fold<double>(0, (sum, e) => sum + e.amount);
    final totalPersonal =
        personalList.fold<double>(0, (sum, e) => sum + e.amount);
    final grandTotal = totalWork + totalPersonal;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مقارنة مصاريف العمل والمصاريف الشخصية',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                _buildReportRow(
                  'إجمالي مصاريف العمل (تُخصم من الربح):',
                  AppFormatters.formatMoney(totalWork, currency: currency),
                  AppColors.primaryGreen,
                ),
                const Divider(),
                _buildReportRow(
                  'إجمالي المصاريف الشخصية (مسحوبات منزلية):',
                  AppFormatters.formatMoney(totalPersonal, currency: currency),
                  AppColors.warningOrange,
                ),
                const Divider(),
                _buildReportRow(
                  'إجمالي المبالغ المصروفة من الصندوق:',
                  AppFormatters.formatMoney(grandTotal, currency: currency),
                  AppColors.debtRed,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportRow(String label, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Text(val,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }
}
