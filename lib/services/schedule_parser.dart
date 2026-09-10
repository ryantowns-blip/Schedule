import '../models/parsed_shift.dart';

class ScheduleParser {
  const ScheduleParser();

  ParsedShift parse(String input) {
    final raw = input.trim();
    final normalized = raw.replaceAll(' ', '').toUpperCase();

    ParsedShift nonWorking(ShiftType type) => ParsedShift(
          raw: raw,
          startMinutes: null,
          baseDurationMinutes: 0,
          shiftType: type,
          flexType: FlexType.none,
          isSupervisor: false,
          isCic: false,
          overtimeBeforeMinutes: 0,
          overtimeAfterMinutes: 0,
        );

    if (normalized == 'X') return nonWorking(ShiftType.dayOff);
    if (normalized == 'SL') return nonWorking(ShiftType.sickLeave);
    if (normalized == 'HL') return nonWorking(ShiftType.holidayLeave);
    final annualMatch = RegExp(r'^A<(\d{3,4})>$').firstMatch(normalized);
    if (annualMatch != null) {
      final digits = annualMatch.group(1)!.padLeft(4, '0');
      final hour = int.parse(digits.substring(0, 2));
      final minute = int.parse(digits.substring(2, 4));
      if (hour > 23 || minute > 59) {
        throw FormatException('Invalid annual-leave start time in "$raw"');
      }
      return ParsedShift(
        raw: raw,
        startMinutes: hour * 60 + minute,
        baseDurationMinutes: 8 * 60,
        shiftType: ShiftType.annualLeave,
        flexType: FlexType.none,
        isSupervisor: false,
        isCic: false,
        overtimeBeforeMinutes: 0,
        overtimeAfterMinutes: 0,
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

    final startMinutes = hour * 60 + minute;
    var overtimeBeforeMinutes = 0;
    var overtimeAfterMinutes = 0;

    if (splitXtra) {
      overtimeBeforeMinutes = 60;
      overtimeAfterMinutes = 60;
    } else {
      if (xtraBefore) overtimeBeforeMinutes = 120;
      if (xtraAfter) overtimeAfterMinutes = 120;
    }

    return ParsedShift(
      raw: raw,
      startMinutes: startMinutes,
      baseDurationMinutes: 8 * 60,
      shiftType: isOvertime ? ShiftType.overtime : ShiftType.regular,
      flexType: flexType,
      isSupervisor: isSupervisor,
      isCic: isCic,
      overtimeBeforeMinutes: overtimeBeforeMinutes,
      overtimeAfterMinutes: overtimeAfterMinutes,
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
