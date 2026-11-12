import 'package:intl/intl.dart';

class AppFormatters {
  static final NumberFormat _currencyFormatter = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _qtyFormatter = NumberFormat('#,##0.##', 'en_US');
  static final DateFormat _dateTimeFormat =
      DateFormat('yyyy/MM/dd - hh:mm a', 'ar');
  static final DateFormat _dateOnlyFormat = DateFormat('yyyy/MM/dd', 'ar');
  static final DateFormat _timeOnlyFormat = DateFormat('hh:mm a', 'ar');

  static String formatMoney(double amount, {String? currency}) {
    final formatted = _currencyFormatter.format(amount.round());
    if (currency != null && currency.isNotEmpty) {
      return '$formatted $currency';
    }
    return formatted;
  }

  static String formatQty(double qty, {String unit = 'ربطة'}) {
    return '${_qtyFormatter.format(qty)} $unit';
  }

  static String formatDateTime(DateTime dt) {
    try {
      return _dateTimeFormat.format(dt);
    } catch (_) {
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  static String formatDate(DateTime dt) {
    try {
      return _dateOnlyFormat.format(dt);
    } catch (_) {
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    }
  }

  static String formatTime(DateTime dt) {
    try {
      return _timeOnlyFormat.format(dt);
    } catch (_) {
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}
