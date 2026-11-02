import 'money.dart';

/// Monthly budgets are assigned PER CANTEEN (business decision, 2026-11-02):
/// each canteen has its own budget for each month. There is no single
/// organisation-wide amount.
///
/// Document: `monthlyFunds/<canteenId>_<yyyy-MM>` with fields
/// `canteenId`, `monthYear` (yyyy-MM), `fundAmount`, `lastUpdated`,
/// `updatedBy`, `monthLabel`.
///
/// Older documents with only a month id (`2026-11`) were the previous shared
/// fund. They are NOT a canteen budget and are never read as one.
String monthlyFundDocId(String canteenId, String monthKey) {
  final c = canteenId.trim();
  return '${c.isEmpty ? 'main' : c}_$monthKey';
}

/// A canteen's budget compared with what that canteen has spent. Whole paise,
/// like every other money calculation in the app.
class CanteenBudget {
  final String canteenId;
  final int allocatedPaise;
  final int spentPaise;

  const CanteenBudget({
    required this.canteenId,
    required this.allocatedPaise,
    required this.spentPaise,
  });

  factory CanteenBudget.of({
    required String canteenId,
    required double allocated,
    required double spent,
  }) =>
      CanteenBudget(
        canteenId: canteenId,
        allocatedPaise: toPaise(allocated),
        spentPaise: toPaise(spent),
      );

  int get availablePaise => allocatedPaise - spentPaise;
  double get allocated => allocatedPaise / 100;
  double get spent => spentPaise / 100;
  double get available => availablePaise / 100;

  /// No budget set (or zero) means there is nothing to compare against.
  bool get hasBudget => allocatedPaise > 0;
  bool get exceeded => hasBudget && availablePaise < 0;

  /// Share of the budget still unspent (negative when exceeded).
  double get fractionRemaining =>
      hasBudget ? availablePaise / allocatedPaise : 1.0;

  /// Warn when less than 15% is left (or the budget is exceeded).
  bool get needsAlert => hasBudget && fractionRemaining < kLowBudgetFraction;

  /// Whole percent of the budget already used, for display (never negative).
  int get percentUsed {
    if (!hasBudget) return 0;
    final used = (spentPaise * 100 / allocatedPaise).round();
    return used < 0 ? 0 : used;
  }
}

const double kLowBudgetFraction = 0.15;

/// Budgets that need attention, one per canteen that has a budget.
/// [allocatedByCanteen] and [spentByCanteen] are keyed by canteen id.
List<CanteenBudget> budgetsNeedingAlert({
  required Map<String, double> allocatedByCanteen,
  required Map<String, double> spentByCanteen,
}) {
  final out = <CanteenBudget>[];
  allocatedByCanteen.forEach((id, allocated) {
    final b = CanteenBudget.of(
        canteenId: id, allocated: allocated, spent: spentByCanteen[id] ?? 0);
    if (b.needsAlert) out.add(b);
  });
  // worst first (most overspent / least left)
  out.sort((a, b) => a.fractionRemaining.compareTo(b.fractionRemaining));
  return out;
}
