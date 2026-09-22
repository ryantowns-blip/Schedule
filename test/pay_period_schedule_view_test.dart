import 'package:atc_schedule_manager/screens/pay_period_schedule_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<PayPeriodSchedule> savedPeriods() => [
        PayPeriodSchedule(
          start: DateTime(2026, 9, 6),
          end: DateTime(2026, 9, 19),
          shifts: const [],
        ),
        PayPeriodSchedule(
          start: DateTime(2026, 9, 20),
          end: DateTime(2026, 10, 3),
          shifts: const [],
        ),
        PayPeriodSchedule(
          start: DateTime(2026, 10, 4),
          end: DateTime(2026, 10, 17),
          shifts: const [],
        ),
      ];

  test('selects the saved pay period containing today', () {
    final periods = includeCurrentPayPeriod(
      savedPeriods(),
      DateTime(2026, 9, 22),
    );

    expect(periods, hasLength(3));
    expect(defaultPayPeriodIndex(periods, DateTime(2026, 9, 22)), 1);
  });

  test('adds and selects the current period when saved data is older', () {
    final periods = includeCurrentPayPeriod(
      savedPeriods(),
      DateTime(2026, 10, 21),
    );

    expect(periods, hasLength(4));
    expect(periods.last.start, DateTime(2026, 10, 18));
    expect(periods.last.end, DateTime(2026, 10, 31));
    expect(periods.last.shifts, isEmpty);
    expect(defaultPayPeriodIndex(periods, DateTime(2026, 10, 21)), 3);
  });

  test('keeps archived periods available', () {
    final periods = includeCurrentPayPeriod(
      savedPeriods(),
      DateTime(2026, 10, 21),
    );

    expect(periods.first.label, '9/6–9/19');
    expect(periods[1].label, '9/20–10/3');
    expect(periods[2].label, '10/4–10/17');
  });
}
