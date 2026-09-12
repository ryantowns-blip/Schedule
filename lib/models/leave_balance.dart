import 'package:shared_preferences/shared_preferences.dart';

enum LeaveKind { annual, sick }

class LeaveUsage {
  const LeaveUsage({
    required this.date,
    required this.kind,
    this.hours = 8,
    this.id,
  });

  final DateTime date;
  final LeaveKind kind;
  final double hours;
  final String? id;
}

class LeaveBalanceSettings {
  const LeaveBalanceSettings({
    required this.effectiveDate,
    required this.annualBalance,
    required this.sickBalance,
    required this.annualAccrualPerPayPeriod,
    required this.sickAccrualPerPayPeriod,
    this.annualCarryoverLimit = 240,
  });

  static const _effectiveDateKey = 'leave_balance_effective_date';
  static const _annualBalanceKey = 'leave_balance_annual_hours';
  static const _sickBalanceKey = 'leave_balance_sick_hours';
  static const _annualAccrualKey = 'leave_balance_annual_accrual';
  static const _sickAccrualKey = 'leave_balance_sick_accrual';
  static const _carryoverKey = 'leave_balance_carryover_limit';

  final DateTime effectiveDate;
  final double annualBalance;
  final double sickBalance;
  final double annualAccrualPerPayPeriod;
  final double sickAccrualPerPayPeriod;
  final double annualCarryoverLimit;

  static Future<LeaveBalanceSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final effective = DateTime.tryParse(prefs.getString(_effectiveDateKey) ?? '');
    if (effective == null || !prefs.containsKey(_annualBalanceKey)) return null;
    return LeaveBalanceSettings(
      effectiveDate: effective,
      annualBalance: prefs.getDouble(_annualBalanceKey) ?? 0,
      sickBalance: prefs.getDouble(_sickBalanceKey) ?? 0,
      annualAccrualPerPayPeriod: prefs.getDouble(_annualAccrualKey) ?? 8,
      sickAccrualPerPayPeriod: prefs.getDouble(_sickAccrualKey) ?? 4,
      annualCarryoverLimit: prefs.getDouble(_carryoverKey) ?? 240,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_effectiveDateKey, effectiveDate.toIso8601String());
    await prefs.setDouble(_annualBalanceKey, annualBalance);
    await prefs.setDouble(_sickBalanceKey, sickBalance);
    await prefs.setDouble(_annualAccrualKey, annualAccrualPerPayPeriod);
    await prefs.setDouble(_sickAccrualKey, sickAccrualPerPayPeriod);
    await prefs.setDouble(_carryoverKey, annualCarryoverLimit);
  }
}

class LeaveProjection {
  const LeaveProjection({
    required this.leaveYearEnd,
    required this.remainingPayPeriods,
    required this.annualAccrued,
    required this.sickAccrued,
    required this.annualPlanned,
    required this.sickPlanned,
    required this.currentAnnual,
    required this.currentSick,
    required this.projectedAnnual,
    required this.projectedSick,
    required this.useOrLose,
  });

  final DateTime leaveYearEnd;
  final int remainingPayPeriods;
  final double annualAccrued;
  final double sickAccrued;
  final double annualPlanned;
  final double sickPlanned;
  final double currentAnnual;
  final double currentSick;
  final double projectedAnnual;
  final double projectedSick;
  final double useOrLose;
}

class LeaveProjectionService {
  const LeaveProjectionService();

  static final DateTime _payPeriodAnchor = DateTime(2026, 1, 11);

  LeaveProjection calculate({
    required LeaveBalanceSettings settings,
    required List<LeaveUsage> usage,
  }) {
    final asOf = _dateOnly(settings.effectiveDate);
    final today = _dateOnly(DateTime.now());
    final leaveYearEnd = _leaveYearEndContaining(asOf);
    final accrualDates = _payPeriodEndDatesAfter(asOf, leaveYearEnd);
    final uniqueUsage = <String, LeaveUsage>{};
    for (final item in usage) {
      final date = _dateOnly(item.date);
      if (date.isBefore(asOf) || date.isAfter(leaveYearEnd)) continue;
      final key = item.id ?? '${date.year}-${date.month}-${date.day}-${item.kind.name}';
      uniqueUsage.putIfAbsent(key, () => item);
    }

    final annualPlanned = uniqueUsage.values
        .where((item) => item.kind == LeaveKind.annual)
        .fold<double>(0, (total, item) => total + item.hours);
    final sickPlanned = uniqueUsage.values
        .where((item) => item.kind == LeaveKind.sick)
        .fold<double>(0, (total, item) => total + item.hours);

    final accruedThroughToday =
        accrualDates.where((date) => !date.isAfter(today)).toList();
    var annualAccruedThroughToday =
        settings.annualAccrualPerPayPeriod * accruedThroughToday.length;
    if (settings.annualAccrualPerPayPeriod == 6 &&
        accruedThroughToday.contains(leaveYearEnd)) {
      annualAccruedThroughToday += 4;
    }
    final sickAccruedThroughToday =
        settings.sickAccrualPerPayPeriod * accruedThroughToday.length;
    final annualUsedThroughToday = uniqueUsage.values
        .where((item) =>
            item.kind == LeaveKind.annual && !item.date.isAfter(today))
        .fold<double>(0, (total, item) => total + item.hours);
    final sickUsedThroughToday = uniqueUsage.values
        .where((item) =>
            item.kind == LeaveKind.sick && !item.date.isAfter(today))
        .fold<double>(0, (total, item) => total + item.hours);

    var annualAccrued = settings.annualAccrualPerPayPeriod * accrualDates.length;
    if (settings.annualAccrualPerPayPeriod == 6 && accrualDates.contains(leaveYearEnd)) {
      annualAccrued += 4;
    }
    final sickAccrued = settings.sickAccrualPerPayPeriod * accrualDates.length;
    final projectedAnnual = settings.annualBalance + annualAccrued - annualPlanned;
    final projectedSick = settings.sickBalance + sickAccrued - sickPlanned;

    return LeaveProjection(
      leaveYearEnd: leaveYearEnd,
      remainingPayPeriods: accrualDates.length,
      annualAccrued: annualAccrued,
      sickAccrued: sickAccrued,
      annualPlanned: annualPlanned,
      sickPlanned: sickPlanned,
      currentAnnual: settings.annualBalance +
          annualAccruedThroughToday -
          annualUsedThroughToday,
      currentSick:
          settings.sickBalance + sickAccruedThroughToday - sickUsedThroughToday,
      projectedAnnual: projectedAnnual,
      projectedSick: projectedSick,
      useOrLose: (projectedAnnual - settings.annualCarryoverLimit)
          .clamp(0, double.infinity)
          .toDouble(),
    );
  }

  DateTime _leaveYearEndContaining(DateTime date) {
    final startThisYear = _firstPayPeriodStart(date.year);
    final nextStart = date.isBefore(startThisYear)
        ? startThisYear
        : _firstPayPeriodStart(date.year + 1);
    return nextStart.subtract(const Duration(days: 1));
  }

  DateTime _firstPayPeriodStart(int year) {
    final januaryFirst = DateTime(year, 1, 1);
    final difference = januaryFirst.difference(_payPeriodAnchor).inDays;
    final normalizedRemainder = ((difference % 14) + 14) % 14;
    final daysUntilStart = (14 - normalizedRemainder) % 14;
    return januaryFirst.add(Duration(days: daysUntilStart));
  }

  List<DateTime> _payPeriodEndDatesAfter(DateTime asOf, DateTime leaveYearEnd) {
    var start = _payPeriodAnchor;
    while (start.add(const Duration(days: 13)).isBefore(asOf) ||
        start.add(const Duration(days: 13)).isAtSameMomentAs(asOf)) {
      start = start.add(const Duration(days: 14));
    }
    while (start.subtract(const Duration(days: 14)).add(const Duration(days: 13)).isAfter(asOf)) {
      start = start.subtract(const Duration(days: 14));
    }
    final dates = <DateTime>[];
    var end = start.add(const Duration(days: 13));
    while (!end.isAfter(leaveYearEnd)) {
      dates.add(end);
      end = end.add(const Duration(days: 14));
    }
    return dates;
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
}
