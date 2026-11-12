import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/backup/google_drive_backup_service.dart';
import '../../../data/local_db/app_database.dart';

/// شاشة الضبط (الإعدادات):
/// - إدارة النسخ الاحتياطي والاستعادة (محليًا وإلى Google Drive API v3)
/// - قفل التطبيق برمز PIN أو البصمة
/// - إدارة أصناف القات
/// - تصفير البيانات التجريبية
class SettingsAndBackupScreen extends ConsumerStatefulWidget {
  const SettingsAndBackupScreen({super.key});

  @override
  ConsumerState<SettingsAndBackupScreen> createState() =>
      _SettingsAndBackupScreenState();
}

class _SettingsAndBackupScreenState
    extends ConsumerState<SettingsAndBackupScreen> {
  bool _isWorking = false;

  Future<void> _createLocalBackupAndShare() async {
    setState(() => _isWorking = true);
    try {
      final zipFile =
          await ref.read(backupServiceProvider).createLocalBackupZip();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'تم إنشاء النسخة الاحتياطية المضغوطة: ${zipFile.path.split('/').last}')),
      );
      await Share.shareXFiles([XFile(zipFile.path)],
          text: 'نسخة احتياطية لتطبيق مقوتي');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر إنشاء النسخة الاحتياطية: $e'),
              backgroundColor: AppColors.debtRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _backupToGoogleDrive() async {
    setState(() => _isWorking = true);
    try {
      final email =
          await ref.read(backupServiceProvider).uploadBackupToGoogleDrive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم رفع النسخة الاحتياطية بنجاح إلى Google Drive ($email)'),
            backgroundColor: AppColors.cashGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'ملاحظة: يتطلب الرفع إلى Google Drive اتصالاً بالإنترنت وإعداد شهادة SHA-1: $e'),
            backgroundColor: AppColors.warningOrange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _showRestoreFromDriveSheet() async {
    setState(() => _isWorking = true);
    try {
      final backups =
          await ref.read(backupServiceProvider).listGoogleDriveBackups();
      if (!mounted) return;
      setState(() => _isWorking = false);

      if (backups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا توجد نسخ احتياطية سابقة في Google Drive')),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'اختر نسخة احتياطية للاستعادة من Google Drive',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: backups.length,
                  itemBuilder: (context, idx) {
                    final b = backups[idx];
                    final kb = (b.sizeBytes / 1024).toStringAsFixed(1);
                    return ListTile(
                      leading: const Icon(Icons.cloud_download_outlined,
                          color: AppColors.primaryGreen),
                      title: Text(b.name),
                      subtitle: Text(
                          '${AppFormatters.formatDateTime(b.createdTime)} • الحجم: $kb KB'),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        setState(() => _isWorking = true);
                        try {
                          await ref
                              .read(backupServiceProvider)
                              .downloadAndRestoreFromDrive(b.fileId);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'تمت استعادة قاعدة البيانات بنجاح والتحقق من سلامتها 100%'),
                                backgroundColor: AppColors.cashGreen,
                              ),
                            );
                          }
                        } catch (err) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('فشل الاستعادة: $err'),
                                  backgroundColor: AppColors.debtRed),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isWorking = false);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isWorking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر جلب النسخ من Google Drive: $e')),
        );
      }
    }
  }

  void _showPinDialog() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قفل التطبيق برمز PIN'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'أدخل رمز PIN جديدًا (فارغ لإلغاء القفل)',
            helperText: 'لا يتم عرض الرمز الحالي أو تخزينه كنص صريح',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final s = await ref.read(appDatabaseProvider).getAppSettings();
              final newPin =
                  pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim();
              await ref.read(appDatabaseProvider).updateAppSettings(
                    ownerName: s.ownerName,
                    shopName: s.shopName,
                    phone: s.phone,
                    currency: s.currency,
                    pinCode: newPin,
                    lastBackupAt: s.lastBackupAt,
                    gdriveEmail: s.gdriveEmail,
                  );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حفظ الرمز'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final settings = settingsAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الضبط والنسخ الاحتياطي'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isWorking)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_sync_outlined,
                          color: AppColors.primaryGreen, size: 28),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'النسخ الاحتياطي السحابي (Google Drive)',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'آخر نسخة احتياطية: ${settings?.lastBackupAt != null ? AppFormatters.formatDateTime(settings!.lastBackupAt!) : 'لم يتم النسخ بعد'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (settings?.gdriveEmail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'الحساب المرتبط: ${settings!.gdriveEmail}',
                      style: const TextStyle(
                          color: AppColors.primaryGreen, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: _isWorking ? null : _backupToGoogleDrive,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'رفع نسخة احتياطية إلى Google Drive الآن',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: _isWorking ? null : _showRestoreFromDriveSheet,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_download_outlined),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'استعادة نسخة احتياطية من Google Drive',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: _isWorking ? null : _createLocalBackupAndShare,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_zip_outlined),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'حفظ ومشاركة نسخة مضغوطة (ZIP + Metadata)',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline,
                      color: AppColors.primaryGreen),
                  title: const Text('قفل التطبيق برمز PIN أو البصمة'),
                  subtitle: Text(
                    settings?.pinCode != null
                        ? 'مفعّل لحماية خصوصية الحسابات'
                        : 'غير مفعّل حاليًا',
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: _showPinDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined,
                      color: AppColors.debtRed),
                  title: const Text(
                    'تصفير البيانات التجريبية',
                    style: TextStyle(
                        color: AppColors.debtRed, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                      'حذف الحركات التجريبية للبدء الفعلي مع الحفاظ على الأصناف'),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('تأكيد تصفير البيانات التجريبية'),
                        content: const Text(
                          'سيتم مسح جميع حركات المبيعات والمشتريات والسدادات التجريبية وتصفير الأرصدة. هل أنت متأكد؟',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.debtRed),
                            onPressed: () async {
                              await ref
                                  .read(appDatabaseProvider)
                                  .resetTransactionalData();
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'تم تصفير البيانات التجريبية بنجاح')),
                                );
                              }
                            },
                            child: const Text('تأكيد التصفير'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
