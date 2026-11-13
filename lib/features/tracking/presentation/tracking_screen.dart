import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/local_date.dart';
import '../domain/tracking_models.dart';

class TrackingScreen extends ConsumerWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(trackingSectionsProvider);
    final templates = ref.watch(activeTemplatesProvider);

    return Scaffold(
      body: sections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('تعذر تحميل أقسام المتابعة.')),
        data: (sectionList) => templates.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('تعذر تحميل بنود المتابعة.')),
          data: (templateList) {
            if (sectionList.isEmpty && templateList.isEmpty) {
              return _EmptyState(onAdd: () => _add(context, ref, []));
            }
            // تجميع البنود حسب القسم
            final bySection = <String, List<ActivityTemplate>>{};
            for (final t in templateList) {
              final key = t.sectionId ?? '__none__';
              bySection.putIfAbsent(key, () => []).add(t);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final section in sectionList) ...[
                  _SectionHeader(
                    section: section,
                    onArchive: () => _archiveSection(context, ref, section),
                  ),
                  ...?bySection[section.id]?.map(
                    (t) => _TemplateCard(
                      template: t,
                      onArchive: () => ref
                          .read(trackingRepositoryProvider)
                          .archiveTemplate(t.id),
                      onTap: () =>
                          _recordEntry(context, ref, t, localDateKey()),
                      onLongPress: () =>
                          _pickDateAndRecord(context, ref, t),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // بنود بدون قسم
                if (bySection.containsKey('__none__')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'بنود غير مصنّفة',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...bySection['__none__']!.map(
                    (t) => _TemplateCard(
                      template: t,
                      onArchive: () => ref
                          .read(trackingRepositoryProvider)
                          .archiveTemplate(t.id),
                      onTap: () => _recordEntry(context, ref, t, localDateKey()),
                      onLongPress: () => _pickDateAndRecord(context, ref, t),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: sections.maybeWhen(
        data: (sectionList) => FloatingActionButton.extended(
          onPressed: () => _add(context, ref, sectionList),
          icon: const Icon(Icons.add),
          label: const Text('إضافة'),
        ),
        orElse: () => null,
      ),
    );
  }

  // ─── إضافة قسم أو بند ────────────────────────────────────────────────────

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<Section> sections,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('قسم جديد'),
              leading: const Icon(Icons.folder_outlined),
              onTap: () => Navigator.pop(context, 'section'),
            ),
            ListTile(
              title: const Text('بند متابعة جديد'),
              leading: const Icon(Icons.checklist),
              onTap: () => Navigator.pop(context, 'template'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'section') {
      await _addSection(context, ref);
    } else {
      await _addTemplate(context, ref, sections);
    }
  }

  Future<void> _addSection(BuildContext context, WidgetRef ref) async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('قسم جديد'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم القسم'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      await ref.read(trackingRepositoryProvider).addSection(value);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _addTemplate(
    BuildContext context,
    WidgetRef ref,
    List<Section> sections,
  ) async {
    // إذا لم يوجد أقسام نطلب إنشاء قسم أولاً
    if (sections.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أضف قسمًا أولًا.')),
        );
      }
      return;
    }

    final nameCtrl = TextEditingController();
    var selectedSectionId = sections.first.id;
    var selectedPeriod = TrackingPeriod.daily;
    var selectedType = TrackingType.boolean;
    final targetCtrl = TextEditingController(text: '1');

    final result = await showDialog<_TemplateDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('بند متابعة جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الاسم
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم البند *'),
                ),
                const SizedBox(height: 12),
                // القسم
                DropdownButtonFormField<String>(
                  initialValue: selectedSectionId,
                  decoration: const InputDecoration(labelText: 'القسم'),
                  items: sections
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => selectedSectionId = v!),
                ),
                const SizedBox(height: 12),
                // الدورية
                DropdownButtonFormField<TrackingPeriod>(
                  initialValue: selectedPeriod,
                  decoration: const InputDecoration(labelText: 'الدورية'),
                  items: TrackingPeriod.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(_periodLabel(p.name)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => selectedPeriod = v!),
                ),
                const SizedBox(height: 12),
                // نوع المتابعة
                DropdownButtonFormField<TrackingType>(
                  initialValue: selectedType,
                  decoration:
                      const InputDecoration(labelText: 'نوع المتابعة'),
                  items: TrackingType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabel(t.name)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => selectedType = v!),
                ),
                const SizedBox(height: 12),
                // الهدف (للعدد والمدة)
                if (selectedType == TrackingType.count ||
                    selectedType == TrackingType.duration)
                  TextField(
                    controller: targetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: selectedType == TrackingType.duration
                          ? 'الهدف (دقائق)'
                          : 'الهدف (عدد)',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final target = int.tryParse(targetCtrl.text) ?? 1;
                Navigator.pop(
                  dialogContext,
                  _TemplateDraft(
                    name: name,
                    sectionId: selectedSectionId,
                    period: selectedPeriod,
                    type: selectedType,
                    target: target > 0 ? target : 1,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    targetCtrl.dispose();
    if (result == null || !context.mounted) return;

    try {
      await ref.read(trackingRepositoryProvider).addTemplate(
            sectionId: result.sectionId,
            name: result.name,
            period: result.period,
            type: result.type,
            target: result.target,
            localDate: localDateKey(),
          );
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  // ─── تسجيل مدخل ────────────────────────────────────────────────────────────────

  /// يفتح منتقي تاريخ ثم يسجّل مدخل لتاريخ سابق (ضغطة طويلة على البند).
  Future<void> _pickDateAndRecord(
    BuildContext context,
    WidgetRef ref,
    ActivityTemplate template,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: 'اختر تاريخ التسجيل',
    );
    if (picked == null || !context.mounted) return;
    final localDate =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await _recordEntry(context, ref, template, localDate);
  }

  Future<void> _recordEntry(
    BuildContext context,
    WidgetRef ref,
    ActivityTemplate template,
    String localDate,
  ) async {
    // جلب نسخة الجدول السارية في ذلك التاريخ
    final scheduleVersion = await ref
        .read(trackingRepositoryProvider)
        .getScheduleVersionForDate(template.id, localDate);
    if (scheduleVersion == null) return;
    if (!context.mounted) return;

    final trackingType = TrackingType.values.firstWhere(
      (t) => t.name == template.trackingType,
      orElse: () => TrackingType.boolean,
    );

    if (trackingType == TrackingType.boolean) {
      // اختيار مباشر من قائمة
      final state = await showModalBottomSheet<TrackingState>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('منجز'),
                onTap: () =>
                    Navigator.pop(ctx, TrackingState.completed),
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('غير منجز'),
                onTap: () =>
                    Navigator.pop(ctx, TrackingState.explicitlyNotCompleted),
              ),
              ListTile(
                leading: const Icon(
                  Icons.block,
                  color: Colors.grey,
                ),
                title: const Text('غير منطبق'),
                onTap: () =>
                    Navigator.pop(ctx, TrackingState.notApplicable),
              ),
            ],
          ),
        ),
      );
      if (state == null) return;
      if (!context.mounted) return;
      await ref.read(trackingRepositoryProvider).saveEntry(
            scheduleVersionId: scheduleVersion.id,
            localDate: localDate,
            state: state,
          );
    } else {
      // نموذج قيمة
      if (!context.mounted) return;
      final ctrl = TextEditingController();
      final state = await showDialog<_EntryInput>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(template.name),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: trackingType == TrackingType.text
                ? TextInputType.text
                : TextInputType.number,
            decoration: InputDecoration(
              labelText: trackingType == TrackingType.duration
                  ? 'المدة (دقائق)'
                  : trackingType == TrackingType.count
                      ? 'العدد'
                      : 'القيمة',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final raw = ctrl.text.trim();
                if (trackingType == TrackingType.text) {
                  Navigator.pop(
                    dialogCtx,
                    _EntryInput(
                      state: TrackingState.completed,
                      textValue: raw.isEmpty ? null : raw,
                    ),
                  );
                } else {
                  final n = int.tryParse(raw);
                  if (n == null) return;
                  Navigator.pop(
                    dialogCtx,
                    _EntryInput(
                      state: TrackingState.completed,
                      numericValue: n,
                    ),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (state == null) return;
      if (!context.mounted) return;
      await ref.read(trackingRepositoryProvider).saveEntry(
            scheduleVersionId: scheduleVersion.id,
            localDate: localDate,
            state: state.state,
            numericValue: state.numericValue,
            textValue: state.textValue,
          );
    }
  }

  Future<void> _archiveSection(
    BuildContext context,
    WidgetRef ref,
    Section section,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('أرشفة «${section.name}»؟'),
        content: const Text(
          'سيختفي القسم وبنوده من العرض. يمكن استعادة السجلات لاحقًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(trackingRepositoryProvider).archiveSection(section.id);
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _periodLabel(String period) => switch (period) {
  'daily' => 'يومي',
  'weekly' => 'أسبوعي',
  'monthly' => 'شهري',
  _ => period,
};

String _typeLabel(String type) => switch (type) {
  'boolean' => 'نعم / لا',
  'count' => 'عدد',
  'duration' => 'مدة',
  'text' => 'نص',
  _ => type,
};

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.onArchive});
  final Section section;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          section.name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.archive_outlined, size: 20),
        tooltip: 'أرشفة القسم',
        onPressed: onArchive,
      ),
    ],
  );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onArchive,
    required this.onTap,
    this.onLongPress,
  });

  final ActivityTemplate template;
  final VoidCallback onArchive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(_typeIcon(template.trackingType)),
      title: Text(template.name),
      subtitle: Text(
        '${_periodLabel(template.periodicity)} · ${_typeLabel(template.trackingType)}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.archive_outlined),
        tooltip: 'أرشفة',
        onPressed: onArchive,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    ),
  );

  IconData _typeIcon(String type) => switch (type) {
    'boolean' => Icons.check_circle_outline,
    'count' => Icons.pin_outlined,
    'duration' => Icons.timer_outlined,
    'text' => Icons.notes,
    _ => Icons.check_circle_outline,
  };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.checklist, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text(
          'لا توجد بنود متابعة بعد.\nأضف قسمًا ثم بنودًا لتبدأ.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('إضافة'),
        ),
      ],
    ),
  );
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _TemplateDraft {
  const _TemplateDraft({
    required this.name,
    required this.sectionId,
    required this.period,
    required this.type,
    required this.target,
  });

  final String name;
  final String sectionId;
  final TrackingPeriod period;
  final TrackingType type;
  final int target;
}

class _EntryInput {
  const _EntryInput({
    required this.state,
    this.numericValue,
    this.textValue,
  });

  final TrackingState state;
  final int? numericValue;
  final String? textValue;
}
