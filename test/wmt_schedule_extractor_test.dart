import 'package:atc_schedule_manager/services/wmt_schedule_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const extractor = WmtScheduleExtractor();

  test('normalizes JSON-quoted WebView HTML', () {
    const captured = '"<html><body>ok</body></html>"';
    expect(extractor.normalizeCapturedHtml(captured), '<html><body>ok</body></html>');
  });

  test('extracts real WMT pay period table without borrowing neighboring X values', () {
    const html = r'''
      <table>
        <tr>
          <td>Sunday<br>09/06/2026<br>0715Q</td>
          <td>Monday<br>09/07/2026<br>SL</td>
          <td>Tuesday<br>09/08/2026<br>0500L</td>
          <td>Wednesday<br>09/09/2026<br>0500L$</td>
          <td>Thursday<br>09/10/2026<br>X</td>
          <td>Friday<br>09/11/2026<br>1415L</td>
          <td>Saturday<br>09/12/2026<br>1300L</td>
        </tr>
        <tr>
          <td>Sunday<br>09/13/2026<br>0715Q</td>
          <td>Monday<br>09/14/2026<br>C0600L</td>
          <td>Tuesday<br>09/15/2026<br>0500L</td>
          <td>Wednesday<br>09/16/2026<br>1300L$</td>
          <td>Thursday<br>09/17/2026<br>X</td>
          <td>Friday<br>09/18/2026<br>1415L</td>
          <td>Saturday<br>09/19/2026<br>1300L</td>
        </tr>
      </table>
    ''';
    final shifts = extractor.extract(html);
    // SL has no numeric start time, so it is intentionally not treated as a
    // calendar shift yet. Every other dated WMT shift should be captured.
    expect(shifts, hasLength(13));
    expect(shifts.where((e) => e.shift.isDayOff).map((e) => e.date.day), [10, 17]);
    expect(shifts.first.shift.raw, '0715Q');
    expect(shifts.any((e) => e.shift.raw == r'0500L$'), isTrue);
    expect(shifts.any((e) => e.shift.raw == 'C0600L'), isTrue);
    expect(shifts.any((e) => e.shift.raw == r'1300L$'), isTrue);
  });

  test('extracts dated shifts from data-date rows', () {
    const html = '''
      <div data-date="2026-09-10"><span>1400</span></div>
      <div data-date="2026-09-11"><span>L1400</span></div>
      <div data-date="2026-09-12"><span>X</span></div>
    ''';
    final shifts = extractor.extract(html);
    expect(shifts, hasLength(3));
  });
}
