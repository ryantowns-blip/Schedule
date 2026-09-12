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

  test('pairs a WMT date/type column with a later status column', () {
    final result = importer.parseRecognizedText('''
11/15/2026| Annual
10/13/2026| Annual
10/12/2026|| Holiday
08/19/2026| Sick
Approved
Pending
Approved
Denied
''');
    expect(result.$1, hasLength(4));
    expect(result.$1.map((entry) => entry.status), ['Approved', 'Pending', 'Approved', 'Denied']);
    expect(result.$1[2].type, 'Holiday');
    expect(result.$1[3].type, 'Sick');
    expect(result.$2, isEmpty);
  });

  test('attaches a type split onto its own OCR line', () {
    final result = importer.parseRecognizedText('08/10/2026|\nSick\nApproved');
    expect(result.$1, hasLength(1));
    expect(result.$1.single.type, 'Sick');
    expect(result.$1.single.status, 'Approved');
    expect(result.$2, isEmpty);
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

  test('upcoming filter keeps today and future dates only', () {
    final parsed = importer.parseRecognizedText('''
9/9/2026 Annual Approved
9/10/2026 Sick Approved
9/11/2026 Holiday Pending
9/12/2026 Annual
Approved
9/8/2026 Annual
''');
    final filtered = importer.filterUpcoming(
      ScreenshotLeaveImportResult(
        entries: parsed.$1,
        unrecognizedLines: parsed.$2,
        rawText: '',
      ),
      now: DateTime(2026, 9, 10, 18, 30),
    );
    expect(filtered.entries.map((entry) => entry.date), [
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 11),
      DateTime(2026, 9, 12),
    ]);
    expect(filtered.unrecognizedLines, isEmpty);
  });
}
