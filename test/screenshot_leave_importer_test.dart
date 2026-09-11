import 'package:flutter_test/flutter_test.dart';
import 'package:atc_schedule_manager/services/screenshot_leave_importer.dart';

void main() {
  const importer = ScreenshotLeaveImporter();

  test('parses leave row with date type and approved status', () {
    final result = importer.parseRecognizedText('9/20/2026 Annual Approved');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.date, DateTime(2026, 9, 20));
    expect(result.$1.single.type, 'Annual');
    expect(result.$1.single.status, 'Approved');
  });

  test('parses leave when OCR splits date and status onto separate lines', () {
    final result = importer.parseRecognizedText('9/21/26 Annual\nApproved');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.date, DateTime(2026, 9, 21));
    expect(result.$1.single.type, 'Annual');
    expect(result.$1.single.status, 'Approved');
  });

  test('recognizes common leave abbreviations', () {
    final result = importer.parseRecognizedText('9/22/2026 AL Pending\n9/23/2026 HL Approved\n9/24/2026 SL Denied');
    expect(result.$1, hasLength(3));
    expect(result.$1[0].type, 'Annual');
    expect(result.$1[1].type, 'Holiday');
    expect(result.$1[2].type, 'Sick');
  });

  test('recognizes canceled and cancelled status spellings', () {
    final result = importer.parseRecognizedText('9/25/2026 Annual Canceled\n9/26/2026 Annual Cancelled');
    expect(result.$1, hasLength(2));
    expect(result.$1[0].status, 'Cancelled');
    expect(result.$1[1].status, 'Cancelled');
  });

  test('keeps incomplete leave-like text for review', () {
    final result = importer.parseRecognizedText('9/27/2026 Annual');
    expect(result.$1, isEmpty);
    expect(result.$2, contains('9/27/2026 Annual'));
  });

  test('parses real WMT OCR table-border artifacts', () {
    final result = importer.parseRecognizedText('''
11/15/2026l Annual Approved
|11/14/2026l Annual Approved
10/12/2026|| Holiday Approved
lo9/07/2026| Sick |Approved
08/30/2026l AnnualApproved
''');
    expect(result.$1, hasLength(5));
    expect(result.$1[0].date, DateTime(2026, 11, 15));
    expect(result.$1[1].date, DateTime(2026, 11, 14));
    expect(result.$1[2].type, 'Holiday');
    expect(result.$1[3].type, 'Sick');
    expect(result.$1[4].status, 'Approved');
    expect(result.$2, isEmpty);
  });

  test('validates calendar dates instead of accepting overflow dates', () {
    final result = importer.parseRecognizedText('02/31/2026 Annual Approved');
    expect(result.$1, isEmpty);
  });
}
