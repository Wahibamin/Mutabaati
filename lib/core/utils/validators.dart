/// أدوات التحقق الصارمة لمنع الأخطاء المحاسبية (TC-08)
class AppValidators {
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'يرجى إدخال $fieldName';
    }
    return null;
  }

  static String? validatePositiveNumber(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'يرجى إدخال $fieldName';
    }
    final parsed = double.tryParse(value.replaceAll(',', '').trim());
    if (parsed == null) {
      return 'يرجى إدخال رقم صحيح في حقل $fieldName';
    }
    if (parsed <= 0) {
      return 'يجب أن تكون قيمة $fieldName أكبر من صفر';
    }
    return null;
  }

  static String? validateNonNegativeNumber(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return null; // يعتبر صفر إذا تُرك فارغًا في حقل المدفوع
    }
    final parsed = double.tryParse(value.replaceAll(',', '').trim());
    if (parsed == null) {
      return 'يرجى إدخال رقم صحيح في حقل $fieldName';
    }
    if (parsed < 0) {
      return 'لا يمكن أن تكون قيمة $fieldName سالبة';
    }
    return null;
  }
}
