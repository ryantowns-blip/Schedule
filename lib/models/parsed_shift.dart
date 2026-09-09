enum ShiftType { regular, overtime, dayOff }

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
  bool get isOvertime => shiftType == ShiftType.overtime;
  bool get hasXtraBefore => overtimeBeforeMinutes > 0;
  bool get hasXtraAfter => overtimeAfterMinutes > 0;
  int get durationMinutes =>
      baseDurationMinutes + overtimeBeforeMinutes + overtimeAfterMinutes;

  int? get effectiveStartMinutes {
    if (startMinutes == null) return null;
    var value = startMinutes!;
    if (flexType == FlexType.late) value += 15;
    value -= overtimeBeforeMinutes;
    return value;
  }

  int? get effectiveEndMinutes {
    if (startMinutes == null) return null;
    var regularStart = startMinutes!;
    if (flexType == FlexType.late) regularStart += 15;
    return regularStart + baseDurationMinutes + overtimeAfterMinutes;
  }

  String get label {
    if (isDayOff) return 'Day Off';
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
