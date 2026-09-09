enum ShiftType { regular, overtime, dayOff }

enum FlexType { none, late, quarter }

class ParsedShift {
  const ParsedShift({
    required this.raw,
    required this.startMinutes,
    required this.durationMinutes,
    required this.shiftType,
    required this.flexType,
    required this.isSupervisor,
    required this.isCic,
    required this.hasXtraBefore,
    required this.hasXtraAfter,
  });

  final String raw;
  final int? startMinutes;
  final int durationMinutes;
  final ShiftType shiftType;
  final FlexType flexType;
  final bool isSupervisor;
  final bool isCic;
  final bool hasXtraBefore;
  final bool hasXtraAfter;

  bool get isDayOff => shiftType == ShiftType.dayOff;
  bool get isOvertime => shiftType == ShiftType.overtime;

  int? get effectiveStartMinutes {
    if (startMinutes == null) return null;
    var value = startMinutes!;
    if (flexType == FlexType.late) value += 15;
    if (hasXtraBefore) value -= 120;
    return value;
  }

  int? get effectiveEndMinutes {
    final start = effectiveStartMinutes;
    if (start == null) return null;
    return start + durationMinutes;
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
