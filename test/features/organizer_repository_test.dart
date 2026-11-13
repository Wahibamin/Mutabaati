import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import 'package:mutabaati/core/database/app_database.dart';
import 'package:mutabaati/core/services/reminder_service.dart';
import 'package:mutabaati/features/organizer/data/organizer_repository.dart';

class FakeReminderService implements ReminderService {
  int scheduleCalls = 0;
  int cancelCalls = 0;
  int snoozeCalls = 0;

  @override
  Future<void> scheduleReminder({
    required String ownerType,
    required String ownerId,
    required DateTime scheduledAt,
    required String title,
    required String body,
    String kind = 'reminder',
  }) async {
    scheduleCalls++;
  }

  @override
  Future<void> cancelReminder(String ownerType, String ownerId, {String kind = 'reminder'}) async {
    cancelCalls++;
  }

  @override
  Future<void> snoozeReminder(String ownerType, String ownerId, {String kind = 'reminder', int minutes = 10}) async {
    snoozeCalls++;
  }
  
  @override
  Future<void> init() async {}
}

void main() {
  late AppDatabase database;
  late FakeReminderService fakeReminderService;
  late OrganizerRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    fakeReminderService = FakeReminderService();
    repository = OrganizerRepository(
      database,
      fakeReminderService as dynamic, // Type cast to avoid implementation missing errors if dart considers it incomplete
      uuid: const Uuid(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('OrganizerRepository – المهام والمواعيد', () {
    test('addTask ينشئ مهمة عادية بدون تكرار', () async {
      await repository.addTask(title: 'مهمة 1');
      final tasks = await database.select(database.taskOccurrences).get();
      expect(tasks.length, 1);
      expect(tasks.first.isCompleted, isFalse);
    });

    test('addTask مع تفعيل المنبه يستدعي scheduleReminder', () async {
      final dueAt = DateTime.now().add(const Duration(hours: 1));
      await repository.addTask(title: 'مهمة منبه', dueAt: dueAt, hasReminder: true);
      
      final tasks = await database.select(database.taskOccurrences).get();
      expect(tasks.length, 1);
      expect(fakeReminderService.scheduleCalls, 1);
    });

    test('setTaskCompleted يلغي المنبه إذا اكتملت المهمة', () async {
      await repository.addTask(title: 'مهمة سيتم إكمالها', dueAt: DateTime.now(), hasReminder: true);
      final tasks = await database.select(database.taskOccurrences).get();
      final id = tasks.first.id;

      await repository.setTaskCompleted(id, true);
      expect(fakeReminderService.cancelCalls, 1);
    });

    test('addAppointment ينشئ موعد ويستدعي المنبه إن طلب', () async {
      final startsAt = DateTime.now().add(const Duration(hours: 2));
      final endsAt = startsAt.add(const Duration(hours: 1));
      await repository.addAppointment(
        title: 'طبيب',
        startsAt: startsAt,
        endsAt: endsAt,
        timezoneId: 'UTC',
        hasReminder: true,
      );

      final appts = await database.select(database.appointmentOccurrences).get();
      expect(appts.length, 1);
      expect(fakeReminderService.scheduleCalls, 1);
    });

    test('snoozeTask يستدعي خدمة المنبه للتأجيل', () async {
      await repository.snoozeTask('task-123', minutes: 15);
      expect(fakeReminderService.snoozeCalls, 1);
    });
  });
}
