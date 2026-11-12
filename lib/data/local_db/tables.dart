import 'package:drift/drift.dart';

/// 1. جدول الإعدادات (app_settings) - صف وحيد رقم 1
class AppSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get ownerName =>
      text().withDefault(const Constant('مقوت الخير'))();
  TextColumn get shopName => text().withDefault(const Constant('محل القات'))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get currency => text().withDefault(const Constant('ر.ي'))();
  TextColumn get pinCode => text().nullable()();
  DateTimeColumn get lastBackupAt => dateTime().nullable()();
  TextColumn get gdriveEmail => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 2. جدول الموردين (suppliers)
/// لا يمكن أن يكون balance_lah (له) و balance_alayh (عليه) أكبر من صفر في نفس الوقت
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get balanceLah => real().withDefault(const Constant(0.0))();
  RealColumn get balanceAlayh => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 3. جدول الزبائن (customers)
/// صافي الرصيد المدين يوضع في balance_alayh (عليه) والدائن في balance_lah (له)
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get creditLimit =>
      real().nullable()(); // سقف الدين المسموح اختياريًا (صفحة 4)
  RealColumn get balanceAlayh => real().withDefault(const Constant(0.0))();
  RealColumn get balanceLah => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 4. جدول الأصناف (items)
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get defaultSupplierId =>
      integer().nullable().references(Suppliers, #id)();
  TextColumn get unitName => text().withDefault(const Constant('ربطة'))();
  RealColumn get currentQty => real().withDefault(const Constant(0.0))();
  RealColumn get lastBuyPrice => real().withDefault(const Constant(0.0))();
  RealColumn get averageCost => real().withDefault(const Constant(0.0))();
  TextColumn get costStatus => text().withDefault(const Constant('FINAL'))();
  RealColumn get defaultSellPrice => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// 5. جدول فواتير الشراء (purchases)
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  IntColumn get itemId => integer().references(Items, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get totalAmount => real()();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  RealColumn get remainingAmount => real()();
  TextColumn get paymentMethod =>
      text().withDefault(const Constant('CASH'))(); // CASH / TRANSFER
  RealColumn get cogsAmount => real().nullable()();
  TextColumn get costStatus => text().withDefault(const Constant('UNKNOWN'))();
  RealColumn get provisionalQuantity =>
      real().withDefault(const Constant(0.0))();
  RealColumn get provisionalCostAmount =>
      real().withDefault(const Constant(0.0))();
  RealColumn get returnedQuantity => real().withDefault(const Constant(0.0))();
  RealColumn get returnedAmount => real().withDefault(const Constant(0.0))();
  RealColumn get returnedCogs => real().withDefault(const Constant(0.0))();
  RealColumn get refundedAmount => real().withDefault(const Constant(0.0))();
  RealColumn get creditAmount => real().withDefault(const Constant(0.0))();
  TextColumn get transferRef => text().nullable()();
  BoolColumn get isSettled => boolean().withDefault(const Constant(false))();
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 6. جدول المبيعات والمرتجع (sales)
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId => integer().references(Items, #id)();
  TextColumn get saleType => text()(); // CASH / CREDIT
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get totalAmount => real()();
  RealColumn get paidAmount => real()();
  RealColumn get remainingAmount => real()();
  TextColumn get paymentMethod =>
      text().withDefault(const Constant('CASH'))(); // CASH / TRANSFER
  TextColumn get status =>
      text().withDefault(const Constant('ACTIVE'))(); // ACTIVE / RETURNED
  DateTimeColumn get returnedAt => dateTime().nullable()();
  TextColumn get returnNotes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 7. جدول سجل التالف (wastage_records)
class WastageRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId => integer().references(Items, #id)();
  RealColumn get quantity => real()();
  RealColumn get estimatedCost => real().withDefault(const Constant(0.0))();
  TextColumn get costStatus => text().withDefault(const Constant('UNKNOWN'))();
  TextColumn get notes => text()();
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 8. جدول السدادات (payments)
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get partyType => text()(); // CUSTOMER / SUPPLIER
  IntColumn get partyId => integer()();
  RealColumn get amount => real()();
  TextColumn get method => text()(); // CASH / TRANSFER
  TextColumn get transferCompany => text().nullable()();
  TextColumn get transferNumber => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 9. جدول المصاريف (expenses)
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get categoryType => text()(); // WORK / PERSONAL
  TextColumn get title => text()();
  RealColumn get amount => real()();
  TextColumn get paymentMethod =>
      text().withDefault(const Constant('CASH'))(); // CASH / TRANSFER
  TextColumn get notes => text().nullable()();
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class PaymentAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId => integer().references(Payments, #id)();
  TextColumn get documentType => text()();
  IntColumn get documentId => integer()();
  RealColumn get amount => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SaleReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  RealColumn get quantity => real()();
  RealColumn get amount => real()();
  RealColumn get cogsAmount => real().nullable()();
  TextColumn get costStatus => text().withDefault(const Constant('UNKNOWN'))();
  RealColumn get refundAmount => real().withDefault(const Constant(0.0))();
  TextColumn get refundMethod => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class TreasuryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryType => text()();
  RealColumn get amount => real()();
  TextColumn get fromMethod => text().nullable()();
  TextColumn get toMethod => text()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
