import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';

/// شاشة سجل «آخر العمليات» الموحد مع البحث السريع والفلترة حسب نوع الحركة (صفحة 3)
class RecentOperationsScreen extends ConsumerStatefulWidget {
  const RecentOperationsScreen({super.key});

  @override
  ConsumerState<RecentOperationsScreen> createState() =>
      _RecentOperationsScreenState();
}

class _RecentOperationsScreenState
    extends ConsumerState<RecentOperationsScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final opsAsync = ref.watch(recentOperationsStreamProvider);
    final settings = ref.watch(appSettingsStreamProvider).valueOrNull;
    final currency = settings?.currency ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل آخر العمليات الموحد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ابحث باسم الزبون، المورد، أو الصنف...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('الكل', 'ALL'),
                const SizedBox(width: 6),
                _buildFilterChip('مبيعات', 'SALE'),
                const SizedBox(width: 6),
                _buildFilterChip('مشتريات', 'PURCHASE'),
                const SizedBox(width: 6),
                _buildFilterChip('سداد زبون', 'CUSTOMER_PAY'),
                const SizedBox(width: 6),
                _buildFilterChip('سداد مورد', 'SUPPLIER_PAY'),
                const SizedBox(width: 6),
                _buildFilterChip('مصاريف', 'EXPENSE'),
                const SizedBox(width: 6),
                _buildFilterChip('مرتجع / تالف', 'RETURN_WASTE'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: opsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (ops) {
                final filtered = ops.where((op) {
                  if (_selectedFilter == 'RETURN_WASTE') {
                    if (op.type != 'RETURN' && op.type != 'WASTAGE') {
                      return false;
                    }
                  } else if (_selectedFilter != 'ALL' &&
                      op.type != _selectedFilter) {
                    return false;
                  }
                  if (_searchQuery.trim().isNotEmpty) {
                    final q = _searchQuery.trim().toLowerCase();
                    return op.title.toLowerCase().contains(q) ||
                        op.subtitle.toLowerCase().contains(q);
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('لا توجد حركات مطابقة للبحث أو الفلتر'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final op = filtered[index];
                    return Card(
                      child: ListTile(
                        title: Text(op.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            '${op.subtitle}\n${AppFormatters.formatDateTime(op.createdAt)}'),
                        isThreeLine: true,
                        trailing: Text(
                          AppFormatters.formatMoney(op.amount,
                              currency: currency),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: op.isPositiveCash
                                ? AppColors.cashGreen
                                : AppColors.debtRed,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilter = value),
    );
  }
}
