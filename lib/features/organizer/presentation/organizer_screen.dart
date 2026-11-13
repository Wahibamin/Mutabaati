import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

class OrganizerScreen extends ConsumerWidget {
  const OrganizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskOccurrencesProvider);
    final appointments = ref.watch(appointmentOccurrencesProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('المهام', style: Theme.of(context).textTheme.titleLarge),
          tasks.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('تعذر تحميل المهام.'),
            data: (rows) => rows.isEmpty
                ? const ListTile(
                    leading: Icon(Icons.checklist_outlined),
                    title: Text('لا توجد مهام.'),
                  )
                : Column(
                    children: rows
                        .map(
                          (row) => ListTile(
                            leading: Checkbox(
                              value: row.isCompleted,
                              onChanged: row.isCancelled
                                  ? null
                                  : (value) => ref
                                      .read(organizerRepositoryProvider)
                                      .setTaskCompleted(row.id, value ?? false),
                            ),
                            title: Text(
                              row.dueAt == null
                                  ? 'مهمة'
                                  : 'مهمة • ${row.dueAt!.toLocal().toString().substring(0, 16)}',
                            ),
                            subtitle: Text(
                              row.isCancelled
                                  ? 'ملغاة'
                                  : row.isCompleted
                                      ? 'منجزة'
                                      : 'مستحقة',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'snooze') {
                                  ref.read(organizerRepositoryProvider).snoozeTask(row.id);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأجيل المنبه 10 دقائق')));
                                } else if (action == 'cancel') {
                                  // Can add cancel logic if added to repo
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'snooze',
                                  child: Text('تأجيل التنبيه'),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),
          Text('المواعيد', style: Theme.of(context).textTheme.titleLarge),
          appointments.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('تعذر تحميل المواعيد.'),
            data: (rows) => rows.isEmpty
                ? const ListTile(
                    leading: Icon(Icons.event_outlined),
                    title: Text('لا توجد مواعيد.'),
                  )
                : Column(
                    children: rows
                        .map(
                          (row) => ListTile(
                            leading: const Icon(Icons.event),
                            title: Text(row.startsAt.toLocal().toString().substring(0, 16)),
                            subtitle: Text(row.status),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'snooze') {
                                  ref.read(organizerRepositoryProvider).snoozeAppointment(row.id);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأجيل المنبه 10 دقائق')));
                                } else {
                                  ref.read(organizerRepositoryProvider).setAppointmentStatus(row.id, action);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'attended', child: Text('تم الحضور')),
                                PopupMenuItem(value: 'notAttended', child: Text('لم يتم الحضور')),
                                PopupMenuItem(value: 'cancelled', child: Text('إلغاء الموعد')),
                                PopupMenuItem(value: 'snooze', child: Text('تأجيل التنبيه')),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMenu(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
    );
  }

  Future<void> _showAddMenu(BuildContext context, WidgetRef ref) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.check),
              title: const Text('مهمة جديدة'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('موعد جديد'),
              onTap: () => Navigator.pop(context, 'appointment'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !context.mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEventDialog(type: type),
    );

    if (result == null || !context.mounted) return;

    final title = result['title'] as String;
    final recurrence = result['recurrence'] as String;
    final hasReminder = result['hasReminder'] as bool;

    try {
      if (type == 'task') {
        final dueAt = result['dueAt'] as DateTime?;
        await ref.read(organizerRepositoryProvider).addTask(
              title: title,
              dueAt: dueAt,
              recurrenceRule: recurrence,
              hasReminder: hasReminder,
            );
      } else {
        final startsAt = result['startsAt'] as DateTime;
        final endsAt = result['endsAt'] as DateTime;
        await ref.read(organizerRepositoryProvider).addAppointment(
              title: title,
              startsAt: startsAt,
              endsAt: endsAt,
              timezoneId: ref.read(appSettingsProvider).value?.timezoneId ?? 'UTC',
              recurrenceRule: recurrence,
              hasReminder: hasReminder,
            );
      }
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _AddEventDialog extends StatefulWidget {
  final String type;
  const _AddEventDialog({required this.type});

  @override
  State<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<_AddEventDialog> {
  final _controller = TextEditingController();
  String _recurrence = 'none';
  bool _hasReminder = false;
  
  DateTime? _taskDueAt;
  DateTime _apptStartsAt = DateTime.now().add(const Duration(hours: 1));
  DateTime _apptEndsAt = DateTime.now().add(const Duration(hours: 2));

  Future<void> _pickDateTime({required bool isStart}) async {
    final initialDate = isStart ? _apptStartsAt : _apptEndsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;
    
    final result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (widget.type == 'task') {
        _taskDueAt = result;
      } else {
        if (isStart) {
          _apptStartsAt = result;
          if (_apptEndsAt.isBefore(_apptStartsAt)) {
            _apptEndsAt = _apptStartsAt.add(const Duration(hours: 1));
          }
        } else {
          _apptEndsAt = result;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.type == 'task' ? 'مهمة جديدة' : 'موعد جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            const SizedBox(height: 16),
            
            if (widget.type == 'task') ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('وقت الاستحقاق (اختياري)'),
                subtitle: Text(_taskDueAt == null ? 'غير محدد' : _taskDueAt!.toLocal().toString().substring(0, 16)),
                trailing: const Icon(Icons.access_time),
                onTap: () => _pickDateTime(isStart: true),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('البداية'),
                subtitle: Text(_apptStartsAt.toLocal().toString().substring(0, 16)),
                trailing: const Icon(Icons.access_time),
                onTap: () => _pickDateTime(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('النهاية'),
                subtitle: Text(_apptEndsAt.toLocal().toString().substring(0, 16)),
                trailing: const Icon(Icons.access_time),
                onTap: () => _pickDateTime(isStart: false),
              ),
            ],

            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'التكرار'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('لا يتكرر')),
                DropdownMenuItem(value: 'daily', child: Text('يومياً')),
                DropdownMenuItem(value: 'weekly,1', child: Text('كل اثنين')),
                DropdownMenuItem(value: 'weekly,4', child: Text('كل خميس')),
                DropdownMenuItem(value: 'weekly,5', child: Text('كل جمعة')),
                DropdownMenuItem(value: 'monthly,1', child: Text('شهرياً (أول الشهر)')),
                DropdownMenuItem(value: 'monthly,15', child: Text('شهرياً (يوم 15)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _recurrence = val);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تفعيل المنبه'),
              value: _hasReminder,
              onChanged: (val) => setState(() => _hasReminder = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (_controller.text.trim().isEmpty) return;
            if (widget.type == 'appointment' && _apptEndsAt.isBefore(_apptStartsAt)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نهاية الموعد قبل بدايته')));
              return;
            }
            Navigator.pop(context, {
              'title': _controller.text,
              'recurrence': _recurrence,
              'hasReminder': _hasReminder,
              'dueAt': _taskDueAt,
              'startsAt': _apptStartsAt,
              'endsAt': _apptEndsAt,
            });
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
