import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local_db/app_database.dart';

final recordSaleUseCaseProvider = Provider<RecordSaleUseCase>((ref) {
  return RecordSaleUseCase(ref.watch(appDatabaseProvider));
});

final returnSaleUseCaseProvider = Provider<ReturnSaleUseCase>((ref) {
  return ReturnSaleUseCase(ref.watch(appDatabaseProvider));
});

final recordSupplierPurchaseUseCaseProvider =
    Provider<RecordSupplierPurchaseUseCase>((ref) {
  return RecordSupplierPurchaseUseCase(ref.watch(appDatabaseProvider));
});

/// حالة استخدام تسجيل عملية بيع قات (نقد أو آجل أو دفع جزئي)
class RecordSaleUseCase {
  final AppDatabase _db;
  RecordSaleUseCase(this._db);

  Future<int> execute({
    required int itemId,
    required String saleType, // 'CASH' or 'CREDIT'
    int? customerId,
    required double quantity,
    required double unitPrice,
    double? paidAmount,
    String paymentMethod = 'CASH',
    String? requestKey,
  }) {
    return _db.recordSale(
      itemId: itemId,
      saleType: saleType,
      customerId: customerId,
      quantity: quantity,
      unitPrice: unitPrice,
      paidAmount: paidAmount,
      paymentMethod: paymentMethod,
      requestKey: requestKey,
    );
  }
}

/// حالة استخدام إرجاع عملية بيع سابقة (مرتجع > اختر الحركة > تراجع عنها)
class ReturnSaleUseCase {
  final AppDatabase _db;
  ReturnSaleUseCase(this._db);

  Future<void> execute({
    required int saleId,
    String returnNotes = 'مرتجع مبيعات',
  }) {
    return _db.returnSale(
      saleId: saleId,
      returnNotes: returnNotes,
    );
  }

  Future<int> executePartial({
    required int saleId,
    required double quantity,
    double? refundAmount,
    String? refundMethod,
    String returnNotes = 'مرتجع مبيعات',
  }) {
    return _db.returnSalePartial(
      saleId: saleId,
      quantity: quantity,
      refundAmount: refundAmount,
      refundMethod: refundMethod,
      returnNotes: returnNotes,
    );
  }
}

/// حالة استخدام تسجيل فاتورة شراء بضاعة من مورد
class RecordSupplierPurchaseUseCase {
  final AppDatabase _db;
  RecordSupplierPurchaseUseCase(this._db);

  Future<int> execute({
    required int supplierId,
    required int itemId,
    required double quantity,
    required double unitPrice,
    required double paidAmount,
    String paymentMethod = 'CASH',
    String? transferRef,
    String? requestKey,
  }) {
    return _db.recordSupplierPurchase(
      supplierId: supplierId,
      itemId: itemId,
      quantity: quantity,
      unitPrice: unitPrice,
      paidAmount: paidAmount,
      paymentMethod: paymentMethod,
      transferRef: transferRef,
      requestKey: requestKey,
    );
  }
}
