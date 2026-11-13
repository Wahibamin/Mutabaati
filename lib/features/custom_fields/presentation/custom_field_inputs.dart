import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../data/custom_fields_repository.dart';

/// يمثّل قيمة حقل مخصص جاهزة للحفظ.
class CustomFieldEntry {
  const CustomFieldEntry({
    required this.definition,
    this.valueText,
    this.valueInteger,
    this.valueBoolean,
    this.valueDate,
  });

  final CustomFieldDefinition definition;
  final String? valueText;
  final int? valueInteger;
  final bool? valueBoolean;
  final DateTime? valueDate;

  bool get isEmpty =>
      valueText == null &&
      valueInteger == null &&
      valueBoolean == null &&
      valueDate == null;
}

/// يعرض حقولاً مخصصة بحسب تعريفاتها ويجمع القيم المُدخلة.
/// استخدم [CustomFieldFormState] عبر GlobalKey للوصول إلى القيم عند الحفظ.
class CustomFieldForm extends StatefulWidget {
  const CustomFieldForm({
    super.key,
    required this.definitions,
    this.initialValues = const {},
  });

  final List<CustomFieldDefinition> definitions;

  /// قيم مبدئية: definitionId -> CustomFieldValue
  final Map<String, CustomFieldValue> initialValues;

  @override
  State<CustomFieldForm> createState() => CustomFieldFormState();
}

class CustomFieldFormState extends State<CustomFieldForm> {
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, bool?> _boolValues = {};
  final Map<String, DateTime?> _dateValues = {};

  @override
  void initState() {
    super.initState();
    for (final def in widget.definitions) {
      final existing = widget.initialValues[def.id];
      switch (_typeOf(def.fieldType)) {
        case CustomFieldType.shortText:
        case CustomFieldType.longText:
          _textControllers[def.id] = TextEditingController(
            text: existing?.valueText ?? def.defaultValue,
          );
        case CustomFieldType.number:
        case CustomFieldType.durationMinutes:
          _textControllers[def.id] = TextEditingController(
            text: existing?.valueInteger?.toString() ??
                def.defaultValue,
          );
        case CustomFieldType.yesNo:
          final raw = existing?.valueBoolean;
          final defVal = def.defaultValue;
          _boolValues[def.id] =
              raw ?? (defVal == 'true' ? true : defVal == 'false' ? false : null);
        case CustomFieldType.date:
          _dateValues[def.id] = existing?.valueDate;
        case CustomFieldType.singleChoice:
          _textControllers[def.id] = TextEditingController(
            text: existing?.valueText ?? def.defaultValue,
          );
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _textControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// يُعيد قائمة الإدخالات الجاهزة للحفظ.
  List<CustomFieldEntry> collectEntries() {
    return widget.definitions.map((def) {
      switch (_typeOf(def.fieldType)) {
        case CustomFieldType.shortText:
        case CustomFieldType.longText:
        case CustomFieldType.singleChoice:
          final raw = _textControllers[def.id]?.text.trim();
          return CustomFieldEntry(
            definition: def,
            valueText: (raw?.isEmpty ?? true) ? null : raw,
          );
        case CustomFieldType.number:
        case CustomFieldType.durationMinutes:
          final raw = _textControllers[def.id]?.text.trim() ?? '';
          final parsed = int.tryParse(raw);
          return CustomFieldEntry(definition: def, valueInteger: parsed);
        case CustomFieldType.yesNo:
          return CustomFieldEntry(
            definition: def,
            valueBoolean: _boolValues[def.id],
          );
        case CustomFieldType.date:
          return CustomFieldEntry(
            definition: def,
            valueDate: _dateValues[def.id],
          );
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.definitions.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          'حقول إضافية',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        ...widget.definitions.map((def) => _buildField(context, def)),
      ],
    );
  }

  Widget _buildField(BuildContext context, CustomFieldDefinition def) {
    switch (_typeOf(def.fieldType)) {
      case CustomFieldType.shortText:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _textControllers[def.id],
            decoration: InputDecoration(
              labelText: def.label +
                  (def.isRequired ? ' *' : ''),
            ),
          ),
        );
      case CustomFieldType.longText:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _textControllers[def.id],
            maxLines: 3,
            decoration: InputDecoration(
              labelText: def.label +
                  (def.isRequired ? ' *' : ''),
            ),
          ),
        );
      case CustomFieldType.number:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _textControllers[def.id],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: def.label +
                  (def.isRequired ? ' *' : ''),
            ),
          ),
        );
      case CustomFieldType.durationMinutes:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _textControllers[def.id],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '${def.label}${def.isRequired ? ' *' : ''} (دقائق)',
            ),
          ),
        );
      case CustomFieldType.yesNo:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  def.label + (def.isRequired ? ' *' : ''),
                ),
              ),
              ToggleButtons(
                isSelected: [
                  _boolValues[def.id] == true,
                  _boolValues[def.id] == null,
                  _boolValues[def.id] == false,
                ],
                onPressed: (index) => setState(() {
                  _boolValues[def.id] = switch (index) {
                    0 => true,
                    2 => false,
                    _ => null,
                  };
                }),
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('نعم'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('—'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('لا'),
                  ),
                ],
              ),
            ],
          ),
        );
      case CustomFieldType.date:
        final picked = _dateValues[def.id];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  picked == null
                      ? def.label + (def.isRequired ? ' *' : '')
                      : '${def.label}: '
                          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
                ),
              ),
              TextButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final result = await showDatePicker(
                    context: context,
                    initialDate: picked ?? now,
                    firstDate: DateTime(now.year - 10),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (result != null) {
                    setState(() => _dateValues[def.id] = result);
                  }
                },
                child: const Text('اختر'),
              ),
              if (picked != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () =>
                      setState(() => _dateValues[def.id] = null),
                ),
            ],
          ),
        );
      case CustomFieldType.singleChoice:
        // بدون خيارات من قاعدة البيانات هنا نعرض حقل نص كبديل
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _textControllers[def.id],
            decoration: InputDecoration(
              labelText: def.label + (def.isRequired ? ' *' : ''),
            ),
          ),
        );
    }
  }

  static CustomFieldType _typeOf(String name) =>
      CustomFieldType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => CustomFieldType.shortText,
      );
}
