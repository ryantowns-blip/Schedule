import 'package:flutter_test/flutter_test.dart';
import 'package:atc_schedule_manager/services/wmt_leave_extractor.dart';

void main() {
  test('extracts only future annual leave and preserves status', () {
    const html = '''
      <table>
        <tr><th>Date</th><th>Type</th><th>Final Status</th><th>Requested</th></tr>
        <tr><td>09/09/2026</td><td>Annual</td><td>Approved</td><td>8/1/2026 9:00 AM</td></tr>
        <tr><td>09/12/2026</td><td>Sick</td><td>Approved</td><td>9/10/2026 7:00 AM</td></tr>
        <tr><td>10/11/2026</td><td>Annual</td><td>Approved</td><td>12/3/2025 9:19:24 AM</td></tr>
        <tr><td>11/14/2026</td><td>Annual</td><td>Pending</td><td>12/4/2025 9:37:53 AM</td></tr>
        <tr><td>11/15/2026</td><td>Annual</td><td>Canceled</td><td>12/4/2025 9:37:53 AM</td></tr>
      </table>
    ''';

    final entries = const WmtLeaveExtractor().extract(
      html,
      now: DateTime(2026, 9, 10),
    );

    expect(entries.length, 3);
    expect(entries[0].date, DateTime(2026, 10, 11));
    expect(entries[0].status, 'Approved');
    expect(entries[0].isApproved, isTrue);
    expect(entries[1].status, 'Pending');
    expect(entries[1].isApproved, isFalse);
    expect(entries[2].status, 'Canceled');
  });
}
