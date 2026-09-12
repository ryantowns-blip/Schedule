import 'package:atc_schedule_manager/models/parsed_shift.dart';
import 'package:atc_schedule_manager/services/schedule_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ScheduleParser();

  test('parses regular 8 hour shift', () {
    final shift = parser.parse('1400');
    expect(shift.shiftType, ShiftType.regular);
    expect(shift.effectiveStartMinutes, 14 * 60);
    expect(shift.effectiveEndMinutes, 22 * 60);
  });

  test('parses day off', () {
    final shift = parser.parse('X');
    expect(shift.isDayOff, isTrue);
  });

  test('parses overtime shift', () {
    final shift = parser.parse(String.fromCharCode(36) + '1400');
    expect(shift.isOvertime, isTrue);
  });

  test('late flex uses time written in shift name', () {
    final shift = parser.parse('0615L');
    expect(shift.effectiveStartMinutes, 6 * 60 + 15);
  });

  test('q flex uses time written in shift name', () {
    final shift = parser.parse('0715Q');
    expect(shift.effectiveStartMinutes, 7 * 60 + 15);
  });

  test('xtra before adds two hours before', () {
    final shift = parser.parse('Xtra1400');
    expect(shift.effectiveStartMinutes, 12 * 60);
    expect(shift.effectiveEndMinutes, 22 * 60);
  });

  test('xtra after adds two hours after', () {
    final shift = parser.parse('1400Xtra');
    expect(shift.effectiveStartMinutes, 14 * 60);
    expect(shift.effectiveEndMinutes, 24 * 60);
  });

  test('calculates scheduled overtime hours from WMT codes', () {
    expect(parser.parse('1300L' + String.fromCharCode(36)).scheduledOvertimeMinutes, 8 * 60);
    expect(parser.parse('Xtra1400').scheduledOvertimeMinutes, 2 * 60);
    expect(parser.parse('1400Xtra').scheduledOvertimeMinutes, 2 * 60);
    expect(parser.parse('Xt1400ra').scheduledOvertimeMinutes, 2 * 60);
    expect(parser.parse('1300LS').scheduledOvertimeMinutes, 0);
  });

  test('overnight shifts can exceed midnight', () {
    final shift = parser.parse('2230');
    expect(shift.effectiveEndMinutes, greaterThan(1440));
  });
}
