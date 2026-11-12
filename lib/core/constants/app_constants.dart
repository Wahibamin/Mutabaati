class AppConstants {
  static const String appName = 'مقوتي';
  static const String appSubtitle = 'النظام المحاسبي المبسط لبائعي القات';
  static const String defaultCurrency = 'ر.ي';
  static const String defaultUnit = 'ربطة';
  static const String dbFileName = 'maqwati_ledger.sqlite';
  static const String driveBackupFolderName = 'Maqwati_Backups';

  /// فئات مالية سريعة شائعة في سوق القات اليمني لتوفير وقت الكتابة (صفحة 11)
  static const List<double> quickDenominations = [
    1000,
    2000,
    3000,
    5000,
    10000,
    20000,
  ];

  /// المحافظ وشبكات الحوالات الشائعة في اليمن (صفحة 2)
  static const List<String> commonWallets = [
    'جيب (Jaib)',
    'كريمي (Kuraimi)',
    'جوالي (Jawali)',
    'فلوسك (Floosak)',
    'ام فلوس (M-Floos)',
    'ون كاش (OneCash)',
    'حوالة صرافة أخرى',
  ];

  /// أصناف القات الافتراضية للتأسيس السريع (صفحة 4)
  static const List<String> defaultQatItems = [
    'قات عنسي',
    'قات شامي',
    'قات همداني',
    'قات أرحبي',
    'قات سمين',
    'قات غيلي',
  ];

  /// بنود مصاريف العمل الشائعة في المقوات/الفرشة (صفحة 4)
  static const List<String> commonWorkExpenses = [
    'أكياس وقرطاسية',
    'ثلج وماء بارد',
    'إيجار الفرشة / المحل',
    'نقل وفرزة',
    'أجور عمال',
    'كهرباء وإنارة',
  ];

  /// بنود المصاريف الشخصية الشائعة (صفحة 4)
  static const List<String> commonPersonalExpenses = [
    'مقاضي البيت والمنزل',
    'غداء ومصاريف يومية',
    'التزامات عائلية',
    'رصيد واتصالات',
  ];
}
