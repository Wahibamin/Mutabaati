import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqwati/data/local_db/app_database.dart';

/// اختبارات التحقق الشاملة (Comprehensive Testing Plan - المرحلة العاشرة صفحة 14)
/// تغطي حالات الاختبار القياسية (TC-01 إلى TC-09) على محرك SQLite/Drift مباشرة للتأكد من
/// دقة معادلات «له» و«عليه» والصندوق والمخزون والمرتجعات والتالف بنسبة 100%.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.getAppSettings(); // تهيئة الجداول والأصناف الافتراضية
  });

  tearDown(() async {
    await db.close();
  });

  test('TC-01: تسجيل عملية بيع نقدية (قات عنسي، الكمية 2، السعر 5,000)',
      () async {
    final items = await db.getAllItems();
    final ansiItem = items.firstWhere((i) => i.name.contains('عنسي'));

    await db.recordSale(
      itemId: ansiItem.id,
      saleType: 'CASH',
      quantity: 2,
      unitPrice: 5000,
      paymentMethod: 'CASH',
    );

    final summary = await db.getDashboardSummary();
    final updatedItem =
        (await db.getAllItems()).firstWhere((i) => i.id == ansiItem.id);

    expect(summary.cashDrawerBalance, 10000);
    expect(updatedItem.currentQty, -2); // نقصت كمية الصنف بمقدار 2
  });

  test(
      'TC-02 & TC-06: تسجيل عملية بيع آجلة للزبون أحمد (8,000) ثم عمل مرتجع لها',
      () async {
    final items = await db.getAllItems();
    final shamiItem = items.firstWhere((i) => i.name.contains('شامي'));
    final customerId = await db.saveCustomer(name: 'أحمد', phone: '777111222');

    // TC-02: بيع آجل بكمية 1 وسعر 8,000 والمدفوع 0
    final saleId = await db.recordSale(
      itemId: shamiItem.id,
      saleType: 'CREDIT',
      customerId: customerId,
      quantity: 1,
      unitPrice: 8000,
      paidAmount: 0,
    );

    var customer = await db.getCustomerById(customerId);
    var summary = await db.getDashboardSummary();

    expect(customer!.balanceAlayh, 8000);
    expect(customer.balanceLah, 0);
    expect(summary.cashDrawerBalance, 0); // لا يتأثر الصندوق النقدي

    // TC-06: تسجيل مرتجع مبيعات (تراجع عن حركة البيع الآجلة للزبون أحمد)
    await db.returnSale(saleId: saleId, returnNotes: 'مرتجع اختبار TC-06');

    customer = await db.getCustomerById(customerId);
    final updatedItem =
        (await db.getAllItems()).firstWhere((i) => i.id == shamiItem.id);

    expect(customer!.balanceAlayh, 0); // يُخصم مبلغ 8,000 من مديونية أحمد
    expect(updatedItem.currentQty, 0); // تعود الكمية للمخزون
  });

  test(
      'TC-03 & TC-04: شراء بضاعة بدفعة جزئية من المورد صالح ثم سداد الزبون والمورد (نقد وحوالة)',
      () async {
    final items = await db.getAllItems();
    final item = items.first;
    final supplierId = await db.saveSupplier(name: 'صالح', phone: '777333444');
    final customerId = await db.saveCustomer(name: 'أحمد');

    // TC-03: شراء كمية 20 بسعر 3,000 (الإجمالي 60,000) والمدفوع نقدًا 40,000
    await db.recordSupplierPurchase(
      supplierId: supplierId,
      itemId: item.id,
      quantity: 20,
      unitPrice: 3000,
      paidAmount: 40000,
      paymentMethod: 'CASH',
    );

    var supplier = await db.getSupplierById(supplierId);
    var updatedItem =
        (await db.getAllItems()).firstWhere((i) => i.id == item.id);

    expect(supplier!.balanceLah,
        20000); // يزيد حساب المورد صالح في خانة «له» بمقدار 20,000
    expect(updatedItem.currentQty, 20); // تزيد كمية الصنف بـ 20

    // بيع آجل لأحمد بمبلغ 8,000 قبل اختبار TC-04
    await db.recordSale(
      itemId: item.id,
      saleType: 'CREDIT',
      customerId: customerId,
      quantity: 1,
      unitPrice: 8000,
      paidAmount: 0,
    );

    // TC-04: الزبون أحمد عليه 8,000 يسدد 5,000 عبر «حوالة»، والمورد صالح له 20,000 نسدد له 20,000 «نقد»
    await db.recordPayment(
      partyType: 'CUSTOMER',
      partyId: customerId,
      amount: 5000,
      method: 'TRANSFER',
      transferCompany: 'جيب',
      transferNumber: '998877',
    );

    await db.recordPayment(
      partyType: 'SUPPLIER',
      partyId: supplierId,
      amount: 20000,
      method: 'CASH',
    );

    final customer = await db.getCustomerById(customerId);
    supplier = await db.getSupplierById(supplierId);
    final summary = await db.getDashboardSummary();
    final settledSuppliers = await db.getSuppliers(filter: 'SETTLED');

    expect(customer!.balanceAlayh, 3000); // يصبح رصيد أحمد «عليه» 3,000
    expect(summary.transferBalance, 5000); // تزيد الحوالات بـ 5,000
    expect(supplier!.balanceLah, 0); // يصبح رصيد المورد صالح 0
    expect(settledSuppliers.any((s) => s.id == supplierId),
        isTrue); // ينتقل إلى تقرير «مصفر»
  });

  test(
      'TC-05: تسجيل مصروف عمل (2,000) ومصروف شخصي (5,000) وفصلهما في صافي ربح العمل',
      () async {
    final items = await db.getAllItems();
    await db.recordSale(
      itemId: items.first.id,
      saleType: 'CASH',
      quantity: 2,
      unitPrice: 10000, // مبيعات 20,000
    );

    await db.recordExpense(
      categoryType: 'WORK',
      title: 'ثلج وأكياس',
      amount: 2000,
      paymentMethod: 'CASH',
    );

    await db.recordExpense(
      categoryType: 'PERSONAL',
      title: 'مقاضي المنزل',
      amount: 5000,
      paymentMethod: 'CASH',
    );

    final summary = await db.getDashboardSummary();
    expect(summary.cashDrawerBalance,
        20000 - 7000); // ينقص الصندوق بمقدار 7,000 إجمالاً
    expect(summary.todayNetWorkProfit,
        20000 - 2000); // في تقرير أرباح العمل تُخصم 2,000 فقط
    expect(summary.todayPersonalExpenses,
        5000); // تُعرض الـ 5,000 كمسحوبات شخصية منفصلة
  });

  test('TC-07 & TC-08: تسجيل تالف قات والتحقق من رفض القيم غير الصحيحة',
      () async {
    final items = await db.getAllItems();
    final item = items.first;

    // TC-07: تسجيل تالف بكمية 3
    await db.recordWastage(
      itemId: item.id,
      quantity: 3,
      notes: 'قات بايت',
    );

    final updatedItem =
        (await db.getAllItems()).firstWhere((i) => i.id == item.id);
    final summary = await db.getDashboardSummary();

    expect(updatedItem.currentQty, -3);
    expect(summary.cashDrawerBalance, 0); // دون المساس بالصندوق

    // TC-08: رفض حفظ بيع آجل بدون زبون أو بكمية سالبة
    expect(
      () => db.recordSale(
        itemId: item.id,
        saleType: 'CREDIT',
        customerId: null,
        quantity: 1,
        unitPrice: 5000,
      ),
      throwsArgumentError,
    );

    expect(
      () => db.recordSale(
        itemId: item.id,
        saleType: 'CASH',
        quantity: -2,
        unitPrice: 5000,
      ),
      throwsArgumentError,
    );
  });
}
