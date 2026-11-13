import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'weekly'; // 'weekly' or 'monthly'
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  final DateTime _endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'weekly', label: Text('أسبوعي')),
                ButtonSegment(value: 'monthly', label: Text('شهري')),
              ],
              selected: {_period},
              onSelectionChanged: (val) {
                setState(() {
                  _period = val.first;
                  if (_period == 'weekly') {
                    _startDate = DateTime.now().subtract(const Duration(days: 7));
                  } else {
                    _startDate = DateTime.now().subtract(const Duration(days: 30));
                  }
                });
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTrackingReport(context),
                const SizedBox(height: 16),
                _buildPrayersReport(context),
                const SizedBox(height: 16),
                _buildExpenseReport(context),
                const SizedBox(height: 16),
                _buildTasksReport(context),
                const SizedBox(height: 16),
                _buildAppointmentsReport(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseReport(BuildContext context) {
    final startLocal = _startDate.toIso8601String().substring(0, 10);
    final endLocal = _endDate.toIso8601String().substring(0, 10);

    return FutureBuilder(
      future: ref.read(reportsRepositoryProvider).getExpensesReport(startLocal, endLocal),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (snap.hasError) return Text('خطأ: ${snap.error}');
        final data = snap.data as Map<String, dynamic>;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المصاريف', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('الإجمالي: ${(data['total'] as int) / 100}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTasksReport(BuildContext context) {
    return FutureBuilder(
      future: ref.read(reportsRepositoryProvider).getTasksReport(_startDate, _endDate),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (snap.hasError) return Text('خطأ: ${snap.error}');
        final data = snap.data as Map<String, dynamic>;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المهام', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('الإجمالي: ${data['total']}'),
                Text('مكتملة: ${data['completed']}'),
                Text('متأخرة: ${data['overdue']}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppointmentsReport(BuildContext context) {
    return FutureBuilder(
      future: ref.read(reportsRepositoryProvider).getAppointmentsReport(_startDate, _endDate),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (snap.hasError) return Text('خطأ: ${snap.error}');
        final data = snap.data as Map<String, dynamic>;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المواعيد', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('الإجمالي: ${data['total']}'),
                Text('تم الحضور: ${data['attended']}'),
                Text('لم يتم الحضور: ${data['missed']}'),
                Text('ملغاة: ${data['cancelled']}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrayersReport(BuildContext context) {
    final startLocal = _startDate.toIso8601String().substring(0, 10);
    final endLocal = _endDate.toIso8601String().substring(0, 10);

    return FutureBuilder(
      future: ref.read(reportsRepositoryProvider).getPrayersReport(startLocal, endLocal),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (snap.hasError) return Text('خطأ: ${snap.error}');
        final data = snap.data as Map<String, dynamic>;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الصلوات', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('سجلات: ${data['total_recorded']}'),
                Text('جماعة: ${data['jamaah']}'),
                Text('فردي: ${data['individual']}'),
                Text('تأخير: ${data['late']}'),
                Text('لم تؤد: ${data['missed']}'),
                Text('معذور: ${data['excused']}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackingReport(BuildContext context) {
    final startLocal = _startDate.toIso8601String().substring(0, 10);
    final endLocal = _endDate.toIso8601String().substring(0, 10);

    return FutureBuilder(
      future: ref.read(reportsRepositoryProvider).getTrackingReport(startLocal, endLocal),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (snap.hasError) return Text('خطأ: ${snap.error}');
        final data = snap.data as Map<String, dynamic>;
        final total = data['total'] as int;
        final completed = data['completed'] as int;
        final percentage = total == 0 ? 0 : (completed / total * 100).round();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المتابعة (نسبة الإنجاز)', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('المنجزة: $completed / $total'),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total == 0 ? 0 : completed / total),
                const SizedBox(height: 4),
                Text('$percentage%', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );
  }
}
