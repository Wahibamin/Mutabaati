# الملخص التقني | Mutabaati

| البند | التنفيذ |
|---|---|
| الواجهة | Flutter / Dart / Material 3 / RTL عربي |
| الحالة | Riverpod providers وStreamProviders |
| التنقل | go_router |
| التخزين | Drift + SQLite |
| التنبيهات | flutter_local_notifications مع timezone (التحقق الميداني غير مكتمل) |
| النسخ الاحتياطي | JSON + SHA-256 في المستودع (واجهة المسار الثابت تحتاج تحسينًا) |
| تاريخ المراجعة | 12 نوفمبر 2026 |

## بنية الكود

- `lib/app/`: تطبيق MaterialApp والتوجيه والمزودات.
- `lib/core/database/`: مخطط بيانات Drift والإجراءات المولدة.
- `lib/core/services/`: خدمة التذكيرات وجدولتها.
- `lib/core/utils/`: أدوات التواريخ والمبالغ.
- `lib/features/today/`: التجميع اليومي للصلاة والمتابعة.
- `lib/features/tracking/`: أقسام وأنشطة وتسجيل التنفيذ.
- `lib/features/prayers/`: تسجيل حالات الصلاة.
- `lib/features/expenses/`: التصنيفات والمعاملات والمجموع اليومي.
- `lib/features/organizer/`: مهام ومواعيد وتكرار.
- `lib/features/reports/`: ملخصات أسبوعية وشهرية.
- `lib/features/settings/` و`custom_fields/` و`backup/`: الإعدادات والحقول المخصصة وحفظ البيانات.

## نموذج البيانات

قاعدة البيانات تحتوي على 16 جدولًا تشمل `PrayerEntries`, `Expenses`, `TaskSeries`, `TaskOccurrences`, `Appointments`, `ActivityTemplates`, `ActivityEntries`, `ScheduleVersions`, `ReminderJobs` وغيرها.

## مبادئ تطبيقية

1. حفظ البيانات محليًا؛ لا توجد خوادم أو مصادقة سحابية في التصميم الحالي.
2. فصل الاستعلامات عن Widgets وتغليفها في طبقة البيانات.
3. مبالغ صحيحة صغيرة (`amountMinor`) في التخزين لتقليل أخطاء التقريب.
4. التعامل مع التكرار من خلال نماذج مخصصة بدل استنساخ شاشات مستقلة لكل فترة.
5. إعطاء واجهة عربية باتجاه RTL أولوية في التصميم.
