import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/formatters.dart';
import '../entities/models.dart';

/// خدمة إصدار التقارير («مصفر» و«مفصل») ومشاركة كشوفات الحساب وسندات القبض عبر واتساب و PDF
class PdfAndShareService {
  /// إرسال رسالة نصية منسقة (سند قبض أو كشف حساب أو ملخص اليومية) عبر واتساب مباشرة
  static Future<void> shareViaWhatsApp({
    String? phone,
    required String message,
  }) async {
    final encoded = Uri.encodeComponent(message);
    if (phone != null && phone.trim().isNotEmpty) {
      var cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.startsWith('0')) {
        cleanPhone = cleanPhone.substring(1);
      }
      if (!cleanPhone.startsWith('967') && cleanPhone.length == 9) {
        cleanPhone = '967$cleanPhone';
      }
      final whatsappUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encoded');
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        return;
      }
    }
    await Share.share(message);
  }

  /// صياغة سند قبض نصي فوري للزبون بعد السداد (صفحة 4)
  static String buildCustomerReceiptText({
    required String shopName,
    required String customerName,
    required double paidAmount,
    required String method,
    required double remainingAlayh,
    required double remainingLah,
    required String currency,
  }) {
    final methodStr = method == 'CASH' ? 'نقدًا' : 'حوالة مالية';
    final balanceStr = remainingAlayh > 0
        ? 'المتبقي عليكم: ${AppFormatters.formatMoney(remainingAlayh, currency: currency)}'
        : (remainingLah > 0
            ? 'رصيدكم الدائن (لكم): ${AppFormatters.formatMoney(remainingLah, currency: currency)}'
            : 'الرصيد الحالي: مصفر (0)');

    return '''
🌿 *$shopName* 🌿
*سند قبض سداد*
━━━━━━━━━━━━━━
👤 الزبون: *$customerName*
💵 المبلغ المستلم: *${AppFormatters.formatMoney(paidAmount, currency: currency)}*
💳 طريقة الدفع: $methodStr
📅 التاريخ: ${AppFormatters.formatDateTime(DateTime.now())}
━━━━━━━━━━━━━━
📊 *$balanceStr*
شكرًا لتعاملكم معنا.
'''
        .trim();
  }

  /// صياغة ملخص وإقفال اليومية للمشاركة بضغطة زر (صفحة 2 و 10)
  static String buildDailyClosingSummaryText({
    required AppSettingsEntity settings,
    required DashboardSummaryEntity summary,
  }) {
    final c = settings.currency;
    return '''
🌿 *${settings.shopName} - ملخص وإقفال اليومية* 🌿
📅 التاريخ: ${AppFormatters.formatDate(DateTime.now())}
━━━━━━━━━━━━━━
💰 إجمالي مبيعات اليوم: *${AppFormatters.formatMoney(summary.todayTotalSales, currency: c)}*
   • مبيعات نقد/حوالة: ${AppFormatters.formatMoney(summary.todayCashSales, currency: c)}
   • مبيعات آجلة: ${AppFormatters.formatMoney(summary.todayCreditSales, currency: c)}
📥 إجمالي المحصل اليوم: *${AppFormatters.formatMoney(summary.todayCollectedFromCustomers, currency: c)}*
📦 إجمالي مشتريات اليوم: *${AppFormatters.formatMoney(summary.todayPurchasesTotal, currency: c)}*
📊 تكلفة البضاعة المباعة: *${summary.todayProfitIsReliable ? AppFormatters.formatMoney(summary.todayCogs, currency: c) : 'غير متاحة بدقة'}*
🍂 قيمة التالف اليوم: *${AppFormatters.formatMoney(summary.todayWastageCost, currency: c)}*
🛠️ مصاريف العمل اليوم: *${AppFormatters.formatMoney(summary.todayWorkExpenses, currency: c)}*
━━━━━━━━━━━━━━
📈 *صافي ربح العمل اليومي:* *${summary.todayProfitIsReliable ? AppFormatters.formatMoney(summary.todayNetWorkProfit, currency: c) : 'غير متاح بدقة لعدم اكتمال بيانات التكلفة'}*
🏠 المسحوبات الشخصية (منفصلة): ${AppFormatters.formatMoney(summary.todayPersonalExpenses, currency: c)}
━━━━━━━━━━━━━━
🗄️ الصندوق النقدي (الدرج): *${AppFormatters.formatMoney(summary.cashDrawerBalance, currency: c)}*
🏦 رصيد الحوالات والمحافظ: *${AppFormatters.formatMoney(summary.transferBalance, currency: c)}*
👥 إجمالي ديون الزبائن (عليهم): *${AppFormatters.formatMoney(summary.totalCustomersAlayh, currency: c)}*
🚛 إجمالي ديون الموردين (لهم): *${AppFormatters.formatMoney(summary.totalSuppliersLah, currency: c)}*
'''
        .trim();
  }

  /// توليد ومشاركة ملف PDF لكشف الحساب التفصيلي («مفصل») للزبون أو المورد باللغة العربية
  static Future<void> generateAndShareStatementPdf({
    required String shopName,
    required String partyTitle,
    required String partyName,
    required String summaryBalanceText,
    required List<StatementLineEntity> lines,
    required String currency,
  }) async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBoldFont = await PdfGoogleFonts.cairoBold();

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBoldFont,
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#1B4D3E'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      shopName,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'تقرير كشف حساب مفصل - $partyTitle: $partyName',
                      style: const pw.TextStyle(
                          color: PdfColors.white, fontSize: 13),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'التاريخ: ${AppFormatters.formatDate(DateTime.now())}',
                      style: const pw.TextStyle(
                          color: PdfColors.white, fontSize: 11),
                    ),
                    pw.Text(
                      summaryBalanceText,
                      style: pw.TextStyle(
                        color: PdfColors.amber200,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              'الحالة',
              'الرصيد',
              'له',
              'عليه',
              'البيان والتفاصيل',
              'العملية',
              'التاريخ'
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#2E7D32'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellAlignment: pw.Alignment.centerRight,
            data: lines.map((l) {
              return [
                l.balanceLabel,
                AppFormatters.formatMoney(l.runningBalance),
                l.creditLah > 0 ? AppFormatters.formatMoney(l.creditLah) : '-',
                l.debitAlayh > 0
                    ? AppFormatters.formatMoney(l.debitAlayh)
                    : '-',
                l.description,
                l.operationType,
                AppFormatters.formatDate(l.date),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final file = File(p.join(tempDir.path,
        'statement_${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'كشف حساب $partyTitle: $partyName - $summaryBalanceText',
    );
  }
}
