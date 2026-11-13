import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/utils/local_date.dart';
import '../../settings/data/settings_repository.dart';
import '../../tracking/domain/tracking_models.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _selectedTemplateIds = <String>{};
  String _currency = 'SAR';
  String _timezoneId = 'Asia/Riyadh';
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTimezone();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      if (mounted) setState(() => _timezoneId = timezone.identifier);
    } catch (_) {
      // The editable fallback remains available when the platform cannot answer.
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final fractionDigits = _currency == 'KWD' ? 3 : 2;
      await ref
          .read(settingsRepositoryProvider)
          .saveInitialSetup(
            AppSettings(
              isOnboarded: true,
              currencyCode: _currency,
              currencyFractionDigits: fractionDigits,
              timezoneId: _timezoneId.trim(),
              firstWeekday: DateTime.saturday,
              displayName: _nameController.text,
            ),
          );
      await ref
          .read(trackingRepositoryProvider)
          .applyInitialTemplates(_selectedTemplateIds, localDateKey());
      if (mounted) context.go('/home');
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الإعدادات. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.track_changes_rounded,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'مرحبًا بك في متابعتي',
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'إعداد محلي قصير، ويمكن تعديل معظم الخيارات لاحقًا.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم (اختياري)',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: const [
                    DropdownMenuItem(
                      value: 'SAR',
                      child: Text('ريال سعودي (منزلتان)'),
                    ),
                    DropdownMenuItem(
                      value: 'USD',
                      child: Text('دولار أمريكي (منزلتان)'),
                    ),
                    DropdownMenuItem(
                      value: 'EUR',
                      child: Text('يورو (منزلتان)'),
                    ),
                    DropdownMenuItem(
                      value: 'KWD',
                      child: Text('دينار كويتي (3 منازل)'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _currency = value!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: TextEditingController(text: _timezoneId),
                  key: ValueKey(_timezoneId),
                  decoration: const InputDecoration(
                    labelText: 'المنطقة الزمنية',
                  ),
                  onChanged: (value) => _timezoneId = value,
                ),
                const SizedBox(height: 24),
                Text('قوالب المتابعة الاختيارية', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                ...TrackingPeriod.values.expand(
                  (period) => [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        _periodLabel(period),
                        style: textTheme.titleMedium,
                      ),
                    ),
                    ...initialTemplateSeeds
                        .where((template) => template.period == period)
                        .map(
                          (template) => CheckboxListTile(
                            value: _selectedTemplateIds.contains(template.id),
                            title: Text(template.name),
                            subtitle: template.target > 1
                                ? Text('الهدف المقترح: ${template.target}')
                                : null,
                            onChanged: _isSaving
                                ? null
                                : (selected) => setState(() {
                                    selected == true
                                        ? _selectedTemplateIds.add(template.id)
                                        : _selectedTemplateIds.remove(
                                            template.id,
                                          );
                                  }),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_back_rounded),
                  label: const Text('بدء الاستخدام'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _periodLabel(TrackingPeriod period) => switch (period) {
    TrackingPeriod.daily => 'يومي',
    TrackingPeriod.weekly => 'أسبوعي',
    TrackingPeriod.monthly => 'شهري',
  };
}
