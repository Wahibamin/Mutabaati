import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../data/local_db/app_database.dart';

/// شاشة بيانات المستخدم (تسجيل اسم البائع/المحل، رقم الهاتف، ترويسة التقرير، والعملة الافتراضية - صفحة 3)
class UserInfoScreen extends ConsumerStatefulWidget {
  const UserInfoScreen({super.key});

  @override
  ConsumerState<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends ConsumerState<UserInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerController = TextEditingController();
  final _shopController = TextEditingController();
  final _phoneController = TextEditingController();
  String _currency = 'ر.ي';
  bool _loaded = false;

  @override
  void dispose() {
    _ownerController.dispose();
    _shopController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsStreamProvider);

    settingsAsync.whenData((s) {
      if (!_loaded) {
        _ownerController.text = s.ownerName;
        _shopController.text = s.shopName;
        _phoneController.text = s.phone;
        _currency = s.currency;
        _loaded = true;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات المستخدم والمحل'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _ownerController,
                      decoration: const InputDecoration(
                        labelText: 'اسم البائع (المقوت)',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى إدخال اسم البائع'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _shopController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المحل / الفرشة (ترويسة التقارير)',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى إدخال اسم المحل'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف (للتواصل والتقارير)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: ['ر.ي', 'ر.س', 'دولار'].contains(_currency)
                          ? _currency
                          : 'ر.ي',
                      decoration: const InputDecoration(
                        labelText: 'العملة الافتراضية',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'ر.ي', child: Text('ريال يمني (ر.ي)')),
                        DropdownMenuItem(
                            value: 'ر.س', child: Text('ريال سعودي (ر.س)')),
                        DropdownMenuItem(
                            value: 'دولار', child: Text('دولار أمريكي')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _currency = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        final current = await ref
                            .read(appDatabaseProvider)
                            .getAppSettings();
                        await ref.read(appDatabaseProvider).updateAppSettings(
                              ownerName: _ownerController.text.trim(),
                              shopName: _shopController.text.trim(),
                              phone: _phoneController.text.trim(),
                              currency: _currency,
                              pinCode: current.pinCode,
                              lastBackupAt: current.lastBackupAt,
                              gdriveEmail: current.gdriveEmail,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تم حفظ بيانات المستخدم بنجاح')),
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ بيانات المستخدم'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
