import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/balance_badge.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/services/pdf_and_share_service.dart';

/// شاشة تفاصيل حساب الزبون وكشف الحساب التفصيلي بالحركات ومشاركته عبر واتساب أو PDF
class CustomerDetailScreen extends ConsumerWidget {
  final int customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final settings = ref.watch(appSettingsStreamProvider).valueOrNull;
    final currency = settings?.currency ?? 'ر.ي';
    // مراقبة التغييرات اللحظية
    ref.watch(customersStreamProvider);

    return FutureBuilder<CustomerEntity?>(
      future: db.getCustomerById(customerId),
      builder: (context, custSnap) {
        final customer = custSnap.data;
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('حساب الزبون')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final summaryBalanceText = customer.balanceAlayh > 0
            ? 'عليه لصالحنا: ${AppFormatters.formatMoney(customer.balanceAlayh, currency: currency)}'
            : (customer.balanceLah > 0
                ? 'له عندنا: ${AppFormatters.formatMoney(customer.balanceLah, currency: currency)}'
                : 'الحساب مصفر (0)');

        return Scaffold(
          appBar: AppBar(
            title: Text('كشف حساب: ${customer.name}'),
          ),
          body: FutureBuilder<List<StatementLineEntity>>(
            future: db.getCustomerStatement(customer.id),
            builder: (context, stmtSnap) {
              final lines = stmtSnap.data ?? [];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer.name,
                                      style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    if ((customer.phone ?? '').isNotEmpty)
                                      Text(
                                        'الهاتف: ${customer.phone}',
                                        style: const TextStyle(
                                            color: AppColors.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              BalanceBadge(
                                balanceLah: customer.balanceLah,
                                balanceAlayh: customer.balanceAlayh,
                                isCustomer: true,
                                currency: currency,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final pdfBtn = ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                                onPressed: () {
                                  PdfAndShareService
                                      .generateAndShareStatementPdf(
                                    shopName:
                                        settings?.shopName ?? 'مقوت الخير',
                                    partyTitle: 'الزبون',
                                    partyName: customer.name,
                                    summaryBalanceText: summaryBalanceText,
                                    lines: lines,
                                    currency: currency,
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('مشاركة كشف PDF'),
                              );

                              final whatsappBtn = OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                                onPressed: () {
                                  final buffer = StringBuffer();
                                  buffer.writeln(
                                      '🌿 *${settings?.shopName ?? 'مقوت الخير'}* 🌿');
                                  buffer.writeln(
                                      '*كشف حساب الزبون: ${customer.name}*');
                                  buffer.writeln('📊 *$summaryBalanceText*');
                                  buffer.writeln('━━━━━━━━━━━━━━');
                                  for (final l in lines.take(10)) {
                                    buffer.writeln(
                                      '• ${AppFormatters.formatDate(l.date)} | ${l.operationType}: ${l.description}',
                                    );
                                  }
                                  PdfAndShareService.shareViaWhatsApp(
                                    phone: customer.phone,
                                    message: buffer.toString(),
                                  );
                                },
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('إرسال عبر واتساب'),
                              );

                              if (constraints.maxWidth < 360) {
                                return Column(
                                  children: [
                                    pdfBtn,
                                    const SizedBox(height: 8),
                                    whatsappBtn,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: pdfBtn),
                                  const SizedBox(width: 10),
                                  Expanded(child: whatsappBtn),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'حركات الحساب التفصيلية (${lines.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (lines.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('لا توجد حركات مسجلة لهذا الزبون بعد')),
                      ),
                    )
                  else
                    for (final l in lines)
                      Card(
                        child: ListTile(
                          title: Text(l.operationType,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              '${l.description}\n${AppFormatters.formatDateTime(l.date)}'),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                l.debitAlayh > 0
                                    ? 'عليه: +${AppFormatters.formatMoney(l.debitAlayh)}'
                                    : 'سداد/مرتجع: -${AppFormatters.formatMoney(l.creditLah)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: l.debitAlayh > 0
                                      ? AppColors.debtRed
                                      : AppColors.cashGreen,
                                ),
                              ),
                              Text(
                                'الرصيد (${l.balanceLabel}): ${AppFormatters.formatMoney(l.runningBalance)}',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
