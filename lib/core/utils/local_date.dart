String localDateKey([DateTime? date]) {
  final value = date ?? DateTime.now();
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
