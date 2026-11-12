import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/balance_badge.dart';
import '../../../core/widgets/custom_numeric_keypad.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/services/pdf_and_share_service.dart';

/// التبويب 3: زبائن (صفحة 4 وصفحة 11):
/// - شريط بحث علوي فوري للبحث باسم الزبون أو هاتفه.
/// - شريط ملخص أعلى القائمة: إجمالي ما «عليهم» وإجمالي ما «لهم».
/// - بطاقة الزبون: الاسم، حالة الرصيد («عليه» أو «له»)، وزر «سداد سريع» من خارج البطاقة دون الحاجة للدخول في التفاصيل.
/// - إرسال سند قبض نصي عبر واتساب فور السداد.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _searchQuery = '';
  String _filter = 'ALL'; // ALL, DEBTORS (المدينين حسب الأعلى دينًا), SETTLED

  void _showAddCustomerDialog({CustomerEntity? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final limitCtrl = TextEditingController(
      text: existing?.creditLimit != null
          ? existing!.creditLimit!.toInt().toString()
          : '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(existing == null ? 'إضافة زبون جديد' : 'تعديل بيانات الزبون'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الزبون *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (لإرسال سند القبض واتساب)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'سقف الدين المسموح (اختياري)',
                  prefixIcon: Icon(Icons.warning_amber_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('يرجى إدخال اسم الزبون'),
                      backgroundColor: AppColors.debtRed),
                );
                return;
              }
              final limit = double.tryParse(limitCtrl.text.trim());
              await ref.read(appDatabaseProvider).saveCustomer(
                    id: existing?.id,
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                    creditLimit: limit,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حفظ الزبون'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickCustomerPaymentSheet(
    CustomerEntity customer,
    AppSettingsEntity? settings,
    String currency,
  ) async {
    double amount = customer.balanceAlayh > 0 ? customer.balanceAlayh : 0;
    String method = 'CASH';
    String selectedWallet = AppConstants.commonWallets.first;
    final transferNoCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سداد من الزبون: ${customer.name}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الرصيد الحالي عليه: ${AppFormatters.formatMoney(customer.balanceAlayh, currency: currency)}',
                      style: const TextStyle(
                          color: AppColors.debtRed,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const Text('طريقة القبض:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ChoiceChip(
                          label: const Text('نقد (في الدرج)'),
                          selected: method == 'CASH',
                          onSelected: (_) =>
                              setSheetState(() => method = 'CASH'),
                        ),
                        ChoiceChip(
                          label: const Text('حوالة مالية'),
                          selected: method == 'TRANSFER',
                          onSelected: (_) =>
                              setSheetState(() => method = 'TRANSFER'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final val = await CustomNumericKeypad.show(
                          ctx,
                          title: 'مبلغ السداد المستلم من الزبون',
                          initialValue: amount,
                        );
                        if (val != null) setSheetState(() => amount = val);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'مبلغ السداد (اضغط لإدخال المبلغ)',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        child: Text(
                          amount > 0
                              ? AppFormatters.formatMoney(amount,
                                  currency: currency)
                              : 'اضغط لإدخال المبلغ',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.cashGreen),
                        ),
                      ),
                    ),
                    if (method == 'TRANSFER') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedWallet,
                        decoration: const InputDecoration(
                          labelText: 'اسم المحفظة / الشبكة',
                          prefixIcon:
                              Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: AppConstants.commonWallets
                            .map((w) =>
                                DropdownMenuItem(value: w, child: Text(w)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setSheetState(() => selectedWallet = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: transferNoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'رقم الحوالة / الملاحظة',
                          prefixIcon: Icon(Icons.tag),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة إضافية',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cashGreen),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    if (amount <= 0) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'يرجى إدخال مبلغ سداد أكبر من صفر'),
                                          backgroundColor: AppColors.debtRed,
                                        ),
                                      );
                                      return;
                                    }
                                    setSheetState(() => isSubmitting = true);
                                    await ref
                                        .read(appDatabaseProvider)
                                        .recordPayment(
                                          partyType: 'CUSTOMER',
                                          partyId: customer.id,
                                          amount: amount,
                                          method: method,
                                          transferCompany: method == 'TRANSFER'
                                              ? selectedWallet
                                              : null,
                                          transferNumber: method == 'TRANSFER'
                                              ? transferNoCtrl.text.trim()
                                              : null,
                                          notes: notesCtrl.text.trim(),
                                        );
                                    final updatedCustomer = await ref
                                        .read(appDatabaseProvider)
                                        .getCustomerById(customer.id);
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                              'تم تسجيل السداد وخصمه من رصيد الزبون بنجاح'),
                                          backgroundColor: AppColors.cashGreen,
                                          action: SnackBarAction(
                                            label: 'سند واتساب',
                                            textColor: Colors.white,
                                            onPressed: () {
                                              final receipt = PdfAndShareService
                                                  .buildCustomerReceiptText(
                                                shopName: settings?.shopName ??
                                                    'مقوت الخير',
                                                customerName: customer.name,
                                                paidAmount: amount,
                                                method: method,
                                                remainingAlayh: updatedCustomer
                                                        ?.balanceAlayh ??
                                                    0,
                                                remainingLah: updatedCustomer
                                                        ?.balanceLah ??
                                                    0,
                                                currency: currency,
                                              );
                                              PdfAndShareService
                                                  .shareViaWhatsApp(
                                                phone: customer.phone,
                                                message: receipt,
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('حفظ السداد'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersStreamProvider);
    final settings = ref.watch(appSettingsStreamProvider).valueOrNull;
    final currency = settings?.currency ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text('قسم الزبائن (عليه / له / سداد / تقارير)'),
        ),
        actions: [
          IconButton(
            tooltip: 'إضافة زبون جديد',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => _showAddCustomerDialog(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: () => _showAddCustomerDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة زبون'),
      ),
      body: customersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (customers) {
          final totalAlayh =
              customers.fold<double>(0, (sum, c) => sum + c.balanceAlayh);
          final totalLah =
              customers.fold<double>(0, (sum, c) => sum + c.balanceLah);

          final filtered = customers.where((c) {
            if (_filter == 'DEBTORS' && c.balanceAlayh <= 0.001) return false;
            if (_filter == 'SETTLED' && !c.isSettled) return false;
            if (_searchQuery.trim().isNotEmpty) {
              final q = _searchQuery.trim().toLowerCase();
              return c.name.toLowerCase().contains(q) ||
                  (c.phone ?? '').contains(q);
            }
            return true;
          }).toList();

          return Column(
            children: [
              // شريط ملخص أعلى القائمة: إجمالي ما «عليهم» وإجمالي ما «لهم» (صفحة 11)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryBox(
                            label: 'إجمالي ما «عليهم» (ديون لنا)',
                            amount: AppFormatters.formatMoney(totalAlayh,
                                currency: currency),
                            color: AppColors.debtRed,
                            bg: AppColors.debtRedBg,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSummaryBox(
                            label: 'إجمالي ما «لهم» (رصيد دائن)',
                            amount: AppFormatters.formatMoney(totalLah,
                                currency: currency),
                            color: AppColors.transferBlue,
                            bg: AppColors.transferBlueBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'بحث فوري باسم الزبون أو رقم هاتفه...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text('الكل (${customers.length})'),
                            selected: _filter == 'ALL',
                            onSelected: (_) => setState(() => _filter = 'ALL'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('المدينون (الأعلى دينًا)'),
                            selected: _filter == 'DEBTORS',
                            onSelected: (_) =>
                                setState(() => _filter = 'DEBTORS'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('مصفر (0)'),
                            selected: _filter == 'SETTLED',
                            onSelected: (_) =>
                                setState(() => _filter = 'SETTLED'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('لا يوجد زبائن مطابقون للبحث.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => context.push('/customer/${c.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                c.name,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if ((c.phone ?? '').isNotEmpty)
                                                Text(
                                                  'هاتف: ${c.phone}',
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        BalanceBadge(
                                          balanceLah: c.balanceLah,
                                          balanceAlayh: c.balanceAlayh,
                                          isCustomer: true,
                                          currency: currency,
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 18),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              context.push('/customer/${c.id}'),
                                          icon: const Icon(
                                              Icons.receipt_long_outlined,
                                              size: 18),
                                          label:
                                              const Text('تقارير وكشف الحساب'),
                                        ),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.cashGreen,
                                            minimumSize: const Size(115, 38),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                          ),
                                          onPressed: () =>
                                              _showQuickCustomerPaymentSheet(
                                                  c, settings, currency),
                                          icon: const Icon(
                                              Icons.payments_outlined,
                                              size: 18),
                                          label: const Text('سداد سريع'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBox({
    required String label,
    required String amount,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(amount,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
