enum TrackingPeriod { daily, weekly, monthly }

enum TrackingType { boolean, count, duration, text }

enum TrackingState {
  unrecorded,
  completed,
  explicitlyNotCompleted,
  notApplicable,
}

class TemplateSeed {
  const TemplateSeed({
    required this.id,
    required this.name,
    required this.period,
    this.target = 1,
  });

  final String id;
  final String name;
  final TrackingPeriod period;
  final int target;
}

const initialTemplateSeeds = <TemplateSeed>[
  TemplateSeed(
    id: 'daily.morning_adhkar',
    name: 'أذكار الصباح',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.evening_adhkar',
    name: 'أذكار المساء',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.quran_portion',
    name: 'الورد القرآني اليومي',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.after_prayer_adhkar',
    name: 'الأذكار عقب الصلوات',
    period: TrackingPeriod.daily,
    target: 5,
  ),
  TemplateSeed(
    id: 'daily.witr',
    name: 'صلاة الوتر',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.duha',
    name: 'صلاة الضحى',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.rawatib',
    name: 'السنن الراتبة',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.between_maghrib_isha',
    name: 'المكث بين المغرب والعشاء في المسجد',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.attendance',
    name: 'الالتزام بالدوام الوظيفي أو الدراسي',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'daily.family_follow_up',
    name: 'متابعة الأهل في واجباتهم',
    period: TrackingPeriod.daily,
  ),
  TemplateSeed(
    id: 'weekly.friday_early',
    name: 'التبكير لصلاة الجمعة',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.kahf',
    name: 'قراءة سورة الكهف يوم الجمعة',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.lesson',
    name: 'حضور درس',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.kinship',
    name: 'زيارة الأرحام',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.fitrah',
    name: 'المحافظة على سنن الفطرة',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.monday_thursday_fasting',
    name: 'صيام الاثنين والخميس',
    period: TrackingPeriod.weekly,
    target: 2,
  ),
  TemplateSeed(
    id: 'weekly.after_fajr',
    name: 'البقاء بعد الفجر في المسجد حتى الشروق',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.family_lesson',
    name: 'إقامة درس للأهل',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.islamic_newspaper',
    name: 'قراءة جريدة إسلامية ثم إهداؤها',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.charity',
    name: 'إخراج صدقة',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.advice',
    name: 'إسداء نصيحة',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.family_attendance',
    name: 'حضور الأهل درسًا أسبوعيًا',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.dawah_visit',
    name: 'زيارة دعوية',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'weekly.night_prayer',
    name: 'قيام الليل',
    period: TrackingPeriod.weekly,
  ),
  TemplateSeed(
    id: 'monthly.sick_visit',
    name: 'عيادة مريض',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.white_days',
    name: 'صيام أيام البيض',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.family_outing',
    name: 'خروج ترويحي مع الأهل',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.brotherly_visit',
    name: 'زيارة أخوية',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.scholar_visit',
    name: 'زيارة عالم',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.graveyard_or_hospital',
    name: 'زيارة مقبرة أو مستشفى',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.audio_material',
    name: 'سماع مادة صوتية وإهداؤها',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.dawah_gift',
    name: 'إهداء دعوي',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.family_lecture',
    name: 'حضور الأهل محاضرة عامة نسائية',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.article',
    name: 'كتابة مقال دعوي إن أمكن',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.islamic_magazine',
    name: 'قراءة مجلة إسلامية وإهداؤها',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.social_occasion',
    name: 'المشاركة في مناسبة فرح أو ترح',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.charity_work',
    name: 'الاشتراك في العمل الخيري',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.exercise',
    name: 'مزاولة الرياضة',
    period: TrackingPeriod.monthly,
  ),
  TemplateSeed(
    id: 'monthly.will_renewal',
    name: 'تجديد الوصية',
    period: TrackingPeriod.monthly,
  ),
];
