import '../models/parsed_shift.dart';

class ScheduleParser {
  const ScheduleParser();

  ParsedShift parse(String input) {
    final raw = input.trim();
    final normalized = raw.replaceAll(' ', '').toUpperCase();

    if (normalized == 'X') {
      return ParsedShift(
        raw: raw,
        startMinutes: null,
        durationMinutes: 0,
        shiftType: ShiftType.dayOff,
        flexType: FlexType.none,
        isSupervisor: false,
        isCic: false,
        hasXtraBefore: false,
        hasXtraAfter: false,
      );
    }

    final isOvertime = normalized.contains(r'$');
    final isSupervisor = normalized.contains('S');
    final isCic = normalized.contains('C');
    final flexType = normalized.contains('L')
        ? FlexType.late
        : normalized.contains('Q')
            ? FlexType.quarter
            : FlexType.none;

    final lower = raw.toLowerCase().replaceAll(' ', '');
    final xtraBefore = lower.startsWith('xtra');
    final xtraAfter = lower.endsWith('xtra');
    final splitXtra = lower.startsWith('xt') && lower.endsWith('ra') && !xtraBefore;

    final timeMatch = RegExp(r'(\d{3,4})').firstMatch(normalized);
    if (timeMatch == null) {
      throw FormatException('No shift start time found in "$raw"');
    }

    final digits = timeMatch.group(1)!;
    final padded = digits.padLeft(4, '0');
    final hour = int.parse(padded.substring(0, 2));
    final minute = int.parse(padded.substring(2, 4));
    if (hour > 23 || minute > 59) {
      throw FormatException('Invalid time in "$raw"');
    }

    var startMinutes = hour * 60 + minute;
    var durationMinutes = 8 * 60;

    if (splitXtra) {
      startMinutes -= 60;
      durationMinutes = 10 * 60;
    } else if (xtraBefore && xtraAfter) {
      durationMinutes = 10 * 60;
    } else if (xtraBefore || xtraAfter) {
      durationMinutes = 10 * 60;
    }

    return ParsedShift(
      raw: raw,
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
      shiftType: isOvertime ? ShiftType.overtime : ShiftType.regular,
      flexType: flexType,
      isSupervisor: isSupervisor,
      isCic: isCic,
      hasXtraBefore: xtraBefore || splitXtra,
      hasXtraAfter: xtraAfter || splitXtra,
    );
  }

  List<ParsedShift> parseLines(String text) {
    final shifts = <ParsedShift>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      shifts.add(parse(trimmed));
    }
    return shifts;
  }
}
