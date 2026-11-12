import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/balance_badge.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';

/// التبويب 2: موردين (صفحة 4 وصفحة 11):
/// - قائمة الموردين: بطاقة لكل مورد توضح اسمه، هاتفه، ومربع «له» أو «عليه» أو «مصفر».
/// - شريط ملخص علوي: إجمالي ما «لهم» علينا وإجمالي ما «عليهم» لنا.
/// - فلتر سريع لعرض الموردين الذين لهم مبالغ مستحقة مقابل الموردين «المصفرين» (تقرير مصفر).
/// - زر «+ إضافة مورد جديد».
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  String _searchQuery = '';
  String _filter = 'ALL'; // ALL, HAS_BALANCE, SETTLED

  void _showAddOrEditSupplierDialog({SupplierEntity? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null
            ? 'إضافة مورد جديد (رعوي / مسوق)'
            : 'تعديل بيانات المورد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'المنطقة / نوع القات / ملاحظات',
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
                      content: Text('يرجى إدخال اسم المورد'),
                      backgroundColor: AppColors.debtRed),
                );
                return;
              }
              await ref.read(appDatabaseProvider).saveSupplier(
                    id: existing?.id,
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حفظ المورد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersStreamProvider);
    final currency =
        ref.watch(appSettingsStreamProvider).valueOrNull?.currency ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text('قسم الموردين (بياناته • حسابه • بضاعته)'),
        ),
        actions: [
          IconButton(
            tooltip: 'إضافة مورد جديد',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => _showAddOrEditSupplierDialog(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: () => _showAddOrEditSupplierDialog(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مورد جديد'),
      ),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (suppliers) {
          final totalLah =
              suppliers.fold<double>(0, (sum, s) => sum + s.balanceLah);
          final totalAlayh =
              suppliers.fold<double>(0, (sum, s) => sum + s.balanceAlayh);

          final filtered = suppliers.where((s) {
            if (_filter == 'SETTLED' && !s.isSettled) return false;
            if (_filter == 'HAS_BALANCE' && s.isSettled) return false;
            if (_searchQuery.trim().isNotEmpty) {
              final q = _searchQuery.trim().toLowerCase();
              return s.name.toLowerCase().contains(q) ||
                  (s.phone ?? '').contains(q) ||
                  (s.notes ?? '').toLowerCase().contains(q);
            }
            return true;
          }).toList();

          return Column(
            children: [
              // شريط ملخص علوي لإجمالي حسابات الموردين
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryHeaderBox(
                            label: 'إجمالي ما «لهم» علينا',
                            amount: AppFormatters.formatMoney(totalLah,
                                currency: currency),
                            color: AppColors.debtRed,
                            bg: AppColors.debtRedBg,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSummaryHeaderBox(
                            label: 'إجمالي ما «عليهم» لنا',
                            amount: AppFormatters.formatMoney(totalAlayh,
                                currency: currency),
                            color: AppColors.cashGreen,
                            bg: AppColors.cashGreenBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'ابحث باسم المورد، الهاتف، أو المنطقة...',
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
                            label: Text('الكل (${suppliers.length})'),
                            selected: _filter == 'ALL',
                            onSelected: (_) => setState(() => _filter = 'ALL'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('لهم / عليهم رصيد'),
                            selected: _filter == 'HAS_BALANCE',
                            onSelected: (_) =>
                                setState(() => _filter = 'HAS_BALANCE'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('تقرير «مصفر» (0)'),
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
                    ? const Center(
                        child: Text(
                            'لا يوجد موردون مطابقون. اضغط «إضافة مورد جديد» للبدء.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final s = filtered[index];
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () =>
                                  context.push('/supplier/${s.id}?tab=0'),
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
                                                s.name,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if ((s.phone ?? '').isNotEmpty ||
                                                  (s.notes ?? '').isNotEmpty)
                                                Text(
                                                  '${s.phone ?? ''} ${s.notes != null && s.notes!.isNotEmpty ? '• ${s.notes}' : ''}',
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
                                          balanceLah: s.balanceLah,
                                          balanceAlayh: s.balanceAlayh,
                                          isCustomer: false,
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
                                          onPressed: () => context
                                              .push('/supplier/${s.id}?tab=0'),
                                          icon: const Icon(
                                              Icons
                                                  .account_balance_wallet_outlined,
                                              size: 18),
                                          label: const Text('حسابه / سداد'),
                                        ),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(120, 38),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                          ),
                                          onPressed: () => context
                                              .push('/supplier/${s.id}?tab=1'),
                                          icon: const Icon(
                                              Icons.add_shopping_cart,
                                              size: 18),
                                          label: const Text('بضاعته / الشراء'),
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

  Widget _buildSummaryHeaderBox({
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
