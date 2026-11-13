class RecurrenceRule {
  const RecurrenceRule({
    required this.type,
    this.daysOfWeek,
    this.dayOfMonth,
    this.until,
  });

  final RecurrenceType type;
  final List<int>? daysOfWeek; // 1 = Monday, 7 = Sunday
  final int? dayOfMonth; // 1..31
  final DateTime? until;

  static RecurrenceRule parse(String rule) {
    if (rule == 'none' || rule.isEmpty) {
      return const RecurrenceRule(type: RecurrenceType.none);
    }
    
    final parts = rule.split(';');
    final mainPart = parts[0].split(',');
    
    DateTime? untilDate;
    if (parts.length > 1 && parts[1].startsWith('until=')) {
      untilDate = DateTime.tryParse(parts[1].substring(6));
    }

    switch (mainPart[0]) {
      case 'daily':
        return RecurrenceRule(type: RecurrenceType.daily, until: untilDate);
      case 'weekly':
        final days = mainPart.skip(1).map(int.parse).toList();
        return RecurrenceRule(
          type: RecurrenceType.weekly,
          daysOfWeek: days,
          until: untilDate,
        );
      case 'monthly':
        final day = int.parse(mainPart[1]);
        return RecurrenceRule(
          type: RecurrenceType.monthly,
          dayOfMonth: day,
          until: untilDate,
        );
      default:
        return const RecurrenceRule(type: RecurrenceType.none);
    }
  }

  String toRuleString() {
    if (type == RecurrenceType.none) return 'none';
    
    final sb = StringBuffer();
    switch (type) {
      case RecurrenceType.daily:
        sb.write('daily');
        break;
      case RecurrenceType.weekly:
        sb.write('weekly,${daysOfWeek!.join(',')}');
        break;
      case RecurrenceType.monthly:
        sb.write('monthly,$dayOfMonth');
        break;
      case RecurrenceType.none:
        break;
    }
    
    if (until != null) {
      sb.write(';until=${until!.toIso8601String().substring(0, 10)}');
    }
    
    return sb.toString();
  }

  List<DateTime> generateOccurrences(DateTime start, {int maxOccurrences = 60, DateTime? hardUntil}) {
    if (type == RecurrenceType.none) {
      return [start];
    }

    final occurrences = <DateTime>[start];
    var current = start;
    final limit = hardUntil ?? until ?? start.add(const Duration(days: 365));

    while (occurrences.length < maxOccurrences) {
      current = _nextOccurrence(current);
      if (current.isAfter(limit)) break;
      occurrences.add(current);
    }

    return occurrences;
  }

  DateTime _nextOccurrence(DateTime current) {
    switch (type) {
      case RecurrenceType.daily:
        return current.add(const Duration(days: 1));
      case RecurrenceType.weekly:
        // Find next day in daysOfWeek
        var next = current.add(const Duration(days: 1));
        while (!daysOfWeek!.contains(next.weekday)) {
          next = next.add(const Duration(days: 1));
        }
        return next;
      case RecurrenceType.monthly:
        var year = current.year;
        var month = current.month + 1;
        if (month > 12) {
          month = 1;
          year++;
        }
        // Handle end of month issues (e.g. 31st of Feb)
        var day = dayOfMonth!;
        final daysInMonth = DateTime(year, month + 1, 0).day;
        if (day > daysInMonth) day = daysInMonth;
        
        return DateTime(
          year,
          month,
          day,
          current.hour,
          current.minute,
          current.second,
        );
      case RecurrenceType.none:
        return current;
    }
  }
}

enum RecurrenceType { none, daily, weekly, monthly }
