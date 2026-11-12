import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';

/// لوحة أرقام كبيرة (Custom Numeric Keypad) كما وردت في المرحلة السادسة (صفحة 11):
/// عند إدخال الكمية أو السعر أو مبلغ السداد، تُفتح لوحة أرقام واضحة مع أزرار فئات مالية
/// سريعة شائعة (1000، 2000، 5000، 10000) لتوفير وقت الكتابة لبائع القات.
class CustomNumericKeypad extends StatefulWidget {
  final String title;
  final double initialValue;
  final bool showQuickAmounts;
  final ValueChanged<double> onConfirmed;

  const CustomNumericKeypad({
    super.key,
    required this.title,
    this.initialValue = 0,
    this.showQuickAmounts = true,
    required this.onConfirmed,
  });

  static Future<double?> show(
    BuildContext context, {
    required String title,
    double initialValue = 0,
    bool showQuickAmounts = true,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return CustomNumericKeypad(
          title: title,
          initialValue: initialValue,
          showQuickAmounts: showQuickAmounts,
          onConfirmed: (val) => Navigator.of(ctx).pop(val),
        );
      },
    );
  }

  @override
  State<CustomNumericKeypad> createState() => _CustomNumericKeypadState();
}

class _CustomNumericKeypadState extends State<CustomNumericKeypad> {
  late String _input;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue > 0) {
      _input = widget.initialValue == widget.initialValue.roundToDouble()
          ? widget.initialValue.toInt().toString()
          : widget.initialValue.toString();
    } else {
      _input = '';
    }
  }

  void _appendDigit(String digit) {
    setState(() {
      if (digit == '.' && _input.contains('.')) return;
      if (_input == '0' && digit != '.') {
        _input = digit;
      } else {
        _input += digit;
      }
    });
  }

  void _addQuickAmount(double amount) {
    final current = double.tryParse(_input) ?? 0;
    final updated = current + amount;
    setState(() {
      _input = updated.toInt().toString();
    });
  }

  void _backspace() {
    if (_input.isNotEmpty) {
      setState(() {
        _input = _input.substring(0, _input.length - 1);
      });
    }
  }

  void _clear() {
    setState(() {
      _input = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final numericVal = double.tryParse(_input) ?? 0;

    final textScaler = MediaQuery.textScalerOf(context);
    final chipHeight = textScaler.scale(42.0).clamp(42.0, 60.0);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('تصفير'),
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryGreen, width: 1.5),
                ),
                child: Text(
                  _input.isEmpty
                      ? '0'
                      : (widget.showQuickAmounts
                          ? AppFormatters.formatMoney(numericVal)
                          : _input),
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
              if (widget.showQuickAmounts) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: chipHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AppConstants.quickDenominations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final amount = AppConstants.quickDenominations[index];
                      return ActionChip(
                        backgroundColor: AppColors.cashGreenBg,
                        side: BorderSide.none,
                        label: Text(
                          '+${AppFormatters.formatMoney(amount)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        onPressed: () => _addQuickAmount(amount),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.1,
                children: [
                  for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                    _buildKeyButton(d, onTap: () => _appendDigit(d)),
                  _buildKeyButton(
                    widget.showQuickAmounts ? '000' : '.',
                    onTap: () =>
                        _appendDigit(widget.showQuickAmounts ? '000' : '.'),
                  ),
                  _buildKeyButton('0', onTap: () => _appendDigit('0')),
                  _buildKeyButton(
                    '⌫',
                    isAction: true,
                    onTap: _backspace,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => widget.onConfirmed(numericVal),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('تأكيد القيمة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyButton(String label,
      {required VoidCallback onTap, bool isAction = false}) {
    return Material(
      color: isAction ? AppColors.debtRedBg : AppColors.scaffoldBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isAction ? AppColors.debtRed : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
