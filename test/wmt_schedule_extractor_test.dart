import 'package:atc_schedule_manager/services/wmt_schedule_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const extractor = WmtScheduleExtractor();

  test('normalizes JSON-quoted WebView HTML', () {
    const captured = '"<html><body>ok</body></html>"';
    expect(extractor.normalizeCapturedHtml(captured), '<html><body>ok</body></html>');
  });

  test('extracts dated shifts from data-date rows', () {
    const html = '''
      <div data-date="2026-09-10"><span>1400</span></div>
      <div data-date="2026-09-11"><span>L1400</span></div>
      <div data-date="2026-09-12"><span>X</span></div>
      <div data-date="2026-09-13"><span>\$1400</span></div>
    ''';

    final shifts = extractor.extract(html);
    expect(shifts, hasLength(4));
    expect(shifts[0].date, DateTime(2026, 9, 10));
    expect(shifts[0].shift.raw, '1400');
    expect(shifts[1].shift.raw, 'L1400');
    expect(shifts[2].shift.isDayOff, isTrue);
    expect(shifts[3].shift.isOvertime, isTrue);
  });

  test('falls back to nearby date and shift text', () {
    const html = '''
      <table>
        <tr><td>9/14/2026</td><td>Q1400</td></tr>
        <tr><td>9/15/2026</td><td>Xtra1400</td></tr>
      </table>
    ''';

    final shifts = extractor.extract(html);
    expect(shifts, hasLength(2));
    expect(shifts[0].shift.raw, 'Q1400');
    expect(shifts[1].shift.raw, 'Xtra1400');
  });
}
