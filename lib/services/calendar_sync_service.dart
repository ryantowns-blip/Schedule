import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;

import 'wmt_schedule_extractor.dart';

enum DuplicateHandling { updateExisting, createNew }

class CalendarSyncResult {
  const CalendarSyncResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.duplicates,
  });

  final int created;
  final int updated;
  final int skipped;
  final int duplicates;
}

class CalendarSyncService {
  CalendarSyncService({dc.DeviceCalendar? calendar})
      : _calendar = calendar ?? dc.DeviceCalendar.instance;

  static const _descriptionPrefix = 'ATC Schedule Manager';
  static const _defaultReminders = <Duration>[
    Duration(days: 1),
    Duration(hours: 2),
    Duration(minutes: 30),
  ];

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

  Future<int> countExistingMatches({
    required String calendarId,
    required List<DatedShift> shifts,
  }) async {
    final working = workingShifts(shifts);
    if (working.isEmpty) return 0;
    final existing = await _existingAtcEvents(calendarId, working);
    var count = 0;
    for (final entry in working) {
      if (_findExistingFor(entry, existing) != null) count++;
    }
    return count;
  }

  Future<CalendarSyncResult> syncWorkingShiftEvents({
    required String calendarId,
    required List<DatedShift> shifts,
    required DuplicateHandling duplicateHandling,
  }) async {
    var created = 0;
    var updated = 0;
    var skipped = 0;
    var duplicates = 0;

    final working = workingShifts(shifts);
    final existing = await _existingAtcEvents(calendarId, working);

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
      final description = '$_descriptionPrefix • WMT code: ${shift.raw}';
      final match = _findExistingFor(entry, existing);

      if (match != null) {
        duplicates++;
        if (duplicateHandling == DuplicateHandling.updateExisting) {
          await _calendar.updateEvent(
            eventId: match.instanceId,
            title: _titleFor(entry),
            startDate: start,
            endDate: end,
            description: dc.Patch.set(description),
            reminders: const dc.Patch.set(_defaultReminders),
          );
          updated++;
          continue;
        }
      }

      await _calendar.createEvent(
        calendarId: calendarId,
        title: _titleFor(entry),
        startDate: start,
        endDate: end,
        description: description,
        reminders: _defaultReminders,
      );
      created++;
    }

    return CalendarSyncResult(
      created: created,
      updated: updated,
      skipped: skipped,
      duplicates: duplicates,
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

  bool _looksLikeAtcManagerEvent(dc.Event event) {
    final description = event.description ?? '';
    if (description.contains(_descriptionPrefix)) return true;
    final title = event.title.trim().toLowerCase();
    return title == 'atc shift' ||
        title == 'atc supervisor' ||
        title == 'atc cic' ||
        title == r'$ ot';
  }

  String _titleFor(DatedShift entry) {
    final shift = entry.shift;
    if (shift.isOvertime) return r'$ OT';
    if (shift.isSupervisor) return 'ATC Supervisor';
    if (shift.isCic) return 'ATC CIC';
    return 'ATC Shift';
  }
}
