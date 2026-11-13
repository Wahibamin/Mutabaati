import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutabaati/core/database/app_database.dart';
import 'package:mutabaati/features/tracking/data/tracking_repository.dart';
import 'package:mutabaati/features/tracking/domain/tracking_models.dart';

AppDatabase _openDb() => AppDatabase.forTesting(NativeDatabase.memory());

const _today = '2026-09-20';
const _future = '2099-01-01';

void main() {
  late AppDatabase db;
  late TrackingRepository repo;

  setUp(() {
    db = _openDb();
    repo = TrackingRepository(db);
  });

  tearDown(() => db.close());

  group('TrackingRepository – أقسام', () {
    test('إنشاء قسم وقراءته', () async {
      await repo.addSection('العبادات');
      final sections = await repo.watchSections().first;
      expect(sections.length, 1);
      expect(sections.first.name, 'العبادات');
    });

    test('رفض الاسم الفارغ', () {
      expect(
        () => repo.addSection('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('أرشفة قسم يُخفيه من watchSections', () async {
      await repo.addSection('تعليم');
      final before = await repo.watchSections().first;
      expect(before.length, 1);
      await repo.archiveSection(before.first.id);
      final after = await repo.watchSections().first;
      expect(after, isEmpty);
    });
  });

  group('TrackingRepository – قوالب', () {
    late String sectionId;

    setUp(() async {
      sectionId = await repo.addSection('قسم الاختبار');
    });

    test('إضافة قالب يومي نعم/لا', () async {
      await repo.addTemplate(
        sectionId: sectionId,
        name: 'أذكار الصباح',
        period: TrackingPeriod.daily,
        type: TrackingType.boolean,
        localDate: _today,
      );
      final templates = await repo.watchActiveTemplates().first;
      expect(templates.length, 1);
      expect(templates.first.name, 'أذكار الصباح');
      expect(templates.first.periodicity, 'daily');
      expect(templates.first.trackingType, 'boolean');
    });

    test('إضافة قالب عدد بهدف', () async {
      await repo.addTemplate(
        sectionId: sectionId,
        name: 'تكرار الذكر',
        period: TrackingPeriod.daily,
        type: TrackingType.count,
        target: 100,
        localDate: _today,
      );
      final sv =
          await repo.getActiveScheduleVersion(
          (await repo.watchActiveTemplates().first).first.id);
      expect(sv, isNotNull);
      expect(sv!.targetValue, 100);
    });

    test('رفض الهدف الصفري', () {
      expect(
        () => repo.addTemplate(
          sectionId: sectionId,
          name: 'بند',
          period: TrackingPeriod.daily,
          type: TrackingType.count,
          target: 0,
          localDate: _today,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('أرشفة قالب يُخفيه من watchActiveTemplates', () async {
      await repo.addTemplate(
        sectionId: sectionId,
        name: 'مؤقت',
        period: TrackingPeriod.daily,
        type: TrackingType.boolean,
        localDate: _today,
      );
      final before = await repo.watchActiveTemplates().first;
      expect(before.length, 1);
      await repo.archiveTemplate(before.first.id);
      final after = await repo.watchActiveTemplates().first;
      expect(after, isEmpty);
    });
  });

  group('TrackingRepository – تسجيل المدخلات', () {
    late String scheduleVersionId;

    setUp(() async {
      final sid = await repo.addSection('اختبار');
      await repo.addTemplate(
        sectionId: sid,
        name: 'بند يومي',
        period: TrackingPeriod.daily,
        type: TrackingType.boolean,
        localDate: _today,
      );
      final t = (await repo.watchActiveTemplates().first).first;
      final sv = await repo.getActiveScheduleVersion(t.id);
      scheduleVersionId = sv!.id;
    });

    test('حفظ مدخل مكتمل', () async {
      await repo.saveEntry(
        scheduleVersionId: scheduleVersionId,
        localDate: _today,
        state: TrackingState.completed,
      );
      final entries = await db.select(db.activityEntries).get();
      expect(entries.length, 1);
      expect(entries.first.state, 'completed');
    });

    test('تحديث المدخل بدلاً من إنشاء مكرر (upsert)', () async {
      await repo.saveEntry(
        scheduleVersionId: scheduleVersionId,
        localDate: _today,
        state: TrackingState.completed,
      );
      await repo.saveEntry(
        scheduleVersionId: scheduleVersionId,
        localDate: _today,
        state: TrackingState.explicitlyNotCompleted,
      );
      final entries = await db.select(db.activityEntries).get();
      expect(entries.length, 1);
      expect(entries.first.state, 'explicitlyNotCompleted');
    });

    test('رفض تسجيل مدخل مستقبلي', () {
      expect(
        () => repo.saveEntry(
          scheduleVersionId: scheduleVersionId,
          localDate: _future,
          state: TrackingState.completed,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TrackingRepository – نسخ الجداول (ScheduleVersions)', () {
    late String sectionId;
    late String templateId;

    setUp(() async {
      sectionId = await repo.addSection('قسم الاختبار');
      await repo.addTemplate(
        sectionId: sectionId,
        name: 'قراءة',
        period: TrackingPeriod.daily,
        type: TrackingType.count,
        target: 10,
        localDate: '2026-01-01',
      );
      templateId = (await repo.watchActiveTemplates().first).first.id;
    });

    test('updateTemplateSchedule ينشئ نسخة جديدة بتاريخ جديد', () async {
      await repo.updateTemplateSchedule(
        templateId: templateId,
        newPeriod: TrackingPeriod.weekly,
        newTarget: 50,
        effectiveFromLocalDate: '2026-02-01',
      );

      // نسخة 2026-01-01
      final v1 = await repo.getScheduleVersionForDate(templateId, '2026-01-15');
      expect(v1, isNotNull);
      expect(v1!.targetValue, 10);
      expect(v1.periodicity, 'daily');

      // نسخة 2026-02-01
      final v2 = await repo.getScheduleVersionForDate(templateId, '2026-02-05');
      expect(v2, isNotNull);
      expect(v2!.targetValue, 50);
      expect(v2.periodicity, 'weekly');
      
      // التاكد من أن getActiveScheduleVersion يعيد النسخة الأحدث
      final active = await repo.getActiveScheduleVersion(templateId);
      expect(active!.id, v2.id);
    });

    test('updateTemplateSchedule يحدّث النسخة الموجودة لو كانت بنفس التاريخ', () async {
      await repo.updateTemplateSchedule(
        templateId: templateId,
        newPeriod: TrackingPeriod.monthly,
        newTarget: 100,
        effectiveFromLocalDate: '2026-01-01',
      );

      final v = await repo.getScheduleVersionForDate(templateId, '2026-01-01');
      expect(v!.targetValue, 100);
      expect(v.periodicity, 'monthly');
    });
  });

  group('TrackingRepository – القوالب الأولية', () {
    test('applyInitialTemplates ينشئ القسم والقوالب', () async {
      await repo.applyInitialTemplates(
        ['daily.morning_adhkar', 'daily.witr', 'weekly.kahf'],
        _today,
      );
      final templates = await repo.watchActiveTemplates().first;
      expect(templates.length, 3);
      final ids = templates.map((t) => t.id).toSet();
      expect(ids, containsAll(['daily.morning_adhkar', 'daily.witr', 'weekly.kahf']));
    });

    test('applyInitialTemplates لا يكرر القوالب عند الاستدعاء مرتين', () async {
      await repo.applyInitialTemplates(['daily.morning_adhkar'], _today);
      await repo.applyInitialTemplates(['daily.morning_adhkar'], _today);
      final templates = await repo.watchActiveTemplates().first;
      expect(templates.length, 1);
    });
  });
}
