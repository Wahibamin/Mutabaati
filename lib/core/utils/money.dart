class MoneyParser {
  static const int maximumMinorUnits = 9000000000000000;

  static int parseToMinorUnits(String input, {required int fractionDigits}) {
    final normalized = _normalize(input).trim();
    if (normalized.isEmpty || fractionDigits < 0 || fractionDigits > 3) {
      throw const FormatException('أدخل مبلغًا صالحًا.');
    }

    final parts = normalized.split('.');
    if (parts.length > 2 ||
        parts.first.isEmpty ||
        (parts.length == 2 && parts.last.isEmpty)) {
      throw const FormatException('صيغة المبلغ غير واضحة.');
    }
    final whole = int.tryParse(parts.first);
    final decimals = parts.length == 2 ? parts.last : '';
    if (whole == null ||
        !RegExp(r'^\d*$').hasMatch(decimals) ||
        decimals.length > fractionDigits) {
      throw const FormatException('صيغة المبلغ غير صالحة.');
    }
    final paddedDecimals = decimals.padRight(fractionDigits, '0');
    final scale = _powerOfTen(fractionDigits);
    final minor =
        whole * scale +
        (paddedDecimals.isEmpty ? 0 : int.parse(paddedDecimals));
    if (minor <= 0 || minor > maximumMinorUnits) {
      throw const FormatException('المبلغ خارج الحد المدعوم.');
    }
    return minor;
  }

  static String formatMinorUnits(int amount, {required int fractionDigits}) {
    final scale = _powerOfTen(fractionDigits);
    final whole = amount ~/ scale;
    if (fractionDigits == 0) return '$whole';
    final decimals = (amount % scale).toString().padLeft(fractionDigits, '0');
    return '$whole.$decimals';
  }

  static String _normalize(String value) => value
      .replaceAll('٫', '.')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');

  static int _powerOfTen(int exponent) {
    var value = 1;
    for (var index = 0; index < exponent; index++) {
      value *= 10;
    }
    return value;
  }
}
