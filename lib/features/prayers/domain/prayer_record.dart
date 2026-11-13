enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

enum PrayerPerformance { unrecorded, performed, missed, excused }

enum PrayerMethod { congregation, individual }

enum PrayerTiming { onTime, late, unspecified }

class PrayerRecord {
  const PrayerRecord({
    required this.localDate,
    required this.prayer,
    required this.performance,
    this.method,
    this.timing,
  });

  final String localDate;
  final PrayerName prayer;
  final PrayerPerformance performance;
  final PrayerMethod? method;
  final PrayerTiming? timing;
}
