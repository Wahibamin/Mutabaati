import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Sections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ActivityTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId => text().nullable().references(Sections, #id)();
  TextColumn get name => text()();
  TextColumn get periodicity => text()();
  TextColumn get trackingType => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ScheduleVersions extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(ActivityTemplates, #id)();
  TextColumn get effectiveStartLocalDate => text()();
  TextColumn get periodicity => text()();
  TextColumn get trackingType => text()();
  IntColumn get targetValue => integer().nullable()();
  TextColumn get applicableDays => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ActivityEntries extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleVersionId =>
      text().references(ScheduleVersions, #id)();
  TextColumn get localDate => text()();
  TextColumn get state => text()();
  IntColumn get numericValue => integer().nullable()();
  TextColumn get textValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {scheduleVersionId, localDate},
  ];
}

class PrayerEntries extends Table {
  TextColumn get localDate => text()();
  TextColumn get prayerName => text()();
  TextColumn get performance => text()();
  TextColumn get method => text().nullable()();
  TextColumn get timing => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localDate, prayerName};
}

class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get localDate => text()();
  TextColumn get note => text().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get localTime => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskSeries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get sectionId => text().nullable().references(Sections, #id)();
  TextColumn get priority => text()();
  TextColumn get timezoneId => text().nullable()();
  TextColumn get recurrenceRule => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get seriesId => text().references(TaskSeries, #id)();
  DateTimeColumn get dueAt => dateTime().nullable()();
  TextColumn get localOccurrenceKey => text()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get isCancelled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {seriesId, localOccurrenceKey},
  ];
}

class Appointments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get timezoneId => text()();
  TextColumn get recurrenceRule => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppointmentOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get appointmentId => text().references(Appointments, #id)();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get localOccurrenceKey => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {appointmentId, localOccurrenceKey},
  ];
}

class CustomFieldDefinitions extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text().nullable()();
  TextColumn get label => text()();
  TextColumn get fieldType => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  TextColumn get defaultValue => text().nullable()();
  TextColumn get validationJson => text().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomFieldOptions extends Table {
  TextColumn get id => text()();
  TextColumn get definitionId =>
      text().references(CustomFieldDefinitions, #id)();
  TextColumn get label => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomFieldValues extends Table {
  TextColumn get id => text()();
  TextColumn get definitionId =>
      text().references(CustomFieldDefinitions, #id)();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get valueText => text().nullable()();
  IntColumn get valueInteger => integer().nullable()();
  BoolColumn get valueBoolean => boolean().nullable()();
  DateTimeColumn get valueDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {definitionId, ownerType, ownerId},
  ];
}

class ReminderJobs extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get kind => text()();
  IntColumn get platformNotificationId => integer()();
  TextColumn get status => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerType, ownerId, kind},
    {platformNotificationId},
  ];
}

@DriftDatabase(
  tables: [
    Settings,
    Sections,
    ActivityTemplates,
    ScheduleVersions,
    ActivityEntries,
    PrayerEntries,
    ExpenseCategories,
    Expenses,
    TaskSeries,
    TaskOccurrences,
    Appointments,
    AppointmentOccurrences,
    CustomFieldDefinitions,
    CustomFieldOptions,
    CustomFieldValues,
    ReminderJobs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'mutabaati'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 1) {
        await m.createAll();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(
        'CREATE INDEX IF NOT EXISTS expenses_local_date_idx '
        'ON expenses (local_date)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS activity_entries_schedule_date_idx '
        'ON activity_entries (schedule_version_id, local_date)',
      );
    },
  );
}
