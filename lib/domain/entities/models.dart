/// الكيانات المحاسبية للتطبيق (Domain Entities)
class AppSettingsEntity {
  final int id;
  final String ownerName;
  final String shopName;
  final String phone;
  final String currency;
  final String? pinCode;
  final DateTime? lastBackupAt;
  final String? gdriveEmail;

  const AppSettingsEntity({
    required this.id,
    required this.ownerName,
    required this.shopName,
    required this.phone,
    required this.currency,
    this.pinCode,
    this.lastBackupAt,
    this.gdriveEmail,
  });

  AppSettingsEntity copyWith({
    String? ownerName,
    String? shopName,
    String? phone,
    String? currency,
    String? pinCode,
    bool clearPin = false,
    DateTime? lastBackupAt,
    String? gdriveEmail,
  }) {
    return AppSettingsEntity(
      id: id,
      ownerName: ownerName ?? this.ownerName,
      shopName: shopName ?? this.shopName,
      phone: phone ?? this.phone,
      currency: currency ?? this.currency,
      pinCode: clearPin ? null : (pinCode ?? this.pinCode),
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      gdriveEmail: gdriveEmail ?? this.gdriveEmail,
    );
  }
}

class SupplierEntity {
  final int id;
  final String name;
  final String? phone;
  final String? notes;
  final double balanceLah; // له: مستحق للمورد في ذمتنا
  final double balanceAlayh; // عليه: مستحق لنا في ذمة المورد
  final bool isActive;
  final DateTime createdAt;

  const SupplierEntity({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    required this.balanceLah,
    required this.balanceAlayh,
    required this.isActive,
    required this.createdAt,
  });

  bool get isSettled => balanceLah <= 0.001 && balanceAlayh <= 0.001;
}

class CustomerEntity {
  final int id;
  final String name;
  final String? phone;
  final String? notes;
  final double? creditLimit;
  final double balanceAlayh; // عليه: مديونية على الزبون لصالحنا
  final double balanceLah; // له: رصيد دائن للزبون عندنا
  final bool isActive;
  final DateTime createdAt;

  const CustomerEntity({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    this.creditLimit,
    required this.balanceAlayh,
    required this.balanceLah,
    required this.isActive,
    required this.createdAt,
  });

  bool get isSettled => balanceAlayh <= 0.001 && balanceLah <= 0.001;
}

class ItemEntity {
  final int id;
  final String name;
  final int? defaultSupplierId;
  final String? supplierName;
  final String unitName;
  final double currentQty;
  final double lastBuyPrice;
  final double averageCost;
  final String costStatus;
  final double defaultSellPrice;
  final bool isActive;

  const ItemEntity({
    required this.id,
    required this.name,
    this.defaultSupplierId,
    this.supplierName,
    required this.unitName,
    required this.currentQty,
    required this.lastBuyPrice,
    required this.averageCost,
    required this.costStatus,
    required this.defaultSellPrice,
    required this.isActive,
  });
}

class PurchaseEntity {
  final int id;
  final int supplierId;
  final String supplierName;
  final int itemId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final String paymentMethod; // CASH / TRANSFER
  final String? transferRef;
  final bool isSettled;
  final bool isReversed;
  final DateTime createdAt;

  const PurchaseEntity({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentMethod,
    this.transferRef,
    required this.isSettled,
    required this.isReversed,
    required this.createdAt,
  });
}

class SaleEntity {
  final int id;
  final int itemId;
  final String itemName;
  final String saleType; // CASH / CREDIT
  final int? customerId;
  final String? customerName;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final String paymentMethod; // CASH / TRANSFER
  final double? cogsAmount;
  final String costStatus;
  final double provisionalQuantity;
  final double returnedQuantity;
  final double returnedAmount;
  final double returnedCogs;
  final double refundedAmount;
  final double creditAmount;
  final String status; // ACTIVE / RETURNED
  final DateTime? returnedAt;
  final String? returnNotes;
  final DateTime createdAt;

  const SaleEntity({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.saleType,
    this.customerId,
    this.customerName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentMethod,
    required this.cogsAmount,
    required this.costStatus,
    required this.provisionalQuantity,
    required this.returnedQuantity,
    required this.returnedAmount,
    required this.returnedCogs,
    required this.refundedAmount,
    required this.creditAmount,
    required this.status,
    this.returnedAt,
    this.returnNotes,
    required this.createdAt,
  });

  bool get isReturned => status == 'RETURNED';
  double get returnableQuantity => quantity - returnedQuantity;
  double get netSalesAmount => totalAmount - returnedAmount;
}

class WastageEntity {
  final int id;
  final int itemId;
  final String itemName;
  final double quantity;
  final double estimatedCost;
  final String costStatus;
  final String notes;
  final bool isReversed;
  final DateTime createdAt;

  const WastageEntity({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.estimatedCost,
    required this.costStatus,
    required this.notes,
    required this.isReversed,
    required this.createdAt,
  });
}

class PaymentEntity {
  final int id;
  final String partyType; // CUSTOMER / SUPPLIER
  final int partyId;
  final String partyName;
  final double amount;
  final String method; // CASH / TRANSFER
  final String? transferCompany;
  final String? transferNumber;
  final String? notes;
  final bool isReversed;
  final DateTime createdAt;

  const PaymentEntity({
    required this.id,
    required this.partyType,
    required this.partyId,
    required this.partyName,
    required this.amount,
    required this.method,
    this.transferCompany,
    this.transferNumber,
    this.notes,
    required this.isReversed,
    required this.createdAt,
  });
}

class ExpenseEntity {
  final int id;
  final String categoryType; // WORK / PERSONAL
  final String title;
  final double amount;
  final String paymentMethod; // CASH / TRANSFER
  final String? notes;
  final bool isReversed;
  final DateTime createdAt;

  const ExpenseEntity({
    required this.id,
    required this.categoryType,
    required this.title,
    required this.amount,
    required this.paymentMethod,
    this.notes,
    required this.isReversed,
    required this.createdAt,
  });
}

class SaleReturnEntity {
  final int id;
  final int saleId;
  final double quantity;
  final double amount;
  final double? cogsAmount;
  final String costStatus;
  final double refundAmount;
  final String? refundMethod;
  final String? notes;
  final DateTime createdAt;

  const SaleReturnEntity({
    required this.id,
    required this.saleId,
    required this.quantity,
    required this.amount,
    required this.cogsAmount,
    required this.costStatus,
    required this.refundAmount,
    required this.refundMethod,
    required this.notes,
    required this.createdAt,
  });
}

/// عنصر في سجل «آخر العمليات» الموحد (صفحة 3)
class UnifiedOperationEntity {
  final String idKey;
  final String
      type; // SALE, PURCHASE, CUSTOMER_PAY, SUPPLIER_PAY, EXPENSE, RETURN, WASTAGE
  final String title;
  final String subtitle;
  final double amount;
  final String paymentMethod;
  final DateTime createdAt;
  final bool isPositiveCash;

  const UnifiedOperationEntity({
    required this.idKey,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.paymentMethod,
    required this.createdAt,
    required this.isPositiveCash,
  });
}

/// ملخص التطبيق ولوحة المؤشرات الفورية وإقفال اليومية (صفحة 3 وصفحة 7)
class DashboardSummaryEntity {
  final double
      todayTotalSales; // إجمالي مبيعات اليوم الصافية (نقد + آجل) بعد المرتجع
  final double todayCashSales; // مبيعات اليوم المحصلة نقدًا/حوالة
  final double todayCreditSales; // مبيعات اليوم الآجلة
  final double
      todayCollectedFromCustomers; // إجمالي المحصل اليوم (مبيعات مدفوعة + سدادات زبائن)
  final double todayPurchasesTotal; // إجمالي مشتريات اليوم
  final double todayWorkExpenses; // مصاريف العمل اليوم
  final double todayPersonalExpenses; // المصاريف الشخصية اليوم (مسحوبات منزلية)
  final double todayWastageCost; // قيمة التالف اليوم
  final double todayCogs; // تكلفة البضاعة المباعة فعليًا بعد المرتجعات
  final double
      todayNetWorkProfit; // المبيعات الصافية - COGS - التالف - مصاريف العمل
  final bool
      todayProfitIsReliable; // false when historical cost evidence is missing
  final double cashDrawerBalance; // صافي الصندوق النقدي الفعلي (الدرج)
  final double transferBalance; // صافي رصيد الحوالات والمحافظ الإلكترونية
  final double totalCustomersAlayh; // إجمالي الديون لنا عند الزبائن («عليهم»)
  final double totalCustomersLah; // إجمالي الرصيد الدائن للزبائن («لهم»)
  final double totalSuppliersLah; // إجمالي الديون علينا للموردين («لهم»)
  final double totalSuppliersAlayh; // إجمالي المبالغ لنا عند الموردين («عليهم»)

  const DashboardSummaryEntity({
    required this.todayTotalSales,
    required this.todayCashSales,
    required this.todayCreditSales,
    required this.todayCollectedFromCustomers,
    required this.todayPurchasesTotal,
    required this.todayWorkExpenses,
    required this.todayPersonalExpenses,
    required this.todayWastageCost,
    required this.todayCogs,
    required this.todayNetWorkProfit,
    required this.todayProfitIsReliable,
    required this.cashDrawerBalance,
    required this.transferBalance,
    required this.totalCustomersAlayh,
    required this.totalCustomersLah,
    required this.totalSuppliersLah,
    required this.totalSuppliersAlayh,
  });

  double get totalTreasury => cashDrawerBalance + transferBalance;
}

/// سطر في كشف الحساب التفصيلي («مفصل») للزبون أو المورد
class StatementLineEntity {
  final DateTime date;
  final String operationType;
  final String description;
  final double debitAlayh; // عليه
  final double creditLah; // له
  final double runningBalance;
  final String balanceLabel; // له / عليه / مصفر

  const StatementLineEntity({
    required this.date,
    required this.operationType,
    required this.description,
    required this.debitAlayh,
    required this.creditLah,
    required this.runningBalance,
    required this.balanceLabel,
  });
}
