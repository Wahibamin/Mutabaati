import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../../../core/database/app_database.dart';

class BackupRepository {
  BackupRepository(this._database);
  final AppDatabase _database;

  Future<String> exportData(String destinationPath) async {
    final data = <String, dynamic>{
      'formatVersion': 1,
      'schemaVersion': _database.schemaVersion,
      'appVersion': '1.0.0',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

    final tablesMap = <String, List<Map<String, dynamic>>>{};

    tablesMap['settings'] = (await _database.select(_database.settings).get()).map((e) => e.toJson()).toList();
    tablesMap['sections'] = (await _database.select(_database.sections).get()).map((e) => e.toJson()).toList();
    tablesMap['activity_templates'] = (await _database.select(_database.activityTemplates).get()).map((e) => e.toJson()).toList();
    tablesMap['schedule_versions'] = (await _database.select(_database.scheduleVersions).get()).map((e) => e.toJson()).toList();
    tablesMap['activity_entries'] = (await _database.select(_database.activityEntries).get()).map((e) => e.toJson()).toList();
    tablesMap['prayer_entries'] = (await _database.select(_database.prayerEntries).get()).map((e) => e.toJson()).toList();
    tablesMap['expense_categories'] = (await _database.select(_database.expenseCategories).get()).map((e) => e.toJson()).toList();
    tablesMap['expenses'] = (await _database.select(_database.expenses).get()).map((e) => e.toJson()).toList();
    tablesMap['task_series'] = (await _database.select(_database.taskSeries).get()).map((e) => e.toJson()).toList();
    tablesMap['task_occurrences'] = (await _database.select(_database.taskOccurrences).get()).map((e) => e.toJson()).toList();
    tablesMap['appointments'] = (await _database.select(_database.appointments).get()).map((e) => e.toJson()).toList();
    tablesMap['appointment_occurrences'] = (await _database.select(_database.appointmentOccurrences).get()).map((e) => e.toJson()).toList();
    tablesMap['custom_field_definitions'] = (await _database.select(_database.customFieldDefinitions).get()).map((e) => e.toJson()).toList();
    tablesMap['custom_field_options'] = (await _database.select(_database.customFieldOptions).get()).map((e) => e.toJson()).toList();
    tablesMap['custom_field_values'] = (await _database.select(_database.customFieldValues).get()).map((e) => e.toJson()).toList();
    tablesMap['reminder_jobs'] = (await _database.select(_database.reminderJobs).get()).map((e) => e.toJson()).toList();

    data['tables'] = tablesMap;

    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    final digest = sha256.convert(bytes);
    
    final finalData = Map<String, dynamic>.from(data);
    finalData['checksum'] = digest.toString();

    final finalJsonStr = jsonEncode(finalData);
    final file = File(destinationPath);
    await file.writeAsString(finalJsonStr);

    return destinationPath;
  }

  Future<void> importData(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) throw Exception('الملف غير موجود');

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    if (!data.containsKey('checksum') || !data.containsKey('tables')) {
      throw Exception('ملف غير صالح أو معطوب');
    }

    final checksum = data['checksum'] as String;
    final dataWithoutChecksum = Map<String, dynamic>.from(data)..remove('checksum');
    
    final jsonStr = jsonEncode(dataWithoutChecksum);
    final bytes = utf8.encode(jsonStr);
    final digest = sha256.convert(bytes);

    if (digest.toString() != checksum) {
      throw Exception('تم التلاعب بالملف أو أنه معطوب (Checksum mismatch)');
    }

    if (data['formatVersion'] != 1) {
      throw Exception('إصدار ملف النسخة الاحتياطية غير مدعوم');
    }

    final tables = data['tables'] as Map<String, dynamic>;

    await _database.transaction(() async {
      // Delete all current data in reverse dependency order
      await _database.delete(_database.customFieldValues).go();
      await _database.delete(_database.customFieldOptions).go();
      await _database.delete(_database.customFieldDefinitions).go();
      await _database.delete(_database.appointmentOccurrences).go();
      await _database.delete(_database.appointments).go();
      await _database.delete(_database.taskOccurrences).go();
      await _database.delete(_database.taskSeries).go();
      await _database.delete(_database.expenses).go();
      await _database.delete(_database.expenseCategories).go();
      await _database.delete(_database.prayerEntries).go();
      await _database.delete(_database.activityEntries).go();
      await _database.delete(_database.scheduleVersions).go();
      await _database.delete(_database.activityTemplates).go();
      await _database.delete(_database.sections).go();
      await _database.delete(_database.settings).go();
      await _database.delete(_database.reminderJobs).go();

      // Insert all data
      if (tables.containsKey('settings')) {
        for (final item in tables['settings'] as List) {
          await _database.into(_database.settings).insert(Setting.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('sections')) {
        for (final item in tables['sections'] as List) {
          await _database.into(_database.sections).insert(Section.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('activity_templates')) {
        for (final item in tables['activity_templates'] as List) {
          await _database.into(_database.activityTemplates).insert(ActivityTemplate.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('schedule_versions')) {
        for (final item in tables['schedule_versions'] as List) {
          await _database.into(_database.scheduleVersions).insert(ScheduleVersion.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('activity_entries')) {
        for (final item in tables['activity_entries'] as List) {
          await _database.into(_database.activityEntries).insert(ActivityEntry.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('prayer_entries')) {
        for (final item in tables['prayer_entries'] as List) {
          await _database.into(_database.prayerEntries).insert(PrayerEntry.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('expense_categories')) {
        for (final item in tables['expense_categories'] as List) {
          await _database.into(_database.expenseCategories).insert(ExpenseCategory.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('expenses')) {
        for (final item in tables['expenses'] as List) {
          await _database.into(_database.expenses).insert(Expense.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('task_series')) {
        for (final item in tables['task_series'] as List) {
          await _database.into(_database.taskSeries).insert(TaskSery.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('task_occurrences')) {
        for (final item in tables['task_occurrences'] as List) {
          await _database.into(_database.taskOccurrences).insert(TaskOccurrence.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('appointments')) {
        for (final item in tables['appointments'] as List) {
          await _database.into(_database.appointments).insert(Appointment.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('appointment_occurrences')) {
        for (final item in tables['appointment_occurrences'] as List) {
          await _database.into(_database.appointmentOccurrences).insert(AppointmentOccurrence.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('custom_field_definitions')) {
        for (final item in tables['custom_field_definitions'] as List) {
          await _database.into(_database.customFieldDefinitions).insert(CustomFieldDefinition.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('custom_field_options')) {
        for (final item in tables['custom_field_options'] as List) {
          await _database.into(_database.customFieldOptions).insert(CustomFieldOption.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('custom_field_values')) {
        for (final item in tables['custom_field_values'] as List) {
          await _database.into(_database.customFieldValues).insert(CustomFieldValue.fromJson(item as Map<String, dynamic>));
        }
      }
      if (tables.containsKey('reminder_jobs')) {
        for (final item in tables['reminder_jobs'] as List) {
          await _database.into(_database.reminderJobs).insert(ReminderJob.fromJson(item as Map<String, dynamic>));
        }
      }
    });
  }
}
