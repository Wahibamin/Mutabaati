import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;

import '../database/app_database.dart';

class ReminderService {
  ReminderService(this._database, this._notificationsPlugin)
      : _uuid = const Uuid();

  final AppDatabase _database;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final Uuid _uuid;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );
    await _rescheduleAllPending();
  }

  Future<void> scheduleReminder({
    required String ownerType,
    required String ownerId,
    required DateTime scheduledAt,
    required String title,
    required String body,
    String kind = 'reminder',
  }) async {
    final now = DateTime.now().toUtc();
    final localScheduled = tz.TZDateTime.from(scheduledAt, tz.local);

    if (localScheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      return; // وقت ماضٍ
    }

    final id = _uuid.v7();
    // Use hashcode to generate an integer ID for platform notifications
    final platformId = '$ownerType-$ownerId-$kind'.hashCode;

    await _database.into(_database.reminderJobs).insertOnConflictUpdate(
          ReminderJobsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            kind: kind,
            scheduledAt: scheduledAt.toUtc(),
            platformNotificationId: platformId,
            status: 'pending',
            updatedAt: now,
          ),
        );

    await _scheduleOnPlatform(platformId, title, body, localScheduled);
  }

  Future<void> cancelReminder(String ownerType, String ownerId, {String kind = 'reminder'}) async {
    final query = _database.select(_database.reminderJobs)
      ..where(
        (job) =>
            job.ownerType.equals(ownerType) &
            job.ownerId.equals(ownerId) &
            job.kind.equals(kind),
      );
    final jobs = await query.get();
    for (final job in jobs) {
      await _notificationsPlugin.cancel(id: job.platformNotificationId);
      await (_database.update(_database.reminderJobs)
            ..where((j) => j.id.equals(job.id)))
          .write(
            ReminderJobsCompanion(
              status: const Value('cancelled'),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
    }
  }

  Future<void> snoozeReminder(String ownerType, String ownerId, {String kind = 'reminder', int minutes = 10}) async {
    // Basic snooze logic (cancel existing, schedule new +10 mins)
    final query = _database.select(_database.reminderJobs)
      ..where(
        (job) =>
            job.ownerType.equals(ownerType) &
            job.ownerId.equals(ownerId) &
            job.kind.equals(kind),
      );
    final jobs = await query.get();
    if (jobs.isEmpty) return;
    
    await cancelReminder(ownerType, ownerId, kind: kind);
    final newTime = DateTime.now().add(Duration(minutes: minutes));
    await scheduleReminder(
      ownerType: ownerType,
      ownerId: ownerId,
      scheduledAt: newTime,
      title: 'مؤجل',
      body: 'تذكير مؤجل', // Ideally we fetch original title/body
      kind: kind,
    );
  }

  Future<void> _rescheduleAllPending() async {
    // In a real app we'd fetch title/body from the owner entity, 
    // but here we just clear all platform notifications and rely on 
    // components to re-register on app start if needed, 
    // or we fetch the generic title.
    final pendingJobs = await (_database.select(_database.reminderJobs)
          ..where((job) => job.status.equals('pending')))
        .get();

    for (final job in pendingJobs) {
      final localScheduled = tz.TZDateTime.from(job.scheduledAt, tz.local);
      if (localScheduled.isAfter(tz.TZDateTime.now(tz.local))) {
        await _scheduleOnPlatform(
          job.platformNotificationId,
          'تذكير',
          'تذكير موعد أو مهمة',
          localScheduled,
        );
      } else {
        await (_database.update(_database.reminderJobs)
              ..where((j) => j.id.equals(job.id)))
            .write(
              ReminderJobsCompanion(
                status: const Value('missed'),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
      }
    }
  }

  Future<void> _scheduleOnPlatform(
    int platformId,
    String title,
    String body,
    tz.TZDateTime scheduled,
  ) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mutabaati_reminders_channel',
        'تنبيهات المهام والمواعيد',
        channelDescription: 'قناة تنبيهات متابعتي للأحداث',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _notificationsPlugin.zonedSchedule(
      id: platformId,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
