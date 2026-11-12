import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/services/pdf_and_share_service.dart';
import 'main_shell_screen.dart';

/// التبويب 1: الشاشة الرئيسية (صفحة 3 و 10):
/// - في الأعلى: بطاقة «معلومات أساسية» (اسم المقوت/المحل + زر بيانات المستخدم).
/// - في الوسط: «ملخص التطبيق» (مبيعات اليوم، الصندوق النقدي، الحوالات، ديون الزبائن «عليهم»، ديون الموردين «لهم» + إقفال اليومية).
/// - قسم المصاريف: أزرار «مصاريف العمل»، «مصاريف شخصية»، و«تقارير المصاريف».
/// - في الأسفل: قائمة «آخر العمليات».
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final summaryAsync = ref.watch(dashboardSummaryStreamProvider);
    final recentOpsAsync = ref.watch(recentOperationsStreamProvider);

    final settings = settingsAsync.valueOrNull;
    final currency = settings?.currency ?? 'ر.ي';

    // التحقق من التنبيه التلقائي للنسخ الاحتياطي في نهاية اليوم (تحسينات P1 - صفحة 5)
    final needsBackupReminder = settings?.lastBackupAt == null ||
        DateTime.now().difference(settings!.lastBackupAt!).inHours >= 18;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.eco, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    settings?.shopName ?? 'تطبيق مقوتي',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    settings?.ownerName ?? 'النظام المحاسبي لبائعي القات',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'بيانات المستخدم',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/user-info'),
          ),
          IconButton(
            tooltip: 'الضبط والنسخ الاحتياطي',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: () => context.push('/expenses?tab=0'),
        icon: const Icon(Icons.add_card),
        label: const Text('إضافة مصروف'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          // تنبيه النسخ الاحتياطي التلقائي في نهاية اليوم
          if (needsBackupReminder)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warningOrangeBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.warningOrange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      color: AppColors.warningOrange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'تذكير: يُنصح بحفظ نسخة احتياطية إلى Google Drive لحماية حسابات اليوم.',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/settings'),
                    child: const Text('نسخ الآن'),
                  ),
                ],
              ),
            ),

          // 1. بطاقة معلومات أساسية + اختصارات سريعة
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.cashGreenBg,
                    child: const Icon(Icons.storefront,
                        color: AppColors.primaryGreen, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'معلومات أساسية: ${settings?.shopName ?? 'مقوت الخير'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'المقوت: ${settings?.ownerName ?? '-'} | الهاتف: ${settings?.phone.isNotEmpty == true ? settings!.phone : 'غير محدد'}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/user-info'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('تعديل'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 2. ملخص التطبيق ولوحة المؤشرات الفورية
          summaryAsync.when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Text('خطأ في تحميل الملخص: $e'),
            data: (summary) =>
                _buildSummarySection(context, ref, settings, summary, currency),
          ),

          const SizedBox(height: 14),

          // 3. قسم المصاريف (مصاريف العمل + مصاريف شخصية + تقارير)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: AppColors.primaryGreen),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'قسم المصاريف (الفرشة / الشخصية / التقارير)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionTile(
                          icon: Icons.work_outline,
                          label: 'مصاريف العمل',
                          color: AppColors.primaryGreen,
                          onTap: () => context.push('/expenses?tab=0'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildActionTile(
                          icon: Icons.home_outlined,
                          label: 'مصاريف شخصية',
                          color: AppColors.warningOrange,
                          onTap: () => context.push('/expenses?tab=1'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildActionTile(
                          icon: Icons.bar_chart_outlined,
                          label: 'تقارير المصاريف',
                          color: AppColors.transferBlue,
                          onTap: () => context.push('/expenses?tab=2'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 4. قسم آخر العمليات
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text(
                'آخر العمليات المسجلة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () => context.push('/recent-operations'),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('عرض السجل الكامل والفلترة'),
              ),
            ],
          ),
          recentOpsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('خطأ: $e'),
            data: (ops) {
              if (ops.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                          'لا توجد حركات مسجلة بعد. ابدأ بتسجيل المبيعات أو المشتريات.'),
                    ),
                  ),
                );
              }
              return Column(
                children: ops
                    .take(8)
                    .map((op) => _buildOperationCard(op, currency))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context,
    WidgetRef ref,
    AppSettingsEntity? settings,
    DashboardSummaryEntity summary,
    String currency,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined,
                        color: AppColors.primaryGreen),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'ملخص التطبيق واليومية',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () =>
                      _showDailyClosingDialog(context, ref, settings, summary),
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('ملخص وإقفال اليومية'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                if (isWide) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildMetricBox(
                            title: 'مبيعات اليوم (نقد + آجل)',
                            value: AppFormatters.formatMoney(
                                summary.todayTotalSales,
                                currency: currency),
                            subtitle:
                                'المحصل اليوم: ${AppFormatters.formatMoney(summary.todayCollectedFromCustomers)}',
                            color: AppColors.primaryGreen,
                            bgColor: AppColors.cashGreenBg,
                            onTap: () => ref
                                .read(selectedBottomTabProvider.notifier)
                                .state = 3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricBox(
                            title: 'الصندوق النقدي (الدرج)',
                            value: AppFormatters.formatMoney(
                                summary.cashDrawerBalance,
                                currency: currency),
                            subtitle:
                                'الحوالات: ${AppFormatters.formatMoney(summary.transferBalance)}',
                            color: AppColors.transferBlue,
                            bgColor: AppColors.transferBlueBg,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricBox(
                            title: 'ديون الزبائن «عليهم»',
                            value: AppFormatters.formatMoney(
                                summary.totalCustomersAlayh,
                                currency: currency),
                            subtitle:
                                'لهم: ${AppFormatters.formatMoney(summary.totalCustomersLah)}',
                            color: AppColors.debtRed,
                            bgColor: AppColors.debtRedBg,
                            onTap: () => ref
                                .read(selectedBottomTabProvider.notifier)
                                .state = 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricBox(
                            title: 'ديون الموردين «لهم»',
                            value: AppFormatters.formatMoney(
                                summary.totalSuppliersLah,
                                currency: currency),
                            subtitle:
                                'عليهم لنا: ${AppFormatters.formatMoney(summary.totalSuppliersAlayh)}',
                            color: AppColors.warningOrange,
                            bgColor: AppColors.warningOrangeBg,
                            onTap: () => ref
                                .read(selectedBottomTabProvider.notifier)
                                .state = 1,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildMetricBox(
                              title: 'مبيعات اليوم (نقد + آجل)',
                              value: AppFormatters.formatMoney(
                                  summary.todayTotalSales,
                                  currency: currency),
                              subtitle:
                                  'المحصل اليوم: ${AppFormatters.formatMoney(summary.todayCollectedFromCustomers)}',
                              color: AppColors.primaryGreen,
                              bgColor: AppColors.cashGreenBg,
                              onTap: () => ref
                                  .read(selectedBottomTabProvider.notifier)
                                  .state = 3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricBox(
                              title: 'الصندوق النقدي (الدرج)',
                              value: AppFormatters.formatMoney(
                                  summary.cashDrawerBalance,
                                  currency: currency),
                              subtitle:
                                  'الحوالات: ${AppFormatters.formatMoney(summary.transferBalance)}',
                              color: AppColors.transferBlue,
                              bgColor: AppColors.transferBlueBg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildMetricBox(
                              title: 'ديون الزبائن «عليهم»',
                              value: AppFormatters.formatMoney(
                                  summary.totalCustomersAlayh,
                                  currency: currency),
                              subtitle:
                                  'لهم: ${AppFormatters.formatMoney(summary.totalCustomersLah)}',
                              color: AppColors.debtRed,
                              bgColor: AppColors.debtRedBg,
                              onTap: () => ref
                                  .read(selectedBottomTabProvider.notifier)
                                  .state = 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricBox(
                              title: 'ديون الموردين «لهم»',
                              value: AppFormatters.formatMoney(
                                  summary.totalSuppliersLah,
                                  currency: currency),
                              subtitle:
                                  'عليهم لنا: ${AppFormatters.formatMoney(summary.totalSuppliersAlayh)}',
                              color: AppColors.warningOrange,
                              bgColor: AppColors.warningOrangeBg,
                              onTap: () => ref
                                  .read(selectedBottomTabProvider.notifier)
                                  .state = 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'صافي الربح (المبيعات - تكلفة المباع - التالف - مصاريف العمل):',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    summary.todayProfitIsReliable
                        ? AppFormatters.formatMoney(summary.todayNetWorkProfit,
                            currency: currency)
                        : 'غير متاح بدقة',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: summary.todayNetWorkProfit >= 0
                          ? AppColors.cashGreen
                          : AppColors.debtRed,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required Color bgColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationCard(UnifiedOperationEntity op, String currency) {
    Color iconColor = AppColors.primaryGreen;
    IconData icon = Icons.receipt_long;
    if (op.type == 'SALE') {
      iconColor = AppColors.cashGreen;
      icon = Icons.point_of_sale;
    } else if (op.type == 'PURCHASE') {
      iconColor = AppColors.warningOrange;
      icon = Icons.shopping_cart_checkout;
    } else if (op.type == 'CUSTOMER_PAY') {
      iconColor = AppColors.cashGreen;
      icon = Icons.south_west;
    } else if (op.type == 'SUPPLIER_PAY') {
      iconColor = AppColors.debtRed;
      icon = Icons.north_east;
    } else if (op.type == 'RETURN' || op.type == 'WASTAGE') {
      iconColor = AppColors.wastageGrey;
      icon = Icons.assignment_return_outlined;
    } else if (op.type == 'EXPENSE') {
      iconColor = AppColors.debtRed;
      icon = Icons.money_off_csred_outlined;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          op.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '${op.subtitle} • ${AppFormatters.formatDateTime(op.createdAt)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(
            AppFormatters.formatMoney(op.amount, currency: currency),
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }

  void _showDailyClosingDialog(
    BuildContext context,
    WidgetRef ref,
    AppSettingsEntity? settings,
    DashboardSummaryEntity summary,
  ) {
    final effectiveSettings = settings ??
        const AppSettingsEntity(
          id: 1,
          ownerName: 'أبو محمد',
          shopName: 'مقوت الخير',
          phone: '',
          currency: 'ر.ي',
        );
    final c = effectiveSettings.currency;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fact_check_outlined, color: AppColors.primaryGreen),
            SizedBox(width: 8),
            Text('ملخص وإقفال اليومية'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogRow(
                  'إجمالي مبيعات اليوم الصافية:',
                  AppFormatters.formatMoney(summary.todayTotalSales,
                      currency: c)),
              _buildDialogRow(
                  'إجمالي المحصل اليوم:',
                  AppFormatters.formatMoney(summary.todayCollectedFromCustomers,
                      currency: c)),
              _buildDialogRow(
                  'إجمالي مشتريات اليوم:',
                  AppFormatters.formatMoney(summary.todayPurchasesTotal,
                      currency: c)),
              _buildDialogRow(
                  'تكلفة البضاعة المباعة:',
                  summary.todayProfitIsReliable
                      ? AppFormatters.formatMoney(summary.todayCogs,
                          currency: c)
                      : 'بيانات التكلفة غير مكتملة'),
              _buildDialogRow(
                  'قيمة التالف / البايت اليوم:',
                  AppFormatters.formatMoney(summary.todayWastageCost,
                      currency: c)),
              _buildDialogRow(
                  'مصاريف العمل اليوم:',
                  AppFormatters.formatMoney(summary.todayWorkExpenses,
                      currency: c)),
              const Divider(),
              _buildDialogRow(
                'صافي ربح العمل اليومي:',
                summary.todayProfitIsReliable
                    ? AppFormatters.formatMoney(summary.todayNetWorkProfit,
                        currency: c)
                    : 'غير متاح بدقة',
                isBold: true,
              ),
              _buildDialogRow(
                'المسحوبات الشخصية (منفصلة):',
                AppFormatters.formatMoney(summary.todayPersonalExpenses,
                    currency: c),
              ),
              const Divider(),
              _buildDialogRow(
                  'الصندوق النقدي الفعلي:',
                  AppFormatters.formatMoney(summary.cashDrawerBalance,
                      currency: c)),
              _buildDialogRow(
                  'رصيد الحوالات البنكية:',
                  AppFormatters.formatMoney(summary.transferBalance,
                      currency: c)),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showTreasuryTransferDialog(context, ref, summary, c);
            },
            icon: const Icon(Icons.swap_horiz),
            label: const Text('نقل بين النقد والحوالة'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              final msg = PdfAndShareService.buildDailyClosingSummaryText(
                settings: effectiveSettings,
                summary: summary,
              );
              PdfAndShareService.shareViaWhatsApp(
                phone: effectiveSettings.phone,
                message: msg,
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('مشاركة ملخص اليومية (واتساب)'),
          ),
        ],
      ),
    );
  }

  void _showTreasuryTransferDialog(
    BuildContext context,
    WidgetRef ref,
    DashboardSummaryEntity summary,
    String currency,
  ) {
    var fromMethod = 'CASH';
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final available = fromMethod == 'CASH'
              ? summary.cashDrawerBalance
              : summary.transferBalance;
          final toMethod = fromMethod == 'CASH' ? 'TRANSFER' : 'CASH';
          return AlertDialog(
            title: const Text('نقل مبلغ داخل الخزينة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: fromMethod,
                  decoration: const InputDecoration(labelText: 'النقل من'),
                  items: const [
                    DropdownMenuItem(value: 'CASH', child: Text('النقد')),
                    DropdownMenuItem(
                        value: 'TRANSFER', child: Text('الحوالات')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => fromMethod = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'إلى: ${toMethod == 'CASH' ? 'النقد' : 'الحوالات'} • المتاح: ${AppFormatters.formatMoney(available, currency: currency)}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text.trim());
                  if (amount == null || amount <= 0) return;
                  await ref.read(appDatabaseProvider).recordTreasuryTransfer(
                        fromMethod: fromMethod,
                        toMethod: toMethod,
                        amount: amount,
                      );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('تنفيذ النقل'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDialogRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isBold ? AppColors.primaryGreen : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
