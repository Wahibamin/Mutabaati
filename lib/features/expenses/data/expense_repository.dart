import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/expense_draft.dart';

class ExpenseRepository {
  ExpenseRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<Expense>> watchForLocalDate(String localDate) {
    final query = _database.select(_database.expenses)
      ..where((expense) => expense.localDate.equals(localDate))
      ..orderBy([(expense) => OrderingTerm.desc(expense.createdAt)]);
    return query.watch();
  }

  Stream<int> watchTotalForLocalDate(String localDate) =>
      watchForLocalDate(localDate).map(
        (expenses) =>
            expenses.fold(0, (sum, expense) => sum + expense.amountMinor),
      );

  Future<void> save(ExpenseDraft draft) async {
    if (draft.amountMinor <= 0) {
      throw ArgumentError.value(
        draft.amountMinor,
        'amountMinor',
        'يجب أن يكون المبلغ موجبًا.',
      );
    }
    final now = DateTime.now().toUtc();
    final companion = ExpensesCompanion(
      id: Value(draft.id ?? _uuid.v7()),
      categoryId: Value(draft.categoryId),
      amountMinor: Value(draft.amountMinor),
      localDate: Value(draft.localDate),
      note: Value(
        draft.note?.trim().isEmpty ?? true ? null : draft.note?.trim(),
      ),
      paymentMethod: Value(draft.paymentMethod),
      localTime: Value(draft.localTime),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    if (draft.id == null) {
      await _database.into(_database.expenses).insert(companion);
    } else {
      await (_database.update(
        _database.expenses,
      )..where((row) => row.id.equals(draft.id!))).write(companion);
    }
  }

  Future<void> delete(String id) => (_database.delete(
    _database.expenses,
  )..where((expense) => expense.id.equals(id))).go();

  Future<String> addCategory(String name, {int sortOrder = 0}) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('اسم التصنيف مطلوب.');
    final id = _uuid.v7();
    await _database
        .into(_database.expenseCategories)
        .insert(
          ExpenseCategoriesCompanion.insert(
            id: id,
            name: normalized,
            sortOrder: sortOrder,
            createdAt: DateTime.now().toUtc(),
          ),
        );
    return id;
  }

  Stream<List<ExpenseCategory>> watchCategories() {
    final query = _database.select(_database.expenseCategories)
      ..where((category) => category.archivedAt.isNull())
      ..orderBy([(category) => OrderingTerm.asc(category.sortOrder)]);
    return query.watch();
  }
}
