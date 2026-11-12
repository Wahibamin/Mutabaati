import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local_db/app_database.dart';
import '../../domain/entities/models.dart';

final appSettingsStreamProvider = StreamProvider<AppSettingsEntity>((ref) {
  return ref.watch(appDatabaseProvider).watchAppSettings();
});

final dashboardSummaryStreamProvider =
    StreamProvider<DashboardSummaryEntity>((ref) {
  return ref.watch(appDatabaseProvider).watchDashboardSummary();
});

final itemsStreamProvider = StreamProvider<List<ItemEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchAllItems();
});

final suppliersStreamProvider = StreamProvider<List<SupplierEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchSuppliers();
});

final customersStreamProvider = StreamProvider<List<CustomerEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchCustomers();
});

final salesStreamProvider = StreamProvider<List<SaleEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchSales();
});

final wastageStreamProvider = StreamProvider<List<WastageEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchWastageRecords();
});

final expensesStreamProvider = StreamProvider<List<ExpenseEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchExpenses();
});

final recentOperationsStreamProvider =
    StreamProvider<List<UnifiedOperationEntity>>((ref) {
  return ref.watch(appDatabaseProvider).watchRecentUnifiedOperations(limit: 40);
});
