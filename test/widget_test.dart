import 'package:flutter_test/flutter_test.dart';
import 'package:mutabaati/core/utils/money.dart';

void main() {
  test('parses Arabic and Latin money inputs into minor units', () {
    expect(MoneyParser.parseToMinorUnits('12.50', fractionDigits: 2), 1250);
    expect(MoneyParser.parseToMinorUnits('٧٫٢٥', fractionDigits: 2), 725);
  });

  test('rejects zero, ambiguous, and excessive fractional amounts', () {
    expect(
      () => MoneyParser.parseToMinorUnits('0', fractionDigits: 2),
      throwsFormatException,
    );
    expect(
      () => MoneyParser.parseToMinorUnits('1,25', fractionDigits: 2),
      throwsFormatException,
    );
    expect(
      () => MoneyParser.parseToMinorUnits('1.234', fractionDigits: 2),
      throwsFormatException,
    );
  });
}
