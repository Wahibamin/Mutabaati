/// خدمة الحسابات والمعادلات الرياضية الصارمة لتطبيق «مقوتي» (المرحلة الرابعة - صفحة 6 و 7).
/// تضمن هذه الخدمة تطبيق قواعد «له» و«عليه» في سوق القات اليمني بنسبة 100% دون أي التباس.
class CalculateBalanceService {
  /// 1. المعادلة الرياضية لرصيد الزبون (Customer Account Balance - صفحة 6):
  /// صافي رصيد الزبون = إجمالي المبيعات الآجلة المتبقية (عليه) - إجمالي سدادات الزبون
  /// ملاحظة: المبيعات المرتجعة (status == 'RETURNED') تُستبعد تلقائيًا أو تُخصم من إجمالي المبيعات الآجلة.
  /// - إذا كان الناتج موجبًا (> 0) يُعرض في خانة «عليه» (مدين لنا).
  /// - إذا كان سالبًا (< 0) يُعرض بقيمته المطلقة في خانة «له» (دائن عندنا).
  /// - إذا كان (0) فالحساب «مصفر».
  static ({double balanceAlayh, double balanceLah}) computeCustomerBalance({
    required double totalActiveCreditRemaining,
    required double totalPaymentsReceived,
  }) {
    final net = totalActiveCreditRemaining - totalPaymentsReceived;
    if (net > 0.001) {
      return (balanceAlayh: net, balanceLah: 0.0);
    } else if (net < -0.001) {
      return (balanceAlayh: 0.0, balanceLah: net.abs());
    } else {
      return (balanceAlayh: 0.0, balanceLah: 0.0);
    }
  }

  /// 2. المعادلة الرياضية لرصيد المورد (Supplier Account Balance - صفحة 6):
  /// صافي رصيد المورد = إجمالي المشتريات الآجلة المتبقية (له) - إجمالي سداداتنا للمورد
  /// ملاحظة: في حال دفعنا أثناء الشراء مبلغًا أكبر من الإجمالي، يكون المتبقي سالبًا فيتحول لصالحنا («عليه»).
  /// - إذا كان الناتج موجبًا (> 0) يُعرض في خانة «له» (مستحق للمورد في ذمتنا).
  /// - إذا كان سالبًا (< 0) يُعرض بقيمته المطلقة في خانة «عليه» (مستحق لنا في ذمة المورد).
  /// - إذا كان (0) يظهر المورد في تقرير «مصفر».
  static ({double balanceLah, double balanceAlayh}) computeSupplierBalance({
    required double totalPurchasesRemaining,
    required double totalPaymentsPaid,
  }) {
    final net = totalPurchasesRemaining - totalPaymentsPaid;
    if (net > 0.001) {
      return (balanceLah: net, balanceAlayh: 0.0);
    } else if (net < -0.001) {
      return (balanceLah: 0.0, balanceAlayh: net.abs());
    } else {
      return (balanceLah: 0.0, balanceAlayh: 0.0);
    }
  }

  /// 3. صافي ربح التشغيل = المبيعات الصافية - تكلفة البضاعة المباعة
  /// - التالف - مصاريف العمل. شراء مخزون جديد ليس مصروفًا فوريًا.
  /// بينما تُعرض «المصاريف الشخصية» في سطر مستقل كمسحوبات حتى لا يظن البائع أن تجارته خاسرة بسبب مسحوباته المنزلية.
  static double computeDailyWorkNetProfit({
    required double netSalesAfterReturns,
    required double costOfGoodsSold,
    required double totalWastageCost,
    required double workExpenses,
  }) {
    return netSalesAfterReturns -
        (costOfGoodsSold + totalWastageCost + workExpenses);
  }
}
