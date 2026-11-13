import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/reminder_service.dart';
import '../domain/recurrence_rule.dart';

class OrganizerRepository {
  OrganizerRepository(this._database, this._reminderService, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final ReminderService _reminderService;
  final Uuid _uuid;

  Stream<List<TaskOccurrence>> watchTasks() {
    final query = _database.select(_database.taskOccurrences)
      ..orderBy([(row) => OrderingTerm.asc(row.dueAt)]);
    return query.watch();
  }

  Stream<List<AppointmentOccurrence>> watchAppointments() {
    final query = _database.select(_database.appointmentOccurrences)
      ..orderBy([(row) => OrderingTerm.asc(row.startsAt)]);
    return query.watch();
  }

  Future<void> addTask({
    required String title,
    DateTime? dueAt,
    String priority = 'normal',
    String recurrenceRule = 'none',
    bool hasReminder = false,
  }) async {
    final normalized = title.trim();
    if (normalized.isEmpty) throw const FormatException('عنوان المهمة مطلوب.');
    final now = DateTime.now().toUtc();
    final seriesId = _uuid.v7();
    
    final rrule = RecurrenceRule.parse(recurrenceRule);
    final occurrences = dueAt != null 
        ? rrule.generateOccurrences(dueAt, maxOccurrences: 30)
        : [DateTime.now()]; // إذا لم يوجد استحقاق، نضيف واقعة واحدة فقط كحاوية

    await _database.transaction(() async {
      await _database
          .into(_database.taskSeries)
          .insert(
            TaskSeriesCompanion.insert(
              id: seriesId,
              title: normalized,
              priority: priority,
              recurrenceRule: recurrenceRule,
              createdAt: now,
            ),
          );
          
      for (final occ in occurrences) {
        final actualDue = dueAt != null ? occ : null;
        final occurrenceId = _uuid.v7();
        await _database
            .into(_database.taskOccurrences)
            .insert(
              TaskOccurrencesCompanion.insert(
                id: occurrenceId,
                seriesId: seriesId,
                dueAt: Value(actualDue?.toUtc()),
                localOccurrenceKey: _occurrenceKey(actualDue ?? now),
                createdAt: now,
              ),
            );
            
        if (hasReminder && actualDue != null) {
          await _reminderService.scheduleReminder(
            ownerType: 'task',
            ownerId: occurrenceId,
            scheduledAt: actualDue,
            title: title,
            body: 'تذكير بمهمة مستحقة',
          );
        }
      }
    });
  }

  Future<void> setTaskCompleted(String id, bool completed) async {
    await (_database.update(
      _database.taskOccurrences,
    )..where((row) => row.id.equals(id))).write(
      TaskOccurrencesCompanion(
        isCompleted: Value(completed),
        completedAt: Value(completed ? DateTime.now().toUtc() : null),
      ),
    );
    
    if (completed) {
      await _reminderService.cancelReminder('task', id);
    }
  }

  Future<void> addAppointment({
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timezoneId,
    String recurrenceRule = 'none',
    bool hasReminder = false,
  }) async {
    if (!endsAt.isAfter(startsAt)) {
      throw const FormatException('يجب أن تكون نهاية الموعد بعد بدايته.');
    }
    final normalized = title.trim();
    if (normalized.isEmpty) throw const FormatException('عنوان الموعد مطلوب.');
    final now = DateTime.now().toUtc();
    final appointmentId = _uuid.v7();
    
    final rrule = RecurrenceRule.parse(recurrenceRule);
    final occurrences = rrule.generateOccurrences(startsAt, maxOccurrences: 30);
    final duration = endsAt.difference(startsAt);

    await _database.transaction(() async {
      await _database
          .into(_database.appointments)
          .insert(
            AppointmentsCompanion.insert(
              id: appointmentId,
              title: normalized,
              timezoneId: timezoneId,
              recurrenceRule: recurrenceRule,
              createdAt: now,
            ),
          );
          
      for (final occ in occurrences) {
        final occurrenceId = _uuid.v7();
        await _database
            .into(_database.appointmentOccurrences)
            .insert(
              AppointmentOccurrencesCompanion.insert(
                id: occurrenceId,
                appointmentId: appointmentId,
                startsAt: occ.toUtc(),
                endsAt: occ.add(duration).toUtc(),
                localOccurrenceKey: _occurrenceKey(occ),
                status: 'upcoming',
                createdAt: now,
              ),
            );
            
        if (hasReminder) {
          await _reminderService.scheduleReminder(
            ownerType: 'appointment',
            ownerId: occurrenceId,
            scheduledAt: occ,
            title: title,
            body: 'تذكير بموعد قادم',
          );
        }
      }
    });
  }

  Future<void> setAppointmentStatus(String id, String status) async {
    await (_database.update(_database.appointmentOccurrences)
          ..where((row) => row.id.equals(id)))
        .write(AppointmentOccurrencesCompanion(status: Value(status)));
        
    if (status == 'cancelled' || status == 'attended' || status == 'notAttended') {
      await _reminderService.cancelReminder('appointment', id);
    }
  }

  Future<void> snoozeTask(String id, {int minutes = 10}) async {
    await _reminderService.snoozeReminder('task', id, minutes: minutes);
  }

  Future<void> snoozeAppointment(String id, {int minutes = 10}) async {
    await _reminderService.snoozeReminder('appointment', id, minutes: minutes);
  }

  String _occurrenceKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}T${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
