import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/balance_badge.dart';
import '../../../core/widgets/custom_numeric_keypad.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/services/pdf_and_share_service.dart';
import '../../../domain/usecases/accounting_usecases.dart';

/// داخل صفحة المورد (صفحة 4 وصفحة 11):
/// تبويبان فرعيان كما في المخطط تمامًا:
/// أ) حسابه: يعرض الصافي (له / عليه) + زر «سداد» (نقد أو حوالة) + كشف الحساب (مفصل / مصفر).
/// ب) بضاعته: زر «الأصناف» (اختيار صنف موجود / إضافة صنف)، ونموذج «الشراء» (اختيار الصنف، الكمية، السعر، المدفوع، الإجمالي)، وأزرار تقارير (مصفر / مفصل).
class SupplierDetailScreen extends ConsumerStatefulWidget {
  final int supplierId;
  final int initialTabIndex;

  const SupplierDetailScreen({
    super.key,
    required this.supplierId,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<SupplierDetailScreen> createState() =>
      _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends ConsumerState<SupplierDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // حقول نموذج الشراء في قسم «بضاعته»
  int? _selectedItemId;
  double _buyQuantity = 1;
  double _buyUnitPrice = 0;
  double _paidAmount = 0;
  String _buyPaymentMethod = 'CASH';
  final _transferRefCtrl = TextEditingController();
  bool _isSavingPurchase = false;
  String _purchasesReportMode = 'DETAILED'; // DETAILED (مفصل) or SETTLED (مصفر)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _transferRefCtrl.dispose();
    super.dispose();
  }

  double get _totalPurchaseAmount => _buyQuantity * _buyUnitPrice;
  double get _remainingForSupplier => _totalPurchaseAmount - _paidAmount;

  Future<void> _showSupplierPaymentSheet(
      SupplierEntity supplier, String currency) async {
    double amount = supplier.balanceLah > 0 ? supplier.balanceLah : 0;
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
                      'سداد للمورد: ${supplier.name}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('نوع السداد:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('نقد (من الصندوق)'),
                          selected: method == 'CASH',
                          onSelected: (_) =>
                              setSheetState(() => method = 'CASH'),
                        ),
                        const SizedBox(width: 8),
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
                          title: 'مبلغ السداد للمورد',
                          initialValue: amount,
                        );
                        if (val != null) {
                          setSheetState(() => amount = val);
                        }
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
                              color: AppColors.primaryGreen),
                        ),
                      ),
                    ),
                    if (method == 'TRANSFER') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedWallet,
                        decoration: const InputDecoration(
                          labelText: 'اسم الشبكة / المحفظة',
                          prefixIcon: Icon(Icons.account_balance_outlined),
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
                          labelText: 'رقم الحوالة / الإشعار',
                          prefixIcon: Icon(Icons.tag),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        prefixIcon: Icon(Icons.notes),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'يرجى إدخال مبلغ سداد أكبر من صفر'),
                                    backgroundColor: AppColors.debtRed,
                                  ),
                                );
                                return;
                              }
                              setSheetState(() => isSubmitting = true);
                              await ref.read(appDatabaseProvider).recordPayment(
                                    partyType: 'SUPPLIER',
                                    partyId: supplier.id,
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
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'تم تسجيل سداد المورد وتحديث رصيده بنجاح'),
                                    backgroundColor: AppColors.cashGreen,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('حفظ السداد'),
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

  void _showAddNewItemDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '5000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة صنف قات جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف (مثال: عنسي، شامي، همداني)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'سعر البيع الافتراضي للربطة',
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
              if (nameCtrl.text.trim().isEmpty) return;
              final sellPrice = double.tryParse(priceCtrl.text.trim()) ?? 0;
              final newId = await ref.read(appDatabaseProvider).addOrUpdateItem(
                    name: nameCtrl.text.trim(),
                    defaultSupplierId: widget.supplierId,
                    defaultSellPrice: sellPrice,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                setState(() => _selectedItemId = newId);
              }
            },
            child: const Text('إضافة الصنف'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitPurchase() async {
    if (_isSavingPurchase) return;
    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار الصنف أولاً'),
            backgroundColor: AppColors.debtRed),
      );
      return;
    }
    if (_buyQuantity <= 0 || _buyUnitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال كمية وسعر شراء أكبر من صفر'),
          backgroundColor: AppColors.debtRed,
        ),
      );
      return;
    }

    // حالة استثنائية (صفحة 6): إذا كان «المدفوع» أكبر من «الإجمالي»، يُسجل الفرق كرصيد «عليه» (دفعة مقدمة) للمورد بعد التأكيد
    if (_paidAmount > _totalPurchaseAmount) {
      final diff = _paidAmount - _totalPurchaseAmount;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تنبيه: المدفوع أكبر من الإجمالي'),
          content: Text(
            'المبلغ المدفوع أكبر من إجمالي الفاتورة بمقدار (${AppFormatters.formatMoney(diff)}). هل تريد تسجيل الفرق كرصيد «عليه» (دفعة مقدمة للمورد)؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('تعديل المبلغ'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('نعم، تأكيد الحفظ'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSavingPurchase = true);
    try {
      await ref.read(recordSupplierPurchaseUseCaseProvider).execute(
            supplierId: widget.supplierId,
            itemId: _selectedItemId!,
            quantity: _buyQuantity,
            unitPrice: _buyUnitPrice,
            paidAmount: _paidAmount,
            paymentMethod: _buyPaymentMethod,
            transferRef: _transferRefCtrl.text.trim().isEmpty
                ? null
                : _transferRefCtrl.text.trim(),
          );
      if (mounted) {
        setState(() {
          _buyQuantity = 1;
          _buyUnitPrice = 0;
          _paidAmount = 0;
          _transferRefCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تم حفظ فاتورة الشراء وزيادة مخزون الصنف وتحديث حساب المورد'),
            backgroundColor: AppColors.cashGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.debtRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPurchase = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final itemsAsync = ref.watch(itemsStreamProvider);
    final settings = ref.watch(appSettingsStreamProvider).valueOrNull;
    final currency = settings?.currency ?? 'ر.ي';

    return FutureBuilder<SupplierEntity?>(
      future: db.getSupplierById(widget.supplierId),
      builder: (context, snapshot) {
        final supplier = snapshot.data;
        if (supplier == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('ملف المورد')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('المورد: ${supplier.name}'),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'حسابه (له / عليه / سداد)'),
                Tab(text: 'بضاعته (الأصناف + الشراء + تقارير)'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildSupplierAccountTab(supplier, settings, currency),
              _buildSupplierGoodsTab(
                  supplier, itemsAsync.valueOrNull ?? [], currency),
            ],
          ),
        );
      },
    );
  }

  /// أ) تبويب «حسابه»: يعرض الصافي (له / عليه) + زر «سداد» (نقد أو حوالة) + كشف الحساب
  Widget _buildSupplierAccountTab(
    SupplierEntity supplier,
    AppSettingsEntity? settings,
    String currency,
  ) {
    return FutureBuilder<List<StatementLineEntity>>(
      future: ref.read(appDatabaseProvider).getSupplierStatement(supplier.id),
      builder: (context, snap) {
        final lines = snap.data ?? [];
        final summaryText = supplier.balanceLah > 0
            ? 'له في ذمتنا: ${AppFormatters.formatMoney(supplier.balanceLah, currency: currency)}'
            : (supplier.balanceAlayh > 0
                ? 'عليه لنا: ${AppFormatters.formatMoney(supplier.balanceAlayh, currency: currency)}'
                : 'الحساب مصفر (0)');

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
                                supplier.name,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              if ((supplier.phone ?? '').isNotEmpty)
                                Text('الهاتف: ${supplier.phone}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        BalanceBadge(
                          balanceLah: supplier.balanceLah,
                          balanceAlayh: supplier.balanceAlayh,
                          isCustomer: false,
                          currency: currency,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            onPressed: () =>
                                _showSupplierPaymentSheet(supplier, currency),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('سداد للمورد (نقد / حوالة)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final pdfBtn = OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          onPressed: () {
                            PdfAndShareService.generateAndShareStatementPdf(
                              shopName: settings?.shopName ?? 'مقوت الخير',
                              partyTitle: 'المورد',
                              partyName: supplier.name,
                              summaryBalanceText: summaryText,
                              lines: lines,
                              currency: currency,
                            );
                          },
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('تصدير كشف حساب PDF'),
                        );

                        final whatsappBtn = OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          onPressed: () {
                            PdfAndShareService.shareViaWhatsApp(
                              phone: supplier.phone,
                              message:
                                  'كشف حساب المورد ${supplier.name}\n$summaryText',
                            );
                          },
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('مشاركة واتساب'),
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
                            const SizedBox(width: 8),
                            Expanded(child: whatsappBtn),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'كشف حساب المورد التفصيلي («مفصل» بالحركات)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (lines.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('لا توجد حركات مسجلة لهذا المورد بعد')),
                ),
              )
            else
              for (final l in lines)
                Card(
                  child: ListTile(
                    title: Text(l.operationType,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${l.description}\n${AppFormatters.formatDateTime(l.date)}'),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          l.creditLah > 0
                              ? 'له: +${AppFormatters.formatMoney(l.creditLah)}'
                              : 'سداد: -${AppFormatters.formatMoney(l.debitAlayh)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: l.creditLah > 0
                                ? AppColors.debtRed
                                : AppColors.cashGreen,
                          ),
                        ),
                        Text(
                          'الرصيد (${l.balanceLabel}): ${AppFormatters.formatMoney(l.runningBalance)}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  /// ب) تبويب «بضاعته»: الأصناف + نموذج الشراء + تقارير (مصفر / مفصل)
  Widget _buildSupplierGoodsTab(
    SupplierEntity supplier,
    List<ItemEntity> items,
    String currency,
  ) {
    if (_selectedItemId == null && items.isNotEmpty) {
      _selectedItemId = items.first.id;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'نموذج «الشراء» من المورد',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showAddNewItemDialog,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('+ صنف جديد'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _selectedItemId,
                  decoration: const InputDecoration(
                    labelText: 'الأصناف (اختر الصنف المشترى)',
                    prefixIcon: Icon(Icons.grass_outlined),
                  ),
                  items: items
                      .map(
                        (i) => DropdownMenuItem(
                          value: i.id,
                          child: Text(
                              '${i.name} (المتوفر: ${i.currentQty.toInt()} ${i.unitName})'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedItemId = val),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final val = await CustomNumericKeypad.show(
                            context,
                            title: 'الكمية المشتراة (ربطة)',
                            initialValue: _buyQuantity,
                            showQuickAmounts: false,
                          );
                          if (val != null) setState(() => _buyQuantity = val);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'الكمية',
                            prefixIcon: Icon(Icons.format_list_numbered),
                          ),
                          child: Text(
                            AppFormatters.formatQty(_buyQuantity),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final val = await CustomNumericKeypad.show(
                            context,
                            title: 'سعر شراء الربطة الواحدة',
                            initialValue: _buyUnitPrice,
                          );
                          if (val != null) setState(() => _buyUnitPrice = val);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'سعر الوحدة',
                            prefixIcon: Icon(Icons.price_change_outlined),
                          ),
                          child: Text(
                            AppFormatters.formatMoney(_buyUnitPrice),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // الإجمالي التلقائي = الكمية × السعر
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.scaffoldBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'الإجمالي (تلقائي = الكمية × السعر):',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppFormatters.formatMoney(_totalPurchaseAmount,
                            currency: currency),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final val = await CustomNumericKeypad.show(
                      context,
                      title: 'المبلغ المدفوع للمورد الآن',
                      initialValue: _paidAmount,
                    );
                    if (val != null) setState(() => _paidAmount = val);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText:
                          'المدفوع للمورد الآن (0 إذا كان الشراء بالآجل كاملاً)',
                      prefixIcon: Icon(Icons.paid_outlined),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            AppFormatters.formatMoney(_paidAmount,
                                currency: currency),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'المتبقي للمورد (له): ${AppFormatters.formatMoney(_remainingForSupplier)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _remainingForSupplier > 0
                                  ? AppColors.debtRed
                                  : AppColors.cashGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_paidAmount > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const Text('طريقة الدفع:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ChoiceChip(
                        label: const Text('نقد'),
                        selected: _buyPaymentMethod == 'CASH',
                        onSelected: (_) =>
                            setState(() => _buyPaymentMethod = 'CASH'),
                      ),
                      ChoiceChip(
                        label: const Text('حوالة'),
                        selected: _buyPaymentMethod == 'TRANSFER',
                        onSelected: (_) =>
                            setState(() => _buyPaymentMethod = 'TRANSFER'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _isSavingPurchase ? null : _submitPurchase,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ فاتورة الشراء'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            const Text(
              'تقارير بضاعته (مصفر / مفصل)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChoiceChip(
                  label: const Text('مفصل'),
                  selected: _purchasesReportMode == 'DETAILED',
                  onSelected: (_) =>
                      setState(() => _purchasesReportMode = 'DETAILED'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('مصفر'),
                  selected: _purchasesReportMode == 'SETTLED',
                  onSelected: (_) =>
                      setState(() => _purchasesReportMode = 'SETTLED'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<PurchaseEntity>>(
          future: ref.read(appDatabaseProvider).getPurchases(
                supplierId: supplier.id,
                settledOnly: _purchasesReportMode == 'SETTLED',
              ),
          builder: (context, snap) {
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      _purchasesReportMode == 'SETTLED'
                          ? 'لا توجد فواتير شراء مصفرة لهذا المورد'
                          : 'لا توجد فواتير شراء مسجلة لهذا المورد بعد',
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: list.map((p) {
                return Card(
                  child: ListTile(
                    title: Text(
                      '${p.itemName} (${p.quantity.toInt()} ربطة × ${AppFormatters.formatMoney(p.unitPrice)})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'الإجمالي: ${AppFormatters.formatMoney(p.totalAmount)} | المدفوع: ${AppFormatters.formatMoney(p.paidAmount)} | المتبقي: ${AppFormatters.formatMoney(p.remainingAmount)}\n${AppFormatters.formatDateTime(p.createdAt)}',
                    ),
                    isThreeLine: true,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.isSettled
                            ? AppColors.cashGreenBg
                            : AppColors.debtRedBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        p.isSettled ? 'مصفر' : 'متبقي',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: p.isSettled
                              ? AppColors.cashGreen
                              : AppColors.debtRed,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
