import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// شاشة تشخيص التنبيهات.
/// تعرض حالة الأذونات وتتيح طلبها واختبار تنبيه بعد دقيقة.
/// لا تعتبر «مجدول» دليلاً على «وصل» — اختبر على جهاز فعلي.
class NotificationDiagnosticsScreen extends StatefulWidget {
  const NotificationDiagnosticsScreen({super.key});

  @override
  State<NotificationDiagnosticsScreen> createState() =>
      _NotificationDiagnosticsScreenState();
}

class _NotificationDiagnosticsScreenState
    extends State<NotificationDiagnosticsScreen> {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool? _hasPermission;
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeAndCheck();
  }

  Future<void> _initializeAndCheck() async {
    setState(() => _isLoading = true);
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );
    setState(() {
      _initialized = true;
      _isLoading = false;
    });
    await _checkPermission();
  }

  Future<void> _checkPermission() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      setState(() => _hasPermission = null);
      return;
    }
    final granted =
        await androidPlugin.areNotificationsEnabled() ?? false;
    setState(() => _hasPermission = granted);
  }

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      setState(() {
        _statusMessage = 'المنصة غير مدعومة في هذا البيئة.';
        _isLoading = false;
      });
      return;
    }
    final granted = await androidPlugin.requestNotificationsPermission();
    setState(() {
      _hasPermission = granted ?? false;
      _statusMessage = (granted ?? false)
          ? 'تم منح الإذن.'
          : 'رُفض الإذن. يمكنك تفعيله من إعدادات النظام.';
      _isLoading = false;
    });
  }

  Future<void> _scheduleTestNotification() async {
    if (_hasPermission != true) {
      setState(
        () => _statusMessage = 'اطلب الإذن أولاً قبل جدولة إشعار.',
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      // استخدام timezone إن توفّر، وإلا تنبيه فوري بعد ثانية
      final now = tz.TZDateTime.now(tz.local);
      final scheduled = now.add(const Duration(minutes: 1));
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'mutabaati_test_channel',
          'اختبار التنبيهات',
          channelDescription: 'قناة اختبار تنبيهات متابعتي',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'اختبار',
        ),
      );
      await _plugin.zonedSchedule(
        id: 9999,
        title: 'اختبار التنبيه',
        body: 'هذا تنبيه تجريبي من متابعتي — ${scheduled.hour}:${scheduled.minute.toString().padLeft(2, '0')}',
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      setState(() {
        _statusMessage =
            'جُدول تنبيه تجريبي بعد دقيقة. '
            'تحقق من الجهاز — «مجدول» لا يعني «وصل» تلقائيًا.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'فشل الجدولة: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelAll() async {
    await _plugin.cancelAll();
    setState(() => _statusMessage = 'أُلغيت جميع التنبيهات المجدولة.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تشخيص التنبيهات')),
      body: _isLoading && !_initialized
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── حالة الإذن ────────────────────────────────────────────
                Card(
                  child: ListTile(
                    leading: Icon(
                      _hasPermission == true
                          ? Icons.check_circle
                          : _hasPermission == false
                              ? Icons.cancel
                              : Icons.help_outline,
                      color: _hasPermission == true
                          ? Colors.green
                          : _hasPermission == false
                              ? Colors.red
                              : Colors.grey,
                    ),
                    title: const Text('إذن الإشعارات'),
                    subtitle: Text(
                      _hasPermission == true
                          ? 'مُمنوح'
                          : _hasPermission == false
                              ? 'مرفوض أو غير ممنوح'
                              : 'غير معروف',
                    ),
                    trailing: TextButton(
                      onPressed: _checkPermission,
                      child: const Text('تحديث'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ─── تقييد المنبّه الدقيق ──────────────────────────────────
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.blue),
                    title: Text('قيود المنبّه الدقيق'),
                    subtitle: Text(
                      'Android 12+ قد يقيّد المنبّهات الدقيقة. '
                      'تأكد من منح SCHEDULE_EXACT_ALARM من إعدادات النظام. '
                      'وضع عدم الإزعاج وإيقاف التطبيق قسراً قد يمنع الرنين.',
                    ),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 8),

                // ─── النسخة الاحتياطية للإشعار ─────────────────────────────
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text('حدود المنصة'),
                    subtitle: Text(
                      'لا يُضمن رنين المنبّه عندما:\n'
                      '• الهاتف مُطفأ أو التطبيق موقوف إجباريًا.\n'
                      '• الأذونات مسحوبة.\n'
                      'الإشعار البديل يعمل ضمن قيود النظام فقط.',
                    ),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 16),

                // ─── رسالة الحالة ──────────────────────────────────────────
                if (_statusMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusMessage.startsWith('فشل') ||
                                _statusMessage.contains('رُفض')
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // ─── الأزرار ────────────────────────────────────────────────
                if (_hasPermission != true)
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _requestPermission,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('طلب إذن الإشعارات'),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _scheduleTestNotification,
                    icon: const Icon(Icons.alarm_add_outlined),
                    label: const Text('اختبار تنبيه بعد دقيقة'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _cancelAll,
                    icon: const Icon(Icons.alarm_off_outlined),
                    label: const Text('إلغاء جميع التنبيهات المجدولة'),
                  ),
                ],

                const SizedBox(height: 16),
                const Text(
                  'ملاحظة: «مجدول» لا يعني «وصل». اختبر على جهاز فعلي '
                  'في الخلفية وعند قفل الشاشة.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}
