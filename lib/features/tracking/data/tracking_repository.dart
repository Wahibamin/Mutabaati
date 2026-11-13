import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/tracking_models.dart';

class TrackingRepository {
  TrackingRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  static const _worshipSectionId = 'system.worship';
  final AppDatabase _database;
  final Uuid _uuid;

  Future<void> applyInitialTemplates(
    Iterable<String> templateIds,
    String localDate,
  ) async {
    final requested = initialTemplateSeeds
        .where((template) => templateIds.contains(template.id))
        .toList();
    if (requested.isEmpty) return;
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await _database
          .into(_database.sections)
          .insertOnConflictUpdate(
            SectionsCompanion.insert(
              id: _worshipSectionId,
              name: 'العبادات',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final template in requested) {
        await _database
            .into(_database.activityTemplates)
            .insertOnConflictUpdate(
              ActivityTemplatesCompanion.insert(
                id: template.id,
                sectionId: const Value(_worshipSectionId),
                name: template.name,
                periodicity: template.period.name,
                trackingType: TrackingType.boolean.name,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _database
            .into(_database.scheduleVersions)
            .insertOnConflictUpdate(
              ScheduleVersionsCompanion.insert(
                id: 'seed.${template.id}.v1',
                templateId: template.id,
                effectiveStartLocalDate: localDate,
                periodicity: template.period.name,
                trackingType: TrackingType.boolean.name,
                targetValue: Value(template.target),
                createdAt: now,
              ),
            );
      }
    });
  }

  Stream<List<ActivityTemplate>> watchActiveTemplates() {
    final query = _database.select(_database.activityTemplates)
      ..where(
        (template) =>
            template.archivedAt.isNull() & template.isActive.equals(true),
      );
    return query.watch();
  }

  Stream<List<Section>> watchSections() {
    final query = _database.select(_database.sections)
      ..where((section) => section.archivedAt.isNull())
      ..orderBy([(section) => OrderingTerm.asc(section.sortOrder)]);
    return query.watch();
  }

  Future<String> addSection(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('اسم القسم مطلوب.');
    final id = _uuid.v7();
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.sections)
        .insert(
          SectionsCompanion.insert(
            id: id,
            name: normalized,
            sortOrder: 100,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> archiveSection(String id) =>
      (_database.update(
        _database.sections,
      )..where((section) => section.id.equals(id))).write(
        SectionsCompanion(
          archivedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> addTemplate({
    required String sectionId,
    required String name,
    required TrackingPeriod period,
    required TrackingType type,
    int target = 1,
    required String localDate,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('اسم البند مطلوب.');
    if (target <= 0) throw const FormatException('يجب أن يكون الهدف موجبًا.');
    final now = DateTime.now().toUtc();
    final templateId = _uuid.v7();
    await _database.transaction(() async {
      await _database
          .into(_database.activityTemplates)
          .insert(
            ActivityTemplatesCompanion.insert(
              id: templateId,
              sectionId: Value(sectionId),
              name: normalized,
              periodicity: period.name,
              trackingType: type.name,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _database
          .into(_database.scheduleVersions)
          .insert(
            ScheduleVersionsCompanion.insert(
              id: _uuid.v7(),
              templateId: templateId,
              effectiveStartLocalDate: localDate,
              periodicity: period.name,
              trackingType: type.name,
              targetValue: Value(target),
              createdAt: now,
            ),
          );
    });
  }

  Future<void> archiveTemplate(String id) =>
      (_database.update(
        _database.activityTemplates,
      )..where((template) => template.id.equals(id))).write(
        ActivityTemplatesCompanion(archivedAt: Value(DateTime.now().toUtc())),
      );

  /// يعيد نسخة الجدول الفعّالة (الأحدث) لبند معين.
  Future<ScheduleVersion?> getActiveScheduleVersion(String templateId) async {
    final query = _database.select(_database.scheduleVersions)
      ..where((sv) => sv.templateId.equals(templateId))
      ..orderBy([
        (sv) => OrderingTerm.desc(sv.effectiveStartLocalDate),
      ])
      ..limit(1);
    final results = await query.get();
    return results.isEmpty ? null : results.first;
  }

  /// يعيد نسخة الجدول الفعّالة في تاريخ معين.
  Future<ScheduleVersion?> getScheduleVersionForDate(
    String templateId,
    String localDate,
  ) async {
    final query = _database.select(_database.scheduleVersions)
      ..where(
        (sv) =>
            sv.templateId.equals(templateId) &
            sv.effectiveStartLocalDate.isSmallerOrEqualValue(localDate),
      )
      ..orderBy([
        (sv) => OrderingTerm.desc(sv.effectiveStartLocalDate),
      ])
      ..limit(1);
    final results = await query.get();
    // إذا لم يكن هناك نسخة قبل هذا التاريخ، نأخذ الأقدم لعدم كسر التطبيق.
    if (results.isEmpty) {
      final fallbackQuery = _database.select(_database.scheduleVersions)
        ..where((sv) => sv.templateId.equals(templateId))
        ..orderBy([
          (sv) => OrderingTerm.asc(sv.effectiveStartLocalDate),
        ])
        ..limit(1);
      final fallback = await fallbackQuery.get();
      return fallback.isEmpty ? null : fallback.first;
    }
    return results.first;
  }

  /// يحدّث الدورية أو الهدف لبند معين من خلال إنشاء نسخة جدول جديدة.
  Future<void> updateTemplateSchedule({
    required String templateId,
    required TrackingPeriod newPeriod,
    required int newTarget,
    String? effectiveFromLocalDate,
  }) async {
    final effectiveDate = effectiveFromLocalDate ?? await _calculateEffectiveDate(newPeriod);
    final active = await getActiveScheduleVersion(templateId);
    if (active == null) return;
    if (active.periodicity == newPeriod.name &&
        active.targetValue == newTarget) {
      return; // لا تغيير
    }
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      // 1. تحديث ActivityTemplates ليعكس القيم الأحدث
      await (_database.update(_database.activityTemplates)
            ..where((t) => t.id.equals(templateId)))
          .write(
            ActivityTemplatesCompanion(
              periodicity: Value(newPeriod.name),
              updatedAt: Value(now),
            ),
          );

      // 2. التحقق من وجود نسخة في نفس تاريخ السريان
      final existingAtDate = await (_database.select(_database.scheduleVersions)
            ..where(
              (sv) =>
                  sv.templateId.equals(templateId) &
                  sv.effectiveStartLocalDate.equals(effectiveDate),
            ))
          .getSingleOrNull();

      if (existingAtDate != null) {
        // تحديث النسخة الموجودة في نفس التاريخ
        await (_database.update(_database.scheduleVersions)
              ..where((sv) => sv.id.equals(existingAtDate.id)))
            .write(
              ScheduleVersionsCompanion(
                periodicity: Value(newPeriod.name),
                targetValue: Value(newTarget),
              ),
            );
      } else {
        // إنشاء نسخة جديدة
        await _database.into(_database.scheduleVersions).insert(
              ScheduleVersionsCompanion.insert(
                id: _uuid.v7(),
                templateId: templateId,
                effectiveStartLocalDate: effectiveDate,
                periodicity: newPeriod.name,
                trackingType: active.trackingType,
                targetValue: Value(newTarget),
                createdAt: now,
              ),
            );
      }
    });
  }

  Future<void> saveEntry({
    required String scheduleVersionId,
    required String localDate,
    required TrackingState state,
    int? numericValue,
    String? textValue,
  }) async {
    if (localDate.compareTo(_localToday()) > 0) {
      throw ArgumentError.value(
        localDate,
        'localDate',
        'لا يمكن تسجيل إنجاز مستقبلي.',
      );
    }
    final existing =
        await (_database.select(_database.activityEntries)..where(
              (entry) =>
                  entry.scheduleVersionId.equals(scheduleVersionId) &
                  entry.localDate.equals(localDate),
            ))
            .getSingleOrNull();
    final now = DateTime.now().toUtc();
    final entry = ActivityEntriesCompanion(
      id: Value(existing?.id ?? _uuid.v7()),
      scheduleVersionId: Value(scheduleVersionId),
      localDate: Value(localDate),
      state: Value(state.name),
      numericValue: Value(numericValue),
      textValue: Value(textValue),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
    );
    if (existing == null) {
      await _database.into(_database.activityEntries).insert(entry);
    } else {
      await (_database.update(
        _database.activityEntries,
      )..where((row) => row.id.equals(existing.id))).write(entry);
    }
  }

  String _localToday() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<String> _calculateEffectiveDate(TrackingPeriod period) async {
    final now = DateTime.now();
    if (period == TrackingPeriod.monthly) {
      return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
    } else if (period == TrackingPeriod.weekly) {
      final setting = await (_database.select(_database.settings)..where((s) => s.key.equals('weekStartDay'))).getSingleOrNull();
      final startOfWeekStr = setting?.value ?? 'Saturday';
      
      int startDay;
      switch (startOfWeekStr) {
        case 'Saturday': startDay = DateTime.saturday; break;
        case 'Sunday': startDay = DateTime.sunday; break;
        case 'Monday': startDay = DateTime.monday; break;
        default: startDay = DateTime.saturday;
      }
      
      int diff = now.weekday - startDay;
      if (diff < 0) {
        diff += 7;
      }
      final startOfWeekDate = now.subtract(Duration(days: diff));
      return '${startOfWeekDate.year.toString().padLeft(4, '0')}-${startOfWeekDate.month.toString().padLeft(2, '0')}-${startOfWeekDate.day.toString().padLeft(2, '0')}';
    }
    return _localToday();
  }
}
