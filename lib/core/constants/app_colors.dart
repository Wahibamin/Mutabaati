import 'package:flutter/material.dart';

/// التمييز اللوني المحاسبي الواضح حسب المرجع الهندسي (صفحة 11):
/// - اللون الأخضر لعمليات البيع النقدي والتحصيل والرصيد لصالحنا
/// - اللون البرتقالي/الأحمر للديون الآجلة («عليه» للزبون أو «له» للمورد)
/// - اللون الرمادي الداكن للتالف والمرتجع
class AppColors {
  // الهوية الخضراء مستوحاة من أوراق القات والوثيقة الهندسية
  static const Color primaryGreen = Color(0xFF1B4D3E);
  static const Color primaryLight = Color(0xFF2E7D32);
  static const Color accentGreen = Color(0xFF00897B);

  // ألوان الحالات المحاسبية
  static const Color cashGreen = Color(0xFF1E8E3E); // نقد / قبض / مسدد
  static const Color cashGreenBg = Color(0xFFE6F4EA);

  static const Color debtRed =
      Color(0xFFD93025); // دين آجل («عليه» للزبون أو «له» للمورد)
  static const Color debtRedBg = Color(0xFFFCE8E6);

  static const Color warningOrange = Color(0xFFE65100); // دفعات جزئية / تنبيهات
  static const Color warningOrangeBg = Color(0xFFFFF3E0);

  static const Color transferBlue =
      Color(0xFF1565C0); // حوالات بنكية / محافظ إلكترونية
  static const Color transferBlueBg = Color(0xFFE3F2FD);

  static const Color wastageGrey = Color(0xFF5F6368); // تالف ومرتجع
  static const Color wastageGreyBg = Color(0xFFF1F3F4);

  // خلفيات ونصوص
  static const Color scaffoldBg = Color(0xFFF6F8F7);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF1A1C1E);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color borderLight = Color(0xFFE0E4E2);
}
