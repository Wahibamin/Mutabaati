import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/prayer_record.dart';

class PrayerRepository {
  PrayerRepository(this._database);

  final AppDatabase _database;

  Stream<List<PrayerRecord>> watchForDate(String localDate) {
    final query = _database.select(_database.prayerEntries)
      ..where((entry) => entry.localDate.equals(localDate));
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => PrayerRecord(
              localDate: row.localDate,
              prayer: PrayerName.values.byName(row.prayerName),
              performance: PrayerPerformance.values.byName(row.performance),
              method: row.method == null
                  ? null
                  : PrayerMethod.values.byName(row.method!),
              timing: row.timing == null
                  ? null
                  : PrayerTiming.values.byName(row.timing!),
            ),
          )
          .toList(),
    );
  }

  Future<void> save(PrayerRecord record) async {
    if (record.performance == PrayerPerformance.unrecorded) {
      await (_database.delete(_database.prayerEntries)..where(
            (row) =>
                row.localDate.equals(record.localDate) &
                row.prayerName.equals(record.prayer.name),
          ))
          .go();
      return;
    }
    final hasPerformanceDetails =
        record.performance == PrayerPerformance.performed;
    await _database
        .into(_database.prayerEntries)
        .insertOnConflictUpdate(
          PrayerEntriesCompanion.insert(
            localDate: record.localDate,
            prayerName: record.prayer.name,
            performance: record.performance.name,
            method: Value(hasPerformanceDetails ? record.method?.name : null),
            timing: Value(hasPerformanceDetails ? record.timing?.name : null),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }
}
