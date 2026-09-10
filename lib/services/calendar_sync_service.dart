import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;

import 'wmt_schedule_extractor.dart';

class CalendarSyncResult {
  const CalendarSyncResult({required this.created, required this.skipped});

  final int created;
  final int skipped;
}

class CalendarSyncService {
  CalendarSyncService({dc.DeviceCalendar? calendar})
      : _calendar = calendar ?? dc.DeviceCalendar.instance;

  final dc.DeviceCalendar _calendar;

  Future<List<dc.Calendar>> requestWritableCalendars() async {
    final status = await _calendar.requestPermissions();
    if (status != dc.CalendarPermissionStatus.granted) {
      throw StateError('Calendar access was not granted.');
    }

    final calendars = await _calendar.listCalendars();
    return calendars
        .where((calendar) => !calendar.readOnly && !calendar.hidden)
        .toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  List<DatedShift> workingShifts(List<DatedShift> shifts) =>
      shifts.where((entry) => !entry.shift.isNonWorking && entry.shift.effectiveStartMinutes != null).toList();

  Future<CalendarSyncResult> createWorkingShiftEvents({
    required String calendarId,
    required List<DatedShift> shifts,
  }) async {
    var created = 0;
    var skipped = 0;

    for (final entry in shifts) {
      final shift = entry.shift;
      final startMinutes = shift.effectiveStartMinutes;
      if (shift.isNonWorking || startMinutes == null) {
        skipped++;
        continue;
      }

      final start = DateTime(entry.date.year, entry.date.month, entry.date.day)
          .add(Duration(minutes: startMinutes));
      final end = start.add(Duration(minutes: shift.durationMinutes));

      await _calendar.createEvent(
        calendarId: calendarId,
        title: _titleFor(entry),
        startDate: start,
        endDate: end,
        description: 'ATC Schedule Manager • WMT code: ${shift.raw}',
        reminders: const [
          Duration(days: 1),
          Duration(hours: 2),
          Duration(minutes: 30),
        ],
      );
      created++;
    }

    return CalendarSyncResult(created: created, skipped: skipped);
  }

  String _titleFor(DatedShift entry) {
    final shift = entry.shift;
    if (shift.isOvertime) return r'$ OT';
    if (shift.isSupervisor) return 'ATC Supervisor';
    if (shift.isCic) return 'ATC CIC';
    return 'ATC Shift';
  }
}
