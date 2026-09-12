import 'package:flutter_test/flutter_test.dart';
import 'package:atc_schedule_manager/models/parsed_shift.dart';
import 'package:atc_schedule_manager/services/screenshot_schedule_importer.dart';

void main() {
  const importer = ScreenshotScheduleImporter();

  test('parses date and shift on same OCR line', () {
    final result = importer.parseRecognizedText('9/11/2026 0500L');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.date, DateTime(2026, 9, 11));
    expect(result.$1.single.shift.raw.toUpperCase(), '0500L');
    expect(result.$1.single.shift.flexType, FlexType.late);
  });

  test('parses shift when OCR places date and shift on separate lines', () {
    final result = importer.parseRecognizedText('9/12/26\nQ0600');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.date, DateTime(2026, 9, 12));
    expect(result.$1.single.shift.raw.toUpperCase(), 'Q0600');
    expect(result.$1.single.shift.flexType, FlexType.quarter);
  });

  test('repairs letter O inside numeric shift', () {
    final result = importer.parseRecognizedText('9/13/2026 O5OO');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.shift.startMinutes, 5 * 60);
  });

  test('repairs OCR accented suffix as overtime dollar sign', () {
    final result = importer.parseRecognizedText('9/16/2026 1300LŠ');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.shift.raw.toUpperCase(), r'1300L

  test('recognizes annual leave when OCR uses square brackets', () {
    final result = importer.parseRecognizedText('9/14/2026 A[0500]');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.shift.shiftType, ShiftType.annualLeave);
    expect(result.$1.single.shift.startMinutes, 5 * 60);
  });

  test('recognizes overtime and xtra forms', () {
    final result = importer.parseRecognizedText(
      '9/15/2026 \$1400\n9/16/2026 Xtra1400\n9/17/2026 Xt1400ra',
    );
    expect(result.$1, hasLength(3));
    expect(result.$1[0].shift.shiftType, ShiftType.overtime);
    expect(result.$1[1].shift.overtimeBeforeMinutes, 120);
    expect(result.$1[2].shift.overtimeBeforeMinutes, 60);
    expect(result.$1[2].shift.overtimeAfterMinutes, 60);
  });

  test('parses the real 9/6-9/19 WMT pay-period cell values', () {
    final result = importer.parseRecognizedText(
      '09/06/2026 0715Q\n'
      '09/07/2026 SL\n'
      '09/08/2026 0500L\n'
      '09/09/2026 0500L\$\n'
      '09/10/2026 X\n'
      '09/11/2026 1415L\n'
      '09/12/2026 1300L\n'
      '09/13/2026 0715Q\n'
      '09/14/2026 C0600L\n'
      '09/15/2026 0500L\n'
      '09/16/2026 1300L\$\n'
      '09/17/2026 X\n'
      '09/18/2026 1415L\n'
      '09/19/2026 1300L',
    );

    expect(result.$1, hasLength(14));
    expect(
      result.$1.map((entry) => entry.shift.raw.toUpperCase()).toList(),
      [
        '0715Q',
        'SL',
        '0500L',
        '0500L\$',
        'X',
        '1415L',
        '1300L',
        '0715Q',
        'C0600L',
        '0500L',
        '1300L\$',
        'X',
        '1415L',
        '1300L',
      ],
    );
  });

  test('leaves schedule-like invalid text for manual review', () {
    final result = importer.parseRecognizedText('9/18/2026\n2960');
    expect(result.$1, isEmpty);
    expect(result.$2, contains('2960'));
  });
}
);
    expect(result.$1.single.shift.shiftType, ShiftType.overtime);
    expect(result.$1.single.shift.isSupervisor, isFalse);
  });

  test('recognizes annual leave when OCR uses square brackets', () {
    final result = importer.parseRecognizedText('9/14/2026 A[0500]');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.shift.shiftType, ShiftType.annualLeave);
    expect(result.$1.single.shift.startMinutes, 5 * 60);
  });

  test('recognizes overtime and xtra forms', () {
    final result = importer.parseRecognizedText(
      '9/15/2026 \$1400\n9/16/2026 Xtra1400\n9/17/2026 Xt1400ra',
    );
    expect(result.$1, hasLength(3));
    expect(result.$1[0].shift.shiftType, ShiftType.overtime);
    expect(result.$1[1].shift.overtimeBeforeMinutes, 120);
    expect(result.$1[2].shift.overtimeBeforeMinutes, 60);
    expect(result.$1[2].shift.overtimeAfterMinutes, 60);
  });

  test('parses the real 9/6-9/19 WMT pay-period cell values', () {
    final result = importer.parseRecognizedText(
      '09/06/2026 0715Q\n'
      '09/07/2026 SL\n'
      '09/08/2026 0500L\n'
      '09/09/2026 0500L\$\n'
      '09/10/2026 X\n'
      '09/11/2026 1415L\n'
      '09/12/2026 1300L\n'
      '09/13/2026 0715Q\n'
      '09/14/2026 C0600L\n'
      '09/15/2026 0500L\n'
      '09/16/2026 1300L\$\n'
      '09/17/2026 X\n'
      '09/18/2026 1415L\n'
      '09/19/2026 1300L',
    );

    expect(result.$1, hasLength(14));
    expect(
      result.$1.map((entry) => entry.shift.raw.toUpperCase()).toList(),
      [
        '0715Q',
        'SL',
        '0500L',
        '0500L\$',
        'X',
        '1415L',
        '1300L',
        '0715Q',
        'C0600L',
        '0500L',
        '1300L\$',
        'X',
        '1415L',
        '1300L',
      ],
    );
  });

  test('leaves schedule-like invalid text for manual review', () {
    final result = importer.parseRecognizedText('9/18/2026\n2960');
    expect(result.$1, isEmpty);
    expect(result.$2, contains('2960'));
  });
}
