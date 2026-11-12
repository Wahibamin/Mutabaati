import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/custom_numeric_keypad.dart';
import '../../../data/local_db/app_database.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/usecases/accounting_usecases.dart';

/// التبويب 4: مبيعات (صفحة 4 وصفحة 11):
/// شريط تبديل علوي (4 أقسام حسب المخطط تمامًا):
/// [بيع] | [مرتجع] | [تالف] | [آخر الحركات]
/// - يطبق قاعدة الثلاث نقرات (3-Taps Rule): (نقر على الصنف -> كتابة السعر -> نقر حفظ).
/// - يمنع تكرار النقر المزدوج على زر الحفظ (TC-09) مع إبقاء الشاشة جاهزة للعملية التالية فور الحفظ.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // حالة شاشة البيع السريع
  int? _selectedItemId;
  String _saleType = 'CASH'; // CASH (نقد) or CREDIT (آجل)
  int? _selectedCustomerId;
  double _quantity = 1;
  double _unitPrice = 5000;
  double _partialPaidAmount = 0;
  String _paymentMethod = 'CASH'; // CASH or TRANSFER
  bool _isSavingSale = false;

  // حالة شاشة التالف
  int? _wastageItemId;
  double _wastageQty = 1;
  final _wastageNotesCtrl = TextEditingController(text: 'قات بايت');
  bool _isSavingWastage = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _wastageNotesCtrl.dispose();
    super.dispose();
  }

  double get _totalSaleAmount => _quantity * _unitPrice;

  Future<void> _saveQuickSale(List<ItemEntity> items) async {
    // منع تكرار تسجيل الفاتورة عند النقر المتتالي السريع (TC-09)
    if (_isSavingSale) return;

    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى تحديد الصنف أولاً'),
            backgroundColor: AppColors.debtRed),
      );
      return;
    }
    if (_quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى إدخال كمية أكبر من صفر'),
            backgroundColor: AppColors.debtRed),
      );
      return;
    }
    if (_unitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى إدخال سعر البيع أكبر من صفر'),
            backgroundColor: AppColors.debtRed),
      );
      return;
    }
    if (_saleType == 'CREDIT' && _selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تنبيه: لا يُسمح بحفظ بيع «آجل» بدون اختيار الزبون'),
          backgroundColor: AppColors.debtRed,
        ),
      );
      return;
    }

    // تنبيه غير مانع إذا كانت الكمية المباعة أكبر من المسجلة في الشراء (صفحة 6)
    final currentItem = items.where((i) => i.id == _selectedItemId).firstOrNull;
    if (currentItem != null &&
        _quantity > currentItem.currentQty &&
        currentItem.currentQty > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'تنبيه: الكمية المباعة أكبر من الكمية المتبقية في المخزون (تم السماح بالبيع المباشر)'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    setState(() => _isSavingSale = true);
    try {
      await ref.read(recordSaleUseCaseProvider).execute(
            itemId: _selectedItemId!,
            saleType: _saleType,
            customerId: _saleType == 'CREDIT' ? _selectedCustomerId : null,
            quantity: _quantity,
            unitPrice: _unitPrice,
            paidAmount:
                _saleType == 'CASH' ? _totalSaleAmount : _partialPaidAmount,
            paymentMethod: _paymentMethod,
          );

      if (mounted) {
        setState(() {
          _quantity = 1;
          _partialPaidAmount = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _saleType == 'CASH'
                  ? 'تم حفظ البيع النقدي (${AppFormatters.formatMoney(_totalSaleAmount)}) بنجاح'
                  : 'تم حفظ البيع الآجل وتحديث حساب الزبون بنجاح',
            ),
            backgroundColor: AppColors.cashGreen,
            duration: const Duration(milliseconds: 1400),
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
      if (mounted) setState(() => _isSavingSale = false);
    }
  }

  void _showQuickAddCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة زبون سريع'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الزبون *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'رقم الهاتف (اختياري)'),
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
              final newId = await ref.read(appDatabaseProvider).saveCustomer(
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) setState(() => _selectedCustomerId = newId);
            },
            child: const Text('حفظ واختيار'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsStreamProvider);
    final customersAsync = ref.watch(customersStreamProvider);
    final salesAsync = ref.watch(salesStreamProvider);
    final wastageAsync = ref.watch(wastageStreamProvider);
    final currency =
        ref.watch(appSettingsStreamProvider).valueOrNull?.currency ?? 'ر.ي';

    final items = itemsAsync.valueOrNull ?? [];
    final customers = customersAsync.valueOrNull ?? [];
    final sales = salesAsync.valueOrNull ?? [];
    final wastages = wastageAsync.valueOrNull ?? [];

    if (_selectedItemId == null && items.isNotEmpty) {
      _selectedItemId = items.first.id;
      _unitPrice = items.first.defaultSellPrice > 0
          ? items.first.defaultSellPrice
          : 5000;
    }
    if (_wastageItemId == null && items.isNotEmpty) {
      _wastageItemId = items.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('قسم المبيعات والمرتجع والتالف'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'بيع'),
            Tab(text: 'مرتجع'),
            Tab(text: 'تالف'),
            Tab(text: 'آخر الحركات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQuickSaleTab(items, customers, currency),
          _buildReturnsTab(sales, currency),
          _buildWastageTab(items, wastages, currency),
          _buildSalesHistoryTab(sales, wastages, currency),
        ],
      ),
    );
  }

  /// 1. شاشة البيع السريع (الافتراضية) وفق قاعدة الثلاث نقرات (3-Taps Rule)
  Widget _buildQuickSaleTab(
    List<ItemEntity> items,
    List<CustomerEntity> customers,
    String currency,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        // النقرة 1: شبكة أزرار سريعة لـ «تحديد الصنف»
        const Text(
          '1. تحديد الصنف (نقرة واحدة):',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final isSelected = _selectedItemId == item.id;
            return ChoiceChip(
              label: Text(
                '${item.name} (${item.currentQty.toInt()})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: AppColors.primaryGreen,
              onSelected: (_) {
                setState(() {
                  _selectedItemId = item.id;
                  if (item.defaultSellPrice > 0) {
                    _unitPrice = item.defaultSellPrice;
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // مفتاح تبديل كبير «نوع البيع: نقد / آجل»
        const Text(
          '2. نوع البيع (نقد / آجل):',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _saleType = 'CASH'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    color: _saleType == 'CASH'
                        ? AppColors.cashGreen
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _saleType == 'CASH'
                          ? AppColors.cashGreen
                          : AppColors.borderLight,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        color: _saleType == 'CASH'
                            ? Colors.white
                            : AppColors.cashGreen,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'بيع نقد',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _saleType == 'CASH'
                                ? Colors.white
                                : AppColors.cashGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _saleType = 'CREDIT'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    color: _saleType == 'CREDIT'
                        ? AppColors.debtRed
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _saleType == 'CREDIT'
                          ? AppColors.debtRed
                          : AppColors.borderLight,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_pin_outlined,
                        color: _saleType == 'CREDIT'
                            ? Colors.white
                            : AppColors.debtRed,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'بيع آجل (على الحساب)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _saleType == 'CREDIT'
                                ? Colors.white
                                : AppColors.debtRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // عند اختيار «آجل» يظهر حقل «اختر زبون» أو إضافة زبون سريع
        if (_saleType == 'CREDIT') ...[
          const SizedBox(height: 12),
          Card(
            color: AppColors.debtRedBg.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedCustomerId,
                          decoration: const InputDecoration(
                            labelText: 'اختر الزبون (إلزامي في البيع الآجل)',
                            prefixIcon: Icon(Icons.person_search_outlined),
                          ),
                          items: customers
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                      '${c.name} (عليه: ${c.balanceAlayh.toInt()})'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedCustomerId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'إضافة زبون سريع',
                        onPressed: _showQuickAddCustomerDialog,
                        icon: const Icon(Icons.person_add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final val = await CustomNumericKeypad.show(
                        context,
                        title: 'دفعة جزئية مقدمة من الزبون (اختياري)',
                        initialValue: _partialPaidAmount,
                      );
                      if (val != null) setState(() => _partialPaidAmount = val);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText:
                            'المدفوع مقدمًا (اتركه 0 إذا كان كامل المبلغ آجلاً)',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            AppFormatters.formatMoney(_partialPaidAmount,
                                currency: currency),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'المتبقي آجل (عليه): ${AppFormatters.formatMoney(_totalSaleAmount - _partialPaidAmount)}',
                            style: const TextStyle(
                                color: AppColors.debtRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // النقرة 2: الكمية والسعر المرن («يمكن أن يدخل سعر» بحرية)
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;

            final qtyField = InkWell(
              onTap: () async {
                final val = await CustomNumericKeypad.show(
                  context,
                  title: 'الكمية المباعة (ربطة)',
                  initialValue: _quantity,
                  showQuickAmounts: false,
                );
                if (val != null) setState(() => _quantity = val);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'الكمية (ربطة)',
                  prefixIcon: Icon(Icons.exposure_plus_1),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        _quantity.toInt().toString(),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            if (_quantity > 1) setState(() => _quantity -= 1);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.remove_circle_outline,
                                size: 22, color: AppColors.debtRed),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() => _quantity += 1),
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.add_circle_outline,
                                size: 22, color: AppColors.primaryGreen),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );

            final priceField = InkWell(
              onTap: () async {
                final val = await CustomNumericKeypad.show(
                  context,
                  title: 'سعر البيع الفعلي (مرن)',
                  initialValue: _unitPrice,
                );
                if (val != null) setState(() => _unitPrice = val);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'السعر (اضغط للتعديل)',
                  prefixIcon: Icon(Icons.sell_outlined),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    AppFormatters.formatMoney(_unitPrice, currency: currency),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              ),
            );

            if (isNarrow) {
              return Column(
                children: [
                  qtyField,
                  const SizedBox(height: 10),
                  priceField,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: qtyField),
                const SizedBox(width: 10),
                Expanded(child: priceField),
              ],
            );
          },
        ),

        const SizedBox(height: 10),
        // أزرار فئات سعرية فورية لتغيير السعر بنقرة واحدة
        Builder(
          builder: (context) {
            final chipHeight =
                (44 * MediaQuery.textScalerOf(context).scale(1.0))
                    .clamp(42.0, 64.0);
            return SizedBox(
              height: chipHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  2000.0,
                  3000.0,
                  4000.0,
                  5000.0,
                  6000.0,
                  8000.0,
                  10000.0,
                  15000.0
                ].map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ActionChip(
                      backgroundColor: _unitPrice == p
                          ? AppColors.cashGreenBg
                          : Colors.white,
                      label: Text(
                        AppFormatters.formatMoney(p),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _unitPrice == p
                              ? AppColors.primaryGreen
                              : AppColors.textPrimary,
                        ),
                      ),
                      onPressed: () => setState(() => _unitPrice = p),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),

        if (_saleType == 'CASH' || _partialPaidAmount > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Text('وسيلة القبض:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ChoiceChip(
                label: const Text('نقد في الدرج'),
                selected: _paymentMethod == 'CASH',
                onSelected: (_) => setState(() => _paymentMethod = 'CASH'),
              ),
              ChoiceChip(
                label: const Text('حوالة / محفظة إلكترونية'),
                selected: _paymentMethod == 'TRANSFER',
                onSelected: (_) => setState(() => _paymentMethod = 'TRANSFER'),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // النقرة 3: زر «حفظ البيع» بحجم كبير في أسفل الشاشة
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _saleType == 'CASH' ? AppColors.cashGreen : AppColors.debtRed,
            minimumSize: const Size(double.infinity, 58),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: _isSavingSale ? null : () => _saveQuickSale(items),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'حفظ البيع (${AppFormatters.formatMoney(_totalSaleAmount, currency: currency)})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 2. شاشة المرتجع: (اختر الحركة > تراجع عنها) مع عكس الأثر المالي والمخزني تلقائيًا (TC-06)
  Widget _buildReturnsTab(List<SaleEntity> sales, String currency) {
    if (sales.isEmpty) {
      return const Center(child: Text('لا توجد عمليات بيع مسجلة بعد'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sales.length,
      itemBuilder: (context, index) {
        final s = sales[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${s.itemName} (${s.quantity.toInt()} ربطة)',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: s.isReturned
                            ? AppColors.wastageGreyBg
                            : (s.saleType == 'CASH'
                                ? AppColors.cashGreenBg
                                : AppColors.debtRedBg),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.isReturned
                            ? 'مرتجعة'
                            : (s.saleType == 'CASH' ? 'بيع نقد' : 'بيع آجل'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: s.isReturned
                              ? AppColors.wastageGrey
                              : (s.saleType == 'CASH'
                                  ? AppColors.cashGreen
                                  : AppColors.debtRed),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'الإجمالي: ${AppFormatters.formatMoney(s.totalAmount, currency: currency)} • ${s.customerName != null ? 'الزبون: ${s.customerName}' : 'بيع مباشر'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  AppFormatters.formatDateTime(s.createdAt),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (s.isReturned)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'تم التراجع عنها بتاريخ ${AppFormatters.formatDateTime(s.returnedAt ?? s.createdAt)} (${s.returnNotes ?? ''})',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.wastageGrey,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                else ...[
                  if (s.returnedQuantity > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'مرتجع جزئي: ${s.returnedQuantity} من ${s.quantity}',
                        style: const TextStyle(
                          color: AppColors.warningOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.debtRed,
                        side: const BorderSide(color: AppColors.debtRed),
                      ),
                      onPressed: () => _confirmReturnSale(s, currency),
                      icon: const Icon(Icons.undo),
                      label: const Text('تراجع عنها (مرتجع)'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmReturnSale(SaleEntity sale, String currency) {
    final reasonCtrl = TextEditingController(text: 'مرتجع من الزبون');
    final quantityCtrl = TextEditingController(
      text: sale.returnableQuantity.toString(),
    );
    final grossReturn = sale.returnableQuantity * sale.unitPrice;
    final refundable = sale.paidAmount - sale.refundedAmount;
    final defaultRefund = refundable <= 0
        ? 0.0
        : (refundable < grossReturn ? refundable : grossReturn);
    final refundCtrl = TextEditingController(text: defaultRefund.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التراجع عن عملية البيع (مرتجع)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الكمية المتاحة للإرجاع: ${sale.returnableQuantity}. افصل مبلغ الرد النقدي/الحوالة عن الرصيد الدائن للزبون.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'كمية المرتجع'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refundCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ المردود الآن ($currency)',
                  helperText: 'ما لا يُرد يُعالج في حساب الزبون عند وجوده',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration:
                    const InputDecoration(labelText: 'سبب الإرجاع (اختياري)'),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () async {
              final quantity = double.tryParse(quantityCtrl.text.trim());
              final refund = double.tryParse(refundCtrl.text.trim());
              if (quantity == null || quantity <= 0 || refund == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال كمية ومبلغ مرتجع صالحين'),
                    backgroundColor: AppColors.debtRed,
                  ),
                );
                return;
              }
              await ref.read(returnSaleUseCaseProvider).executePartial(
                    saleId: sale.id,
                    quantity: quantity,
                    refundAmount: refund,
                    refundMethod: refund > 0 ? sale.paymentMethod : null,
                    returnNotes: reasonCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'تم تسجيل المرتجع وعكس الأثر المالي والمخزني بنجاح'),
                    backgroundColor: AppColors.cashGreen,
                  ),
                );
              }
            },
            child: const Text('تأكيد التراجع (مرتجع)'),
          ),
        ],
      ),
    );
  }

  /// 3. شاشة التالف: (اختيار الصنف، تحديد كمية، عمل ملاحظات) لحسابه ضمن خسائر البضاعة (TC-07)
  Widget _buildWastageTab(
    List<ItemEntity> items,
    List<WastageEntity> wastages,
    String currency,
  ) {
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
                  'تسجيل القات التالف أو البايت',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'يُنقص الكمية المتاحة من الصنف ويُسجل ضمن خسائر البضاعة دون المساس بالصندوق النقدي.',
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _wastageItemId,
                  decoration: const InputDecoration(
                    labelText: 'اختيار الصنف',
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
                  onChanged: (v) => setState(() => _wastageItemId = v),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final val = await CustomNumericKeypad.show(
                      context,
                      title: 'تحديد الكمية التالفة (ربطة)',
                      initialValue: _wastageQty,
                      showQuickAmounts: false,
                    );
                    if (val != null) setState(() => _wastageQty = val);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تحديد الكمية التالفة',
                      prefixIcon: Icon(Icons.production_quantity_limits),
                    ),
                    child: Text(
                      AppFormatters.formatQty(_wastageQty),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wastageNotesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عمل ملاحظات (قات بايت، يابس، تالف)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.wastageGrey),
                  onPressed: _isSavingWastage
                      ? null
                      : () async {
                          if (_wastageItemId == null || _wastageQty <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'يرجى تحديد الصنف وكمية التالف أكبر من صفر'),
                                backgroundColor: AppColors.debtRed,
                              ),
                            );
                            return;
                          }
                          setState(() => _isSavingWastage = true);
                          try {
                            await ref.read(appDatabaseProvider).recordWastage(
                                  itemId: _wastageItemId!,
                                  quantity: _wastageQty,
                                  notes: _wastageNotesCtrl.text.trim(),
                                );
                            if (mounted) {
                              setState(() => _wastageQty = 1);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'تم تسجيل القات التالف وخصمه من المخزون بنجاح'),
                                  backgroundColor: AppColors.cashGreen,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isSavingWastage = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حفظ سجل التالف'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'سجل التالف والخسائر (${wastages.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final w in wastages)
          Card(
            child: ListTile(
              title: Text(
                '${w.itemName} (${w.quantity.toInt()} ربطة)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${w.notes} • التكلفة التقديرية: ${AppFormatters.formatMoney(w.estimatedCost, currency: currency)}\n${AppFormatters.formatDateTime(w.createdAt)}',
              ),
              isThreeLine: true,
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(appDatabaseProvider).reverseWastage(w.id);
                },
                child: const Text('تراجع'),
              ),
            ),
          ),
      ],
    );
  }

  /// 4. قائمة آخر الحركات لقسم المبيعات والمرتجعات والتالف
  Widget _buildSalesHistoryTab(
    List<SaleEntity> sales,
    List<WastageEntity> wastages,
    String currency,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'سجل حركات المبيعات والمرتجعات والتالف',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (sales.isEmpty && wastages.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('لا توجد حركات في قسم المبيعات بعد')),
            ),
          ),
        for (final s in sales)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: s.isReturned
                    ? AppColors.wastageGreyBg
                    : (s.saleType == 'CASH'
                        ? AppColors.cashGreenBg
                        : AppColors.debtRedBg),
                child: Icon(
                  s.isReturned ? Icons.undo : Icons.point_of_sale,
                  color: s.isReturned
                      ? AppColors.wastageGrey
                      : (s.saleType == 'CASH'
                          ? AppColors.cashGreen
                          : AppColors.debtRed),
                ),
              ),
              title: Text(
                '${s.isReturned ? '[مرتجع] ' : ''}${s.itemName} (${s.quantity.toInt()} ربطة)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${s.saleType == 'CASH' ? 'نقد' : 'آجل - ${s.customerName ?? ''}'} • ${AppFormatters.formatDateTime(s.createdAt)}',
              ),
              trailing: Text(
                AppFormatters.formatMoney(s.totalAmount, currency: currency),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: s.isReturned
                      ? AppColors.wastageGrey
                      : AppColors.primaryGreen,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
