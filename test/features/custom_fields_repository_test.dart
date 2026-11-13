import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutabaati/core/database/app_database.dart';
import 'package:mutabaati/features/custom_fields/data/custom_fields_repository.dart';

AppDatabase _openDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late CustomFieldsRepository repo;

  setUp(() {
    db = _openDb();
    repo = CustomFieldsRepository(db);
  });

  tearDown(() => db.close());

  group('CustomFieldsRepository – تعريفات الحقول', () {
    test('إنشاء تعريف وقراءته', () async {
      await repo.createDefinition(
        ownerType: 'expense',
        label: 'رقم الفاتورة',
        type: CustomFieldType.shortText,
        sortOrder: 0,
      );
      final defs = await repo.getDefinitions('expense');
      expect(defs.length, 1);
      expect(defs.first.label, 'رقم الفاتورة');
      expect(defs.first.fieldType, 'shortText');
    });

    test('رفض العنوان الفارغ', () async {
      expect(
        () => repo.createDefinition(
          ownerType: 'expense',
          label: '   ',
          type: CustomFieldType.number,
          sortOrder: 0,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('أرشفة تعريف يُخفيه من watchDefinitions', () async {
      await repo.createDefinition(
        ownerType: 'expense',
        label: 'حقل مؤقت',
        type: CustomFieldType.yesNo,
        sortOrder: 0,
      );
      final beforeArchive = await repo.getDefinitions('expense');
      expect(beforeArchive.length, 1);

      await repo.archiveDefinition(beforeArchive.first.id);

      final afterArchive = await repo.getDefinitions('expense');
      expect(afterArchive, isEmpty);
    });
  });

  group('CustomFieldsRepository – قيم الحقول', () {
    late String defId;

    setUp(() async {
      await repo.createDefinition(
        ownerType: 'expense',
        label: 'ملاحظة إضافية',
        type: CustomFieldType.shortText,
        sortOrder: 0,
      );
      defId = (await repo.getDefinitions('expense')).first.id;
    });

    test('saveValue يحفظ قيمة نصية', () async {
      await repo.saveValue(
        definitionId: defId,
        ownerType: 'expense',
        ownerId: 'expense-001',
        valueText: 'قيمة اختبار',
      );
      final values = await repo.getValuesForOwner(
        ownerType: 'expense',
        ownerId: 'expense-001',
      );
      expect(values.length, 1);
      expect(values.first.valueText, 'قيمة اختبار');
    });

    test('saveValue يُحدّث القيمة عند تكرار الاستدعاء (upsert)', () async {
      await repo.saveValue(
        definitionId: defId,
        ownerType: 'expense',
        ownerId: 'expense-001',
        valueText: 'القيمة الأولى',
      );
      await repo.saveValue(
        definitionId: defId,
        ownerType: 'expense',
        ownerId: 'expense-001',
        valueText: 'القيمة المحدّثة',
      );
      final values = await repo.getValuesForOwner(
        ownerType: 'expense',
        ownerId: 'expense-001',
      );
      expect(values.length, 1);
      expect(values.first.valueText, 'القيمة المحدّثة');
    });

    test('saveValue يرفض النوع الخاطئ للسجل', () async {
      expect(
        () => repo.saveValue(
          definitionId: defId,
          ownerType: 'task', // مختلف عن 'expense'
          ownerId: 'task-001',
          valueText: 'خطأ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('saveValue يحفظ قيمة منطقية', () async {
      await repo.createDefinition(
        ownerType: 'expense',
        label: 'هل تمت المراجعة؟',
        type: CustomFieldType.yesNo,
        sortOrder: 1,
      );
      final yesNoDef = (await repo.getDefinitions('expense'))
          .firstWhere((d) => d.fieldType == 'yesNo');

      await repo.saveValue(
        definitionId: yesNoDef.id,
        ownerType: 'expense',
        ownerId: 'expense-002',
        valueBoolean: true,
      );
      final values = await repo.getValuesForOwner(
        ownerType: 'expense',
        ownerId: 'expense-002',
      );
      expect(values.length, 1);
      expect(values.first.valueBoolean, isTrue);
    });

    test('saveValue يحفظ قيمة رقمية', () async {
      await repo.createDefinition(
        ownerType: 'expense',
        label: 'عدد الوحدات',
        type: CustomFieldType.number,
        sortOrder: 2,
      );
      final numDef = (await repo.getDefinitions('expense'))
          .firstWhere((d) => d.fieldType == 'number');

      await repo.saveValue(
        definitionId: numDef.id,
        ownerType: 'expense',
        ownerId: 'expense-003',
        valueInteger: 42,
      );
      final values = await repo.getValuesForOwner(
        ownerType: 'expense',
        ownerId: 'expense-003',
      );
      expect(values.first.valueInteger, 42);
    });
  });
}
