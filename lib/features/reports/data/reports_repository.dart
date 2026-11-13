import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class ReportsRepository {
  ReportsRepository(this._database);
  final AppDatabase _database;

  Future<Map<String, dynamic>> getExpensesReport(String startLocal, String endLocal) async {
    // مجموع المصاريف لكل تصنيف
    final expenses = await (_database.select(_database.expenses)
          ..where((e) => e.localDate.isBetweenValues(startLocal, endLocal)))
        .get();

    int totalMinorUnits = 0;
    final categoryTotals = <String, int>{};

    for (final exp in expenses) {
      totalMinorUnits += exp.amountMinor;
      categoryTotals[exp.categoryId] = (categoryTotals[exp.categoryId] ?? 0) + exp.amountMinor;
    }

    return {
      'total': totalMinorUnits,
      'byCategory': categoryTotals,
    };
  }

  Future<Map<String, dynamic>> getTasksReport(DateTime startUtc, DateTime endUtc) async {
    final tasks = await (_database.select(_database.taskOccurrences)
          ..where((t) => t.dueAt.isBetweenValues(startUtc, endUtc)))
        .get();

    int completed = 0;
    int pending = 0;
    int overdue = 0;
    final now = DateTime.now().toUtc();

    for (final task in tasks) {
      if (task.isCompleted) {
        completed++;
      } else {
        if (task.dueAt != null && task.dueAt!.isBefore(now)) {
          overdue++;
        } else {
          pending++;
        }
      }
    }

    return {
      'total': tasks.length,
      'completed': completed,
      'pending': pending,
      'overdue': overdue,
    };
  }

  Future<Map<String, dynamic>> getPrayersReport(String startLocal, String endLocal) async {
    final prayers = await (_database.select(_database.prayerEntries)
          ..where((p) => p.localDate.isBetweenValues(startLocal, endLocal)))
        .get();

    int jamaah = 0;
    int individual = 0;
    int late = 0;
    int excused = 0;
    int missed = 0;

    for (final prayer in prayers) {
      if (prayer.performance == 'أُديت') {
        if (prayer.method == 'جماعة') jamaah++;
        if (prayer.method == 'فردي') individual++;
        if (prayer.timing == 'متأخرة') late++;
      } else if (prayer.performance == 'معذور') {
        excused++;
      } else if (prayer.performance == 'لم تؤد') {
        missed++;
      }
    }

    return {
      'total_recorded': prayers.length,
      'jamaah': jamaah,
      'individual': individual,
      'late': late,
      'excused': excused,
      'missed': missed,
    };
  }

  Future<Map<String, dynamic>> getAppointmentsReport(DateTime startUtc, DateTime endUtc) async {
    final appointments = await (_database.select(_database.appointmentOccurrences)
          ..where((a) => a.startsAt.isBetweenValues(startUtc, endUtc)))
        .get();

    int attended = 0;
    int missed = 0;
    int cancelled = 0;
    int upcoming = 0;

    for (final appt in appointments) {
      switch (appt.status) {
        case 'attended':
          attended++;
          break;
        case 'notAttended':
          missed++;
          break;
        case 'cancelled':
          cancelled++;
          break;
        default:
          upcoming++;
      }
    }

    return {
      'total': appointments.length,
      'attended': attended,
      'missed': missed,
      'cancelled': cancelled,
      'upcoming': upcoming,
    };
  }

  Future<Map<String, dynamic>> getTrackingReport(String startLocal, String endLocal) async {
    final entries = await (_database.select(_database.activityEntries)
          ..where((e) => e.localDate.isBetweenValues(startLocal, endLocal)))
        .get();

    int totalApplicable = 0;
    int totalCompleted = 0;

    for (final entry in entries) {
      if (entry.state == 'notApplicable') continue;
      totalApplicable++;
      if (entry.state == 'completed') {
        totalCompleted++;
      }
    }

    return {
      'total': totalApplicable,
      'completed': totalCompleted,
    };
  }
}
