import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutabaati/core/database/app_database.dart';
import 'package:mutabaati/features/expenses/data/expense_repository.dart';
import 'package:mutabaati/features/expenses/domain/expense_draft.dart';

AppDatabase _openDb() => AppDatabase.forTesting(NativeDatabase.memory());

const _today = '2026-09-20';
const _yesterday = '2026-09-19';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;
  late String categoryId;

  setUp(() async {
    db = _openDb();
    repo = ExpenseRepository(db);
    categoryId = await repo.addCategory('طعام');
  });

  tearDown(() => db.close());

  group('ExpenseRepository – التصنيفات', () {
    test('إضافة تصنيف وقراءته', () async {
      final cats = await repo.watchCategories().first;
      expect(cats.length, 1);
      expect(cats.first.name, 'طعام');
    });

    test('رفض اسم التصنيف الفارغ', () {
      expect(
        () => repo.addCategory('   '),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ExpenseRepository – مصاريف اليوم', () {
    test('SPEC: 12.50 + 7.25 + 5.00 = 24.75 (بوحدات صغرى)', () async {
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 1250, localDate: _today),
      );
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 725, localDate: _today),
      );
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 500, localDate: _today),
      );
      final total = await repo.watchTotalForLocalDate(_today).first;
      expect(total, 2475);
    });

    test('SPEC: تعديل 7.25 إلى 8.00 → مجموع 25.50', () async {
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 1250, localDate: _today),
      );
      final draft725 = ExpenseDraft(
        categoryId: categoryId,
        amountMinor: 725,
        localDate: _today,
      );
      await repo.save(draft725);
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 500, localDate: _today),
      );

      // تحديد id السجل 725
      final before = await repo.watchForLocalDate(_today).first;
      final row725 = before.firstWhere((e) => e.amountMinor == 725);

      await repo.save(
        ExpenseDraft(
          id: row725.id,
          categoryId: categoryId,
          amountMinor: 800,
          localDate: _today,
        ),
      );

      final total = await repo.watchTotalForLocalDate(_today).first;
      expect(total, 2550);
    });

    test('SPEC: حذف 5.00 → مجموع 20.50', () async {
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 1250, localDate: _today),
      );
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 800, localDate: _today),
      );
      final draft500 = ExpenseDraft(
        categoryId: categoryId,
        amountMinor: 500,
        localDate: _today,
      );
      await repo.save(draft500);

      final before = await repo.watchForLocalDate(_today).first;
      final row500 = before.firstWhere((e) => e.amountMinor == 500);

      await repo.delete(row500.id);

      final total = await repo.watchTotalForLocalDate(_today).first;
      expect(total, 2050);
    });

    test('مصاريف يوم آخر لا تُضاف للمجموع', () async {
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 1000, localDate: _today),
      );
      await repo.save(
        ExpenseDraft(categoryId: categoryId, amountMinor: 500, localDate: _yesterday),
      );
      final total = await repo.watchTotalForLocalDate(_today).first;
      expect(total, 1000);
    });

    test('رفض المبلغ الصفري أو السالب', () {
      expect(
        () => repo.save(
          ExpenseDraft(
            categoryId: categoryId,
            amountMinor: 0,
            localDate: _today,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repo.save(
          ExpenseDraft(
            categoryId: categoryId,
            amountMinor: -1,
            localDate: _today,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('مجموع يوم بلا مصاريف يساوي صفرًا', () async {
      final total = await repo.watchTotalForLocalDate(_today).first;
      expect(total, 0);
    });
  });
}
