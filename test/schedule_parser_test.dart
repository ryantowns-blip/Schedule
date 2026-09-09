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
    final shift = parser.parse(r'$1400');
    expect(shift.isOvertime, isTrue);
  });

  test('late flex starts 15 minutes late', () {
    final shift = parser.parse('L1400');
    expect(shift.effectiveStartMinutes, 14 * 60 + 15);
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

  test('overnight shifts can exceed midnight', () {
    final shift = parser.parse('2230');
    expect(shift.effectiveEndMinutes, greaterThan(1440));
  });
}
