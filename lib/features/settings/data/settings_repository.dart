import '../../../core/database/app_database.dart';

class AppSettings {
  const AppSettings({
    required this.isOnboarded,
    required this.currencyCode,
    required this.currencyFractionDigits,
    required this.timezoneId,
    required this.firstWeekday,
    this.displayName,
  });

  final bool isOnboarded;
  final String currencyCode;
  final int currencyFractionDigits;
  final String timezoneId;
  final int firstWeekday;
  final String? displayName;
}

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Stream<AppSettings> watch() =>
      _database.select(_database.settings).watch().map((rows) {
        final values = {for (final row in rows) row.key: row.value};
        return AppSettings(
          isOnboarded: values['is_onboarded'] == 'true',
          currencyCode: values['currency_code'] ?? 'SAR',
          currencyFractionDigits:
              int.tryParse(values['currency_fraction_digits'] ?? '') ?? 2,
          timezoneId: values['timezone_id'] ?? 'Asia/Riyadh',
          firstWeekday: int.tryParse(values['first_weekday'] ?? '') ?? 6,
          displayName: values['display_name'],
        );
      });

  Future<void> saveInitialSetup(AppSettings settings) async {
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await _putAll({
        'is_onboarded': 'true',
        'currency_code': settings.currencyCode,
        'currency_fraction_digits': settings.currencyFractionDigits.toString(),
        'timezone_id': settings.timezoneId,
        'first_weekday': settings.firstWeekday.toString(),
        if (settings.displayName?.trim().isNotEmpty ?? false)
          'display_name': settings.displayName!.trim(),
      }, now);
    });
  }

  Future<void> _putAll(Map<String, String> values, DateTime now) async {
    for (final entry in values.entries) {
      await _database
          .into(_database.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: entry.key,
              value: entry.value,
              updatedAt: now,
            ),
          );
    }
  }
}
