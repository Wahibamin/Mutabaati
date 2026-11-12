import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/formatters.dart';

/// شارة عرض الرصيد المحاسبي («له» / «عليه» / «مصفر») بدقة بصرية عالية
class BalanceBadge extends StatelessWidget {
  final double balanceLah;
  final double balanceAlayh;
  final bool isCustomer; // true = زبون، false = مورد
  final String currency;

  const BalanceBadge({
    super.key,
    required this.balanceLah,
    required this.balanceAlayh,
    required this.isCustomer,
    this.currency = 'ر.ي',
  });

  @override
  Widget build(BuildContext context) {
    if (balanceAlayh <= 0.001 && balanceLah <= 0.001) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.cashGreenBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'مصفر (0)',
          style: TextStyle(
            color: AppColors.cashGreen,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    }

    if (isCustomer) {
      // في قسم الزبائن: «عليه» يعني دين لنا في ذمة الزبون (أحمر/برتقالي)، و«له» يعني رصيد دائن للزبون عندنا
      if (balanceAlayh > 0) {
        return _buildPill(
          label:
              'عليه: ${AppFormatters.formatMoney(balanceAlayh, currency: currency)}',
          bgColor: AppColors.debtRedBg,
          textColor: AppColors.debtRed,
        );
      } else {
        return _buildPill(
          label:
              'له: ${AppFormatters.formatMoney(balanceLah, currency: currency)}',
          bgColor: AppColors.transferBlueBg,
          textColor: AppColors.transferBlue,
        );
      }
    } else {
      // في قسم الموردين: «له» يعني مبلغ مستحق للمورد في ذمتنا (أحمر/برتقالي)، و«عليه» يعني مبلغ لنا في ذمة المورد
      if (balanceLah > 0) {
        return _buildPill(
          label:
              'له: ${AppFormatters.formatMoney(balanceLah, currency: currency)}',
          bgColor: AppColors.debtRedBg,
          textColor: AppColors.debtRed,
        );
      } else {
        return _buildPill(
          label:
              'عليه: ${AppFormatters.formatMoney(balanceAlayh, currency: currency)}',
          bgColor: AppColors.cashGreenBg,
          textColor: AppColors.cashGreen,
        );
      }
    }
  }

  Widget _buildPill({
    required String label,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
