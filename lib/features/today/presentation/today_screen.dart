import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../prayers/domain/prayer_record.dart';
import '../../tracking/domain/tracking_models.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localDate = localDateKey();
    final settings = ref.watch(appSettingsProvider).value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat.yMMMMEEEEd('ar').format(DateTime.now()),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _PrayerCard(localDate: localDate),
        const SizedBox(height: 16),
        _TrackingCard(localDate: localDate),
        const SizedBox(height: 16),
        _ExpenseTotalCard(
          localDate: localDate,
          fractionDigits: settings?.currencyFractionDigits ?? 2,
          currencyCode: settings?.currencyCode ?? 'SAR',
        ),
      ],
    );
  }
}

class _PrayerCard extends ConsumerWidget {
  const _PrayerCard({required this.localDate});

  final String localDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(prayerRecordsProvider(localDate));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('تعذر تحميل الصلوات.'),
          data: (rows) {
            final byPrayer = {for (final row in rows) row.prayer: row};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الصلوات', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...PrayerName.values.map(
                  (prayer) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 8,
                    leading: Icon(
                      _prayerIcon(prayer),
                      color: _statusColor(
                        context,
                        byPrayer[prayer]?.performance,
                      ),
                    ),
                    title: Text(_prayerLabel(prayer)),
                    subtitle: Text(_statusLabel(byPrayer[prayer])),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => _showPrayerEditor(
                      context,
                      ref,
                      localDate,
                      prayer,
                      byPrayer[prayer],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showPrayerEditor(
    BuildContext context,
    WidgetRef ref,
    String localDate,
    PrayerName prayer,
    PrayerRecord? current,
  ) async {
    final action = await showModalBottomSheet<_PrayerAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('تسجيل الصلاة')),
            _actionTile(
              context,
              _PrayerAction.congregation,
              'أديت جماعة وفي الوقت',
              Icons.groups,
            ),
            _actionTile(
              context,
              _PrayerAction.individual,
              'أديت فردي وفي الوقت',
              Icons.person,
            ),
            _actionTile(
              context,
              _PrayerAction.late,
              'أديت متأخرة',
              Icons.schedule,
            ),
            _actionTile(context, _PrayerAction.missed, 'لم تؤد', Icons.close),
            _actionTile(
              context,
              _PrayerAction.excused,
              'معذور',
              Icons.info_outline,
            ),
            _actionTile(
              context,
              _PrayerAction.clear,
              'العودة إلى غير مسجل',
              Icons.undo,
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    final record = switch (action) {
      _PrayerAction.congregation => PrayerRecord(
        localDate: localDate,
        prayer: prayer,
        performance: PrayerPerformance.performed,
        method: PrayerMethod.congregation,
        timing: PrayerTiming.onTime,
      ),
      _PrayerAction.individual => PrayerRecord(
        localDate: localDate,
        prayer: prayer,
        performance: PrayerPerformance.performed,
        method: PrayerMethod.individual,
        timing: PrayerTiming.onTime,
      ),
      _PrayerAction.late => PrayerRecord(
        localDate: localDate,
        prayer: prayer,
        performance: PrayerPerformance.performed,
        method: current?.method,
        timing: PrayerTiming.late,
      ),
      _PrayerAction.missed => PrayerRecord(
        localDate: localDate,
        prayer: prayer,
        performance: PrayerPerformance.missed,
      ),
      _PrayerAction.excused => PrayerRecord(
        localDate: localDate,
        prayer: prayer,
        performance: PrayerPerformance.excused,
      ),
      _PrayerAction.clear => PrayerRecord(
        localDate: localDate,
        prayer: prayer,
        performance: PrayerPerformance.unrecorded,
      ),
    };
    await ref.read(prayerRepositoryProvider).save(record);
  }

  ListTile _actionTile(
    BuildContext context,
    _PrayerAction action,
    String label,
    IconData icon,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    onTap: () => Navigator.pop(context, action),
  );
}

class _TrackingCard extends ConsumerWidget {
  const _TrackingCard({required this.localDate});

  final String localDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ref
          .watch(activeTemplatesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('تعذر تحميل بنود المتابعة.'),
            data: (templates) {
              if (templates.isEmpty) {
                return const _InlineEmpty(
                  icon: Icons.checklist_outlined,
                  message: 'لم تختر قوالب متابعة بعد.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المتابعة',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ...templates.map(
                    (template) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(template.name),
                      subtitle: Text(_periodLabel(template.periodicity)),
                      trailing: FilledButton.tonal(
                        onPressed: () => ref
                            .read(trackingRepositoryProvider)
                            .saveEntry(
                              scheduleVersionId: 'seed.${template.id}.v1',
                              localDate: localDate,
                              state: TrackingState.completed,
                            ),
                        child: const Text('منجز'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
    ),
  );
}

class _ExpenseTotalCard extends ConsumerWidget {
  const _ExpenseTotalCard({
    required this.localDate,
    required this.fractionDigits,
    required this.currencyCode,
  });

  final String localDate;
  final int fractionDigits;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ref
          .watch(expenseTotalProvider(localDate))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('تعذر حساب مصروف اليوم.'),
            data: (total) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مصروف اليوم',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${MoneyParser.formatMinorUnits(total, fractionDigits: fractionDigits)} $currencyCode',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                const Text('المجموع مبني على السجلات المحفوظة فقط.'),
              ],
            ),
          ),
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ],
  );
}

enum _PrayerAction { congregation, individual, late, missed, excused, clear }

String _prayerLabel(PrayerName prayer) => switch (prayer) {
  PrayerName.fajr => 'الفجر',
  PrayerName.dhuhr => 'الظهر',
  PrayerName.asr => 'العصر',
  PrayerName.maghrib => 'المغرب',
  PrayerName.isha => 'العشاء',
};

String _statusLabel(PrayerRecord? record) {
  if (record == null) return 'غير مسجل';
  return switch (record.performance) {
    PrayerPerformance.performed
        when record.method == PrayerMethod.congregation &&
            record.timing == PrayerTiming.late =>
      'أديت جماعة • متأخرة',
    PrayerPerformance.performed
        when record.method == PrayerMethod.congregation =>
      'أديت جماعة',
    PrayerPerformance.performed when record.method == PrayerMethod.individual =>
      'أديت فردي',
    PrayerPerformance.performed => 'أديت',
    PrayerPerformance.missed => 'لم تؤد',
    PrayerPerformance.excused => 'معذور',
    PrayerPerformance.unrecorded => 'غير مسجل',
  };
}

Color _statusColor(BuildContext context, PrayerPerformance? performance) =>
    switch (performance) {
      PrayerPerformance.performed => Colors.green,
      PrayerPerformance.missed => Theme.of(context).colorScheme.error,
      PrayerPerformance.excused => Colors.purple,
      _ => Colors.grey,
    };

IconData _prayerIcon(PrayerName prayer) => switch (prayer) {
  PrayerName.fajr => Icons.wb_twilight_outlined,
  PrayerName.dhuhr => Icons.wb_sunny_outlined,
  PrayerName.asr => Icons.light_mode_outlined,
  PrayerName.maghrib => Icons.nights_stay_outlined,
  PrayerName.isha => Icons.dark_mode_outlined,
};

String _periodLabel(String period) => switch (period) {
  'daily' => 'يومي',
  'weekly' => 'أسبوعي',
  'monthly' => 'شهري',
  _ => period,
};
