import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atc_schedule_manager/models/schedule_display_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('custom schedule and calendar colors persist', () async {
    final settings = ScheduleDisplaySettings.defaults.copyWith(
      regularColor: const Color(0xFF123456),
      overtimeColor: const Color(0xFF654321),
      annualLeaveColor: const Color(0xFFABCDEF),
      annualLeaveCalendarColor: const Color(0xFF0A7F42),
    );

    await settings.save();
    final loaded = await ScheduleDisplaySettings.load();

    expect(loaded.regularColor?.value, const Color(0xFF123456).value);
    expect(loaded.overtimeColor?.value, const Color(0xFF654321).value);
    expect(loaded.annualLeaveColor?.value, const Color(0xFFABCDEF).value);
    expect(
      loaded.annualLeaveCalendarColor?.value,
      const Color(0xFF0A7F42).value,
    );
  });

  test('reset defaults preserve separate annual leave colors', () {
    expect(
      ScheduleDisplaySettings.defaults.annualLeaveColor?.value,
      const Color(0xFFD8F3DC).value,
    );
    expect(
      ScheduleDisplaySettings.defaults.annualLeaveCalendarColor?.value,
      const Color(0xFFD8F3DC).value,
    );
  });
}
