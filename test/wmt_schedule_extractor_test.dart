import 'package:atc_schedule_manager/services/wmt_schedule_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const extractor = WmtScheduleExtractor();

  test('normalizes JSON-quoted WebView HTML', () {
    const captured = '"<html><body>ok</body></html>"';
    expect(extractor.normalizeCapturedHtml(captured), '<html><body>ok</body></html>');
  });

  test('extracts real WMT pay period table including sick leave', () {
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
    expect(shifts, hasLength(14));
    expect(shifts.where((e) => e.shift.isDayOff).map((e) => e.date.day), [10, 17]);
    final sick = shifts.singleWhere((e) => e.date.day == 7);
    expect(sick.shift.isSickLeave, isTrue);
    expect(sick.shift.label, 'Sick Leave');
    expect(sick.shift.startMinutes, isNull);
    expect(shifts.any((e) => e.shift.raw == r'0500L$'), isTrue);
    expect(shifts.any((e) => e.shift.raw == 'C0600L'), isTrue);
    expect(shifts.any((e) => e.shift.raw == r'1300L$'), isTrue);
  });

  test('extracts annual leave and holiday leave from production WMT cells', () {
    const html = r'''
      <table>
        <tr>
          <td>Friday<br>10/09/2026<br>A<1415L></td>
          <td>Saturday<br>10/10/2026<br>A<1415L></td>
        </tr>
        <tr>
          <td>Sunday<br>10/11/2026<br>A<1300L></td>
          <td>Monday<br>10/12/2026<br>HL</td>
          <td>Tuesday<br>10/13/2026<br>A<0500L></td>
        </tr>
      </table>
    ''';

    final shifts = extractor.extract(html);
    expect(shifts, hasLength(5));
    expect(shifts.where((e) => e.shift.isAnnualLeave), hasLength(4));
    expect(shifts.singleWhere((e) => e.date.day == 12).shift.isHolidayLeave, isTrue);
    expect(shifts.singleWhere((e) => e.date.day == 9).shift.raw, 'A<1415L>');
  });

  test('extracts annual leave when WebView serializes angle brackets as entities', () {
    const html = r'''
      <table>
        <tr>
          <td>Friday<br>10/09/2026<br>A&lt;1415L&gt;</td>
          <td>Saturday<br>10/10/2026<br>A&lt;0500L&gt;</td>
        </tr>
      </table>
    ''';

    final shifts = extractor.extract(html);
    expect(shifts, hasLength(2));
    expect(shifts.every((e) => e.shift.isAnnualLeave), isTrue);
    expect(shifts.first.shift.raw, 'A<1415L>');
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
