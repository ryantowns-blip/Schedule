import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;

import 'wmt_schedule_extractor.dart';

enum DuplicateHandling { updateExisting, createNew }

class CalendarSyncResult {
  const CalendarSyncResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.duplicates,
    required this.annualLeaveCreated,
    required this.annualLeaveUpdated,
    required this.holidayLeaveCreated,
    required this.holidayLeaveUpdated,
  });

  final int created;
  final int updated;
  final int skipped;
  final int duplicates;
  final int annualLeaveCreated;
  final int annualLeaveUpdated;
  final int holidayLeaveCreated;
  final int holidayLeaveUpdated;
}

class CalendarSyncService {
  CalendarSyncService({dc.DeviceCalendar? calendar})
      : _calendar = calendar ?? dc.DeviceCalendar.instance;

  static const _descriptionPrefix = 'ATC Schedule Manager';
  static const _annualLeaveCalendarName = 'ATC Annual Leave';

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

  List<DatedShift> workingShifts(List<DatedShift> shifts) => shifts
      .where((entry) =>
          !entry.shift.isNonWorking &&
          entry.shift.effectiveStartMinutes != null)
      .toList();

  List<DatedShift> annualLeaveShifts(List<DatedShift> shifts) => shifts
      .where((entry) =>
          entry.shift.isAnnualLeave &&
          entry.shift.effectiveStartMinutes != null)
      .toList();

  List<DatedShift> holidayLeaveShifts(List<DatedShift> shifts) => shifts
      .where((entry) => entry.shift.shiftType == ShiftType.holidayLeave)
      .toList();

  Future<int> countExistingMatches({
    required String calendarId,
    required List<DatedShift> shifts,
  }) async {
    final working = workingShifts(shifts);
    final holiday = holidayLeaveShifts(shifts);
    if (working.isEmpty && holiday.isEmpty) return 0;
    final existing = await _existingAtcEvents(
      calendarId,
      [...working, ...holiday],
    );
    var count = 0;
    for (final entry in working) {
      if (_findExistingFor(entry, existing) != null) count++;
    }
    for (final entry in holiday) {
      if (_findExistingOnDateByTitle(entry, existing, 'Holiday Leave') != null) {
        count++;
      }
    }
    return count;
  }

  Future<CalendarSyncResult> syncShiftEvents({
    required String calendarId,
    required List<DatedShift> shifts,
    required DuplicateHandling duplicateHandling,
    required List<Duration> reminders,
    required String annualLeaveColorHex,
  }) async {
    var created = 0;
    var updated = 0;
    var skipped = 0;
    var duplicates = 0;
    var annualLeaveCreated = 0;
    var annualLeaveUpdated = 0;
    var holidayLeaveCreated = 0;
    var holidayLeaveUpdated = 0;

    final working = workingShifts(shifts);
    final holiday = holidayLeaveShifts(shifts);
    final existing = await _existingAtcEvents(
      calendarId,
      [...working, ...holiday],
    );

    for (final entry in shifts) {
      final shift = entry.shift;
      final startMinutes = shift.effectiveStartMinutes;
      if (shift.isAnnualLeave || shift.shiftType == ShiftType.holidayLeave) {
        continue;
      }
      if (shift.isNonWorking || startMinutes == null) {
        skipped++;
        continue;
      }

      final start = _startFor(entry);
      final end = start.add(Duration(minutes: shift.durationMinutes));
      final description = '$_descriptionPrefix • WMT code: ${shift.raw}';
      final match = _findExistingFor(entry, existing);

      if (match != null) {
        duplicates++;
        if (duplicateHandling == DuplicateHandling.updateExisting) {
          await _calendar.updateEvent(
            eventId: match.instanceId,
            title: shift.raw,
            startDate: start,
            endDate: end,
            description: dc.Patch.set(description),
            reminders: dc.Patch.set(reminders),
          );
          updated++;
          continue;
        }
      }

      await _calendar.createEvent(
        calendarId: calendarId,
        title: shift.raw,
        startDate: start,
        endDate: end,
        description: description,
        reminders: reminders,
      );
      created++;
    }

    for (final entry in holiday) {
      final start = DateTime(entry.date.year, entry.date.month, entry.date.day);
      final end = start.add(const Duration(days: 1));
      final description = '$_descriptionPrefix • Holiday Leave • WMT code: ${entry.shift.raw}';
      final match = _findExistingOnDateByTitle(entry, existing, 'Holiday Leave');

      if (match != null) {
        duplicates++;
        if (duplicateHandling == DuplicateHandling.updateExisting) {
          await _calendar.updateEvent(
            eventId: match.instanceId,
            title: 'Holiday Leave',
            startDate: start,
            endDate: end,
            isAllDay: true,
            description: dc.Patch.set(description),
            reminders: dc.Patch.set(reminders),
          );
          holidayLeaveUpdated++;
          continue;
        }
      }

      await _calendar.createEvent(
        calendarId: calendarId,
        title: 'Holiday Leave',
        startDate: start,
        endDate: end,
        isAllDay: true,
        description: description,
        reminders: reminders,
      );
      holidayLeaveCreated++;
    }

    final leave = annualLeaveShifts(shifts);
    if (leave.isNotEmpty) {
      final leaveCalendarId = await _ensureAnnualLeaveCalendar(annualLeaveColorHex);
      final existingLeave = await _existingAtcEvents(leaveCalendarId, leave);
      for (final entry in leave) {
        final shift = entry.shift;
        final start = _startFor(entry);
        final end = start.add(Duration(minutes: shift.durationMinutes));
        final description = '$_descriptionPrefix • Annual Leave • WMT code: ${shift.raw}';
        final match = _findExistingFor(entry, existingLeave);

        if (match != null && duplicateHandling == DuplicateHandling.updateExisting) {
          await _calendar.updateEvent(
            eventId: match.instanceId,
            title: 'Annual Leave',
            startDate: start,
            endDate: end,
            description: dc.Patch.set(description),
            reminders: dc.Patch.set(reminders),
          );
          annualLeaveUpdated++;
        } else {
          await _calendar.createEvent(
            calendarId: leaveCalendarId,
            title: 'Annual Leave',
            startDate: start,
            endDate: end,
            description: description,
            reminders: reminders,
          );
          annualLeaveCreated++;
        }
      }
    }

    return CalendarSyncResult(
      created: created,
      updated: updated,
      skipped: skipped,
      duplicates: duplicates,
      annualLeaveCreated: annualLeaveCreated,
      annualLeaveUpdated: annualLeaveUpdated,
      holidayLeaveCreated: holidayLeaveCreated,
      holidayLeaveUpdated: holidayLeaveUpdated,
    );
  }

  DateTime _startFor(DatedShift entry) {
    return DateTime(entry.date.year, entry.date.month, entry.date.day)
        .add(Duration(minutes: entry.shift.effectiveStartMinutes!));
  }

  Future<String> _ensureAnnualLeaveCalendar(String colorHex) async {
    final calendars = await _calendar.listCalendars();
    for (final calendar in calendars) {
      if (!calendar.readOnly && calendar.name == _annualLeaveCalendarName) {
        if (calendar.colorHex?.toUpperCase() != colorHex.toUpperCase()) {
          await _calendar.updateCalendar(calendar.id, colorHex: colorHex);
        }
        return calendar.id;
      }
    }
    return _calendar.createCalendar(
      name: _annualLeaveCalendarName,
      colorHex: colorHex,
    );
  }

  Future<List<dc.Event>> _existingAtcEvents(
    String calendarId,
    List<DatedShift> shifts,
  ) async {
    if (shifts.isEmpty) return const [];
    final dates = shifts.map((e) => e.date).toList()
      ..sort((a, b) => a.compareTo(b));
    final first = dates.first;
    final last = dates.last;
    final rangeStart = DateTime(first.year, first.month, first.day);
    final rangeEnd = DateTime(last.year, last.month, last.day)
        .add(const Duration(days: 2));
    final events = await _calendar.listEvents(
      rangeStart,
      rangeEnd,
      calendarIds: [calendarId],
    );
    return events.where(_looksLikeAtcManagerEvent).toList();
  }

  dc.Event? _findExistingFor(DatedShift entry, List<dc.Event> events) {
    final startMinutes = entry.shift.effectiveStartMinutes;
    if (startMinutes == null) return null;
    final expected = DateTime(entry.date.year, entry.date.month, entry.date.day)
        .add(Duration(minutes: startMinutes));

    for (final event in events) {
      final sameDay = event.startDate.year == expected.year &&
          event.startDate.month == expected.month &&
          event.startDate.day == expected.day;
      if (!sameDay) continue;

      final difference = event.startDate.difference(expected).inMinutes.abs();
      if (difference <= 180) return event;
    }
    return null;
  }

  dc.Event? _findExistingOnDateByTitle(
    DatedShift entry,
    List<dc.Event> events,
    String title,
  ) {
    for (final event in events) {
      final sameDay = event.startDate.year == entry.date.year &&
          event.startDate.month == entry.date.month &&
          event.startDate.day == entry.date.day;
      if (sameDay && event.title.trim().toLowerCase() == title.toLowerCase()) {
        return event;
      }
    }
    return null;
  }

  bool _looksLikeAtcManagerEvent(dc.Event event) {
    final description = event.description ?? '';
    if (description.contains(_descriptionPrefix)) return true;
    final title = event.title.trim().toLowerCase();
    return title == 'annual leave' ||
        title == 'holiday leave' ||
        RegExp(r'^[a-z$]*(?:xtra)?\d{3,4}[a-z$]*(?:xtra)?$', caseSensitive: false)
            .hasMatch(event.title.trim());
  }
}
