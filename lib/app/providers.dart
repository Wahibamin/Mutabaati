import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/expenses/data/expense_repository.dart';
import '../features/custom_fields/data/custom_fields_repository.dart';
import '../features/organizer/data/organizer_repository.dart';
import '../features/prayers/data/prayer_repository.dart';
import '../features/reports/data/reports_repository.dart';
import '../features/backup/data/backup_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/tracking/data/tracking_repository.dart';
import '../core/services/reminder_service.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final flutterLocalNotificationsPluginProvider = Provider<FlutterLocalNotificationsPlugin>((ref) {
  return FlutterLocalNotificationsPlugin();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService(
    ref.watch(appDatabaseProvider),
    ref.watch(flutterLocalNotificationsPluginProvider),
  );
  // Note: init() should be called in main() or during app startup
  return service;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);
final appSettingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);
final prayerRepositoryProvider = Provider<PrayerRepository>(
  (ref) => PrayerRepository(ref.watch(appDatabaseProvider)),
);
final prayerRecordsProvider = StreamProvider.family((ref, String localDate) {
  return ref.watch(prayerRepositoryProvider).watchForDate(localDate);
});
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(appDatabaseProvider)),
);
final expenseTotalProvider = StreamProvider.family((ref, String localDate) {
  return ref.watch(expenseRepositoryProvider).watchTotalForLocalDate(localDate);
});
final expensesForDateProvider = StreamProvider.family((ref, String localDate) {
  return ref.watch(expenseRepositoryProvider).watchForLocalDate(localDate);
});
final expenseCategoriesProvider = StreamProvider(
  (ref) => ref.watch(expenseRepositoryProvider).watchCategories(),
);
final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingRepository(ref.watch(appDatabaseProvider)),
);
final activeTemplatesProvider = StreamProvider(
  (ref) => ref.watch(trackingRepositoryProvider).watchActiveTemplates(),
);
final trackingSectionsProvider = StreamProvider(
  (ref) => ref.watch(trackingRepositoryProvider).watchSections(),
);
final customFieldsRepositoryProvider = Provider<CustomFieldsRepository>(
  (ref) => CustomFieldsRepository(ref.watch(appDatabaseProvider)),
);
final organizerRepositoryProvider = Provider<OrganizerRepository>(
  (ref) => OrganizerRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(reminderServiceProvider),
  ),
);
final taskOccurrencesProvider = StreamProvider(
  (ref) => ref.watch(organizerRepositoryProvider).watchTasks(),
);
final appointmentOccurrencesProvider = StreamProvider(
  (ref) => ref.watch(organizerRepositoryProvider).watchAppointments(),
);

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(appDatabaseProvider)),
);

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(ref.watch(appDatabaseProvider)),
);
