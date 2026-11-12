import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Encodes PIN values with a random salt and an intentionally repeated SHA-256
/// derivation. This protects legacy database backups from exposing the PIN as
/// plain text. It does not encrypt the SQLite database itself.
class PinSecurityService {
  static const String _prefix = 'PIN2';
  static const int _iterations = 120000;

  const PinSecurityService._();

  static bool isEncoded(String value) => value.startsWith('$_prefix\$');

  static String encode(String pin, {List<int>? salt}) {
    final normalized = pin.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('رمز PIN لا يمكن أن يكون فارغًا');
    }

    final actualSalt = salt ?? _randomBytes(16);
    final digest = _derive(normalized, actualSalt, _iterations);
    return '$_prefix\$$_iterations\$${base64UrlEncode(actualSalt)}\$${base64UrlEncode(digest)}';
  }

  static bool verify(String pin, String storedValue) {
    if (!isEncoded(storedValue)) {
      return _constantTimeEquals(
        utf8.encode(pin.trim()),
        utf8.encode(storedValue.trim()),
      );
    }

    final parts = storedValue.split(r'$');
    if (parts.length != 4 || parts.first != _prefix) return false;

    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 10000 || iterations > 1000000) {
      return false;
    }

    try {
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      final actual = _derive(pin.trim(), salt, iterations);
      return _constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  static List<int> _derive(String pin, List<int> salt, int iterations) {
    var block = sha256.convert(<int>[...salt, ...utf8.encode(pin)]).bytes;
    for (var i = 1; i < iterations; i++) {
      block = sha256.convert(<int>[...block, ...salt]).bytes;
    }
    return block;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var i = 0; i < length; i++) {
      final a = i < left.length ? left[i] : 0;
      final b = i < right.length ? right[i] : 0;
      difference |= a ^ b;
    }
    return difference == 0;
  }
}
