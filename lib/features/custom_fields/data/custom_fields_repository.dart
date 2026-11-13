import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

enum CustomFieldType {
  shortText,
  longText,
  number,
  yesNo,
  singleChoice,
  date,
  durationMinutes,
}

class CustomFieldsRepository {
  CustomFieldsRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<CustomFieldDefinition>> watchDefinitions(String ownerType) {
    final query = _database.select(_database.customFieldDefinitions)
      ..where(
        (field) =>
            field.ownerType.equals(ownerType) & field.archivedAt.isNull(),
      )
      ..orderBy([(field) => OrderingTerm.asc(field.sortOrder)]);
    return query.watch();
  }

  Future<List<CustomFieldDefinition>> getDefinitions(String ownerType) async {
    final query = _database.select(_database.customFieldDefinitions)
      ..where(
        (field) =>
            field.ownerType.equals(ownerType) & field.archivedAt.isNull(),
      )
      ..orderBy([(field) => OrderingTerm.asc(field.sortOrder)]);
    return query.get();
  }

  Future<void> createDefinition({
    required String ownerType,
    required String label,
    required CustomFieldType type,
    required int sortOrder,
    bool isRequired = false,
  }) async {
    final normalized = label.trim();
    if (normalized.isEmpty) throw const FormatException('عنوان الحقل مطلوب.');
    await _database
        .into(_database.customFieldDefinitions)
        .insert(
          CustomFieldDefinitionsCompanion.insert(
            id: _uuid.v7(),
            ownerType: ownerType,
            label: normalized,
            fieldType: type.name,
            sortOrder: sortOrder,
            isRequired: Value(isRequired),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> archiveDefinition(String id) async {
    await (_database.update(
      _database.customFieldDefinitions,
    )..where((field) => field.id.equals(id))).write(
      CustomFieldDefinitionsCompanion(
        archivedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// يحفظ قيمة حقل مخصص أو يحدّثها (upsert). يدعم النص والرقم والمنطقي والتاريخ.
  Future<void> saveValue({
    required String definitionId,
    required String ownerType,
    required String ownerId,
    String? valueText,
    int? valueInteger,
    bool? valueBoolean,
    DateTime? valueDate,
  }) async {
    final definition = await (_database.select(
      _database.customFieldDefinitions,
    )..where((field) => field.id.equals(definitionId))).getSingle();
    if (definition.ownerType != ownerType) {
      throw ArgumentError('الحقل لا ينتمي إلى هذا النوع من السجلات.');
    }
    await _database.transaction(() async {
      final existing = await (_database.select(_database.customFieldValues)
            ..where(
              (v) =>
                  v.definitionId.equals(definitionId) &
                  v.ownerType.equals(ownerType) &
                  v.ownerId.equals(ownerId),
            ))
          .getSingleOrNull();

      if (existing == null) {
        await _database.into(_database.customFieldValues).insert(
              CustomFieldValuesCompanion.insert(
                id: _uuid.v7(),
                definitionId: definitionId,
                ownerType: ownerType,
                ownerId: ownerId,
                valueText: Value(valueText),
                valueInteger: Value(valueInteger),
                valueBoolean: Value(valueBoolean),
                valueDate: Value(valueDate),
                createdAt: DateTime.now().toUtc(),
              ),
            );
      } else {
        await (_database.update(_database.customFieldValues)
              ..where((v) => v.id.equals(existing.id)))
            .write(
              CustomFieldValuesCompanion(
                valueText: Value(valueText),
                valueInteger: Value(valueInteger),
                valueBoolean: Value(valueBoolean),
                valueDate: Value(valueDate),
              ),
            );
      }
    });
  }

  /// للتوافق مع الاستدعاءات القديمة – يحفظ قيمة نصية فقط.
  Future<void> saveTextValue({
    required String definitionId,
    required String ownerType,
    required String ownerId,
    required String? value,
  }) => saveValue(
    definitionId: definitionId,
    ownerType: ownerType,
    ownerId: ownerId,
    valueText: value,
  );

  /// يعيد قيم الحقول المخصصة لسجل معين.
  Future<List<CustomFieldValue>> getValuesForOwner({
    required String ownerType,
    required String ownerId,
  }) async {
    final query = _database.select(_database.customFieldValues)
      ..where(
        (v) => v.ownerType.equals(ownerType) & v.ownerId.equals(ownerId),
      );
    return query.get();
  }

  Stream<List<CustomFieldValue>> watchValuesForOwner({
    required String ownerType,
    required String ownerId,
  }) {
    final query = _database.select(_database.customFieldValues)
      ..where(
        (v) => v.ownerType.equals(ownerType) & v.ownerId.equals(ownerId),
      );
    return query.watch();
  }
}
