enum ShiftType { regular, overtime, dayOff, sickLeave, annualLeave, holidayLeave }

enum FlexType { none, late, quarter }

class ParsedShift {
  const ParsedShift({
    required this.raw,
    required this.startMinutes,
    required this.baseDurationMinutes,
    required this.shiftType,
    required this.flexType,
    required this.isSupervisor,
    required this.isCic,
    required this.overtimeBeforeMinutes,
    required this.overtimeAfterMinutes,
  });

  final String raw;
  final int? startMinutes;
  final int baseDurationMinutes;
  final ShiftType shiftType;
  final FlexType flexType;
  final bool isSupervisor;
  final bool isCic;
  final int overtimeBeforeMinutes;
  final int overtimeAfterMinutes;

  bool get isDayOff => shiftType == ShiftType.dayOff;
  bool get isSickLeave => shiftType == ShiftType.sickLeave;
  bool get isAnnualLeave => shiftType == ShiftType.annualLeave;
  bool get isHolidayLeave => shiftType == ShiftType.holidayLeave;
  bool get isNonWorking => isDayOff || isSickLeave || isAnnualLeave || isHolidayLeave;
  bool get isOvertime => shiftType == ShiftType.overtime;
  bool get hasXtraBefore => overtimeBeforeMinutes > 0;
  bool get hasXtraAfter => overtimeAfterMinutes > 0;
  int get durationMinutes =>
      baseDurationMinutes + overtimeBeforeMinutes + overtimeAfterMinutes;

  /// The time printed in the WMT shift name is the authoritative shift start.
  /// L and Q remain labels/modifiers only; they do not move the calendar start.
  /// Xtra before still extends overtime before the named shift time.
  int? get effectiveStartMinutes {
    if (startMinutes == null) return null;
    return startMinutes! - overtimeBeforeMinutes;
  }

  int? get effectiveEndMinutes {
    if (startMinutes == null) return null;
    return startMinutes! + baseDurationMinutes + overtimeAfterMinutes;
  }

  String get label {
    if (isDayOff) return 'Day Off';
    if (isSickLeave) return 'Sick Leave';
    if (isAnnualLeave) return 'Annual Leave';
    if (isHolidayLeave) return 'Holiday Leave';
    final parts = <String>[];
    if (isOvertime) parts.add(r'$ OT');
    if (isSupervisor) parts.add('Supervisor');
    if (isCic) parts.add('CIC');
    if (flexType == FlexType.late) parts.add('Late Flex');
    if (flexType == FlexType.quarter) parts.add('Q Flex');
    if (hasXtraBefore || hasXtraAfter) parts.add('Xtra');
    return parts.isEmpty ? 'Shift' : parts.join(' • ');
  }
}
