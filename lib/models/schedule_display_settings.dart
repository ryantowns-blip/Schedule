import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleDisplaySettings {
  const ScheduleDisplaySettings({
    required this.regularColor,
    required this.overtimeColor,
    required this.offColor,
    required this.annualLeaveColor,
    required this.sickColor,
    required this.holidayColor,
    required this.annualLeaveCalendarColor,
  });

  final Color? regularColor;
  final Color? overtimeColor;
  final Color? offColor;
  final Color? annualLeaveColor;
  final Color? sickColor;
  final Color? holidayColor;
  final Color? annualLeaveCalendarColor;

  static const defaults = ScheduleDisplaySettings(
    regularColor: null,
    overtimeColor: Color(0xFFFFDAD6),
    offColor: Color(0xFFE2E2E6),
    annualLeaveColor: Color(0xFFD8F3DC),
    sickColor: Color(0xFFE8DEF8),
    holidayColor: Color(0xFFE2E2E6),
    annualLeaveCalendarColor: Color(0xFFD8F3DC),
  );

  static const _regularKey = 'display_regular_color';
  static const _overtimeKey = 'display_overtime_color';
  static const _offKey = 'display_off_color';
  static const _annualLeaveKey = 'display_annual_leave_color';
  static const _sickKey = 'display_sick_color';
  static const _holidayKey = 'display_holiday_color';
  static const _annualLeaveCalendarKey = 'calendar_annual_leave_color';
  static const _none = -1;

  static Future<ScheduleDisplaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    Color? read(String key, Color? fallback) {
      final stored = prefs.getInt(key);
      if (stored == null) return fallback;
      if (stored == _none) return null;
      return Color(stored);
    }

    final annualDisplay = read(_annualLeaveKey, defaults.annualLeaveColor);
    return ScheduleDisplaySettings(
      regularColor: read(_regularKey, defaults.regularColor),
      overtimeColor: read(_overtimeKey, defaults.overtimeColor),
      offColor: read(_offKey, defaults.offColor),
      annualLeaveColor: annualDisplay,
      sickColor: read(_sickKey, defaults.sickColor),
      holidayColor: read(_holidayKey, defaults.holidayColor),
      annualLeaveCalendarColor:
          read(_annualLeaveCalendarKey, annualDisplay ?? defaults.annualLeaveCalendarColor),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_regularKey, regularColor?.value ?? _none);
    await prefs.setInt(_overtimeKey, overtimeColor?.value ?? _none);
    await prefs.setInt(_offKey, offColor?.value ?? _none);
    await prefs.setInt(_annualLeaveKey, annualLeaveColor?.value ?? _none);
    await prefs.setInt(_sickKey, sickColor?.value ?? _none);
    await prefs.setInt(_holidayKey, holidayColor?.value ?? _none);
    await prefs.setInt(
      _annualLeaveCalendarKey,
      annualLeaveCalendarColor?.value ?? _none,
    );
  }

  ScheduleDisplaySettings copyWith({
    Color? regularColor,
    bool clearRegular = false,
    Color? overtimeColor,
    bool clearOvertime = false,
    Color? offColor,
    bool clearOff = false,
    Color? annualLeaveColor,
    bool clearAnnualLeave = false,
    Color? sickColor,
    bool clearSick = false,
    Color? holidayColor,
    bool clearHoliday = false,
    Color? annualLeaveCalendarColor,
    bool clearAnnualLeaveCalendar = false,
  }) {
    return ScheduleDisplaySettings(
      regularColor: clearRegular ? null : regularColor ?? this.regularColor,
      overtimeColor: clearOvertime ? null : overtimeColor ?? this.overtimeColor,
      offColor: clearOff ? null : offColor ?? this.offColor,
      annualLeaveColor:
          clearAnnualLeave ? null : annualLeaveColor ?? this.annualLeaveColor,
      sickColor: clearSick ? null : sickColor ?? this.sickColor,
      holidayColor: clearHoliday ? null : holidayColor ?? this.holidayColor,
      annualLeaveCalendarColor: clearAnnualLeaveCalendar
          ? null
          : annualLeaveCalendarColor ?? this.annualLeaveCalendarColor,
    );
  }
}
