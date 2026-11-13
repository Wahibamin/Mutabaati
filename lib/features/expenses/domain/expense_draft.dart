class ExpenseDraft {
  const ExpenseDraft({
    this.id,
    required this.categoryId,
    required this.amountMinor,
    required this.localDate,
    this.note,
    this.paymentMethod,
    this.localTime,
  });

  final String? id;
  final String categoryId;
  final int amountMinor;
  final String localDate;
  final String? note;
  final String? paymentMethod;
  final String? localTime;
}

class ExpenseDaySummary {
  const ExpenseDaySummary({required this.localDate, required this.totalMinor});

  final String localDate;
  final int totalMinor;
}
