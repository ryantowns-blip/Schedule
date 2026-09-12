import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;

import '../models/upcoming_leave.dart';

class LeaveCalendarSyncResult {
  const LeaveCalendarSyncResult({required this.created, required this.skipped});

  final int created;
  final int skipped;
}

class LeaveCalendarService {
  LeaveCalendarService({dc.DeviceCalendar? calendar})
      : _calendar = calendar ?? dc.DeviceCalendar.instance;

  static const _calendarName = 'ATC Annual Leave';
  static const _descriptionPrefix = 'Web Schedule Manager • My Leave';

  final dc.DeviceCalendar _calendar;

  Future<LeaveCalendarSyncResult> syncApprovedLeave({
    required List<UpcomingLeaveEntry> entries,
    required String colorHex,
  }) async {
    final approved = entries.where((entry) => entry.isApproved).toList();
    if (approved.isEmpty) {
      return const LeaveCalendarSyncResult(created: 0, skipped: 0);
    }

    final permission = await _calendar.requestPermissions();
    if (permission != dc.CalendarPermissionStatus.granted) {
      throw StateError('Calendar access was not granted.');
    }

    final calendarId = await _ensureCalendar(colorHex);
    final dates = approved.map((entry) => entry.date).toList()..sort();
    final rangeStart = DateTime(dates.first.year, dates.first.month, dates.first.day);
    final last = dates.last;
    final rangeEnd = DateTime(last.year, last.month, last.day).add(const Duration(days: 2));

    // Check every visible calendar, not just the ATC Annual Leave companion
    // calendar. This catches Annual Leave that may already have been created by
    // the normal schedule sync, an older version of the app, or manually.
    final calendars = await _calendar.listCalendars();
    final calendarIds = calendars
        .where((calendar) => !calendar.hidden)
        .map((calendar) => calendar.id)
        .where((id) => id.isNotEmpty)
        .toList();
    if (!calendarIds.contains(calendarId)) calendarIds.add(calendarId);

    final existing = await _calendar.listEvents(
      rangeStart,
      rangeEnd,
      calendarIds: calendarIds,
    );

    var created = 0;
    var skipped = 0;
    for (final entry in approved) {
      final start = DateTime(entry.date.year, entry.date.month, entry.date.day);
      final duplicate = existing.any((event) {
        final sameDay = event.startDate.year == start.year &&
            event.startDate.month == start.month &&
            event.startDate.day == start.day;
        if (!sameDay) return false;

        // The title is the important conflict check. Do not require the event
        // to have been created by this app because users may already have an
        // Annual Leave event from another sync path or a manual entry.
        return event.title.trim().toLowerCase() == 'annual leave';
      });
      if (duplicate) {
        skipped++;
        continue;
      }

      await _calendar.createEvent(
        calendarId: calendarId,
        title: 'Annual Leave',
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
        isAllDay: true,
        description: '$_descriptionPrefix • Status: ${entry.status}',
        reminders: const [],
      );
      created++;
    }

    return LeaveCalendarSyncResult(created: created, skipped: skipped);
  }

  Future<String> _ensureCalendar(String colorHex) async {
    final calendars = await _calendar.listCalendars();
    for (final calendar in calendars) {
      if (!calendar.readOnly && calendar.name == _calendarName) {
        if (calendar.colorHex?.toUpperCase() != colorHex.toUpperCase()) {
          await _calendar.updateCalendar(calendar.id, colorHex: colorHex);
        }
        return calendar.id;
      }
    }
    return _calendar.createCalendar(name: _calendarName, colorHex: colorHex);
  }
}
