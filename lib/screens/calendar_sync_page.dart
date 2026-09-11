import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:flutter/material.dart';

import '../models/schedule_display_settings.dart';
import '../services/calendar_sync_service.dart';
import '../services/wmt_schedule_extractor.dart';

class CalendarSyncPage extends StatefulWidget {
  const CalendarSyncPage({
    super.key,
    required this.shifts,
    required this.displaySettings,
    this.changeUpdateMode = false,
  });

  final List<DatedShift> shifts;
  final ScheduleDisplaySettings displaySettings;
  final bool changeUpdateMode;

  @override
  State<CalendarSyncPage> createState() => _CalendarSyncPageState();
}

class _CalendarSyncPageState extends State<CalendarSyncPage> {
  final _service = CalendarSyncService();
  List<dc.Calendar> _calendars = const [];
  String? _selectedCalendarId;
  bool _loading = true;
  bool _syncing = false;
  bool _reminder24h = false;
  bool _reminder2h = false;
  bool _reminder30m = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadCalendars();
  }

  Future<void> _loadCalendars() async {
    try {
      final calendars = await _service.requestWritableCalendars();
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        _selectedCalendarId = calendars.isEmpty ? null : calendars.first.id;
        _loading = false;
        _message = calendars.isEmpty ? 'No writable calendars were found on this device.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Calendar access is required before shifts can be added.';
      });
    }
  }

  List<Duration> get _selectedReminders {
    final reminders = <Duration>[];
    if (_reminder24h) reminders.add(const Duration(days: 1));
    if (_reminder2h) reminders.add(const Duration(hours: 2));
    if (_reminder30m) reminders.add(const Duration(minutes: 30));
    return reminders;
  }

  String _annualLeaveColorHex() {
    final color = widget.displaySettings.annualLeaveCalendarColor ??
        const Color(0xFFD8F3DC);
    final hex = color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    return '#$hex';
  }

  Future<DuplicateHandling?> _askDuplicateHandling(int count) async {
    return showDialog<DuplicateHandling>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Existing shifts found'),
        content: Text('$count matching Web Schedule Manager calendar entr${count == 1 ? 'y' : 'ies'} already exist. What should the app do with matches?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, DuplicateHandling.createNew),
            child: const Text('Create New'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DuplicateHandling.updateExisting),
            child: const Text('Update Existing'),
          ),
        ],
      ),
    );
  }

  Future<void> _sync() async {
    final calendarId = _selectedCalendarId;
    if (calendarId == null || _syncing) return;

    setState(() {
      _syncing = true;
      _message = null;
    });

    try {
      final matches = await _service.countExistingMatches(
        calendarId: calendarId,
        shifts: widget.shifts,
        matchSameDate: widget.changeUpdateMode,
      );
      var handling = DuplicateHandling.updateExisting;
      if (!widget.changeUpdateMode && matches > 0) {
        if (!mounted) return;
        final choice = await _askDuplicateHandling(matches);
        if (choice == null) {
          if (mounted) setState(() => _syncing = false);
          return;
        }
        handling = choice;
      }

      final result = await _service.syncShiftEvents(
        calendarId: calendarId,
        shifts: widget.shifts,
        duplicateHandling: handling,
        reminders: _selectedReminders,
        annualLeaveColorHex: _annualLeaveColorHex(),
        matchSameDate: widget.changeUpdateMode,
      );
      if (!mounted) return;
      final leaveTotal = result.annualLeaveCreated + result.annualLeaveUpdated;
      final holidayTotal = result.holidayLeaveCreated + result.holidayLeaveUpdated;
      setState(() {
        _syncing = false;
        final removedText = result.deleted > 0
            ? ', ${result.deleted} obsolete entr${result.deleted == 1 ? 'y' : 'ies'} removed'
            : '';
        _message = widget.changeUpdateMode
            ? 'Calendar changes applied: ${result.updated} shift${result.updated == 1 ? '' : 's'} updated$removedText${leaveTotal > 0 ? ', $leaveTotal Annual Leave entr${leaveTotal == 1 ? 'y' : 'ies'} synced' : ''}${holidayTotal > 0 ? ', and $holidayTotal Holiday Leave entr${holidayTotal == 1 ? 'y' : 'ies'} synced' : ''}.'
            : 'Calendar sync complete: ${result.created} shifts added, ${result.updated} updated$removedText${leaveTotal > 0 ? ', $leaveTotal Annual Leave entr${leaveTotal == 1 ? 'y' : 'ies'} synced' : ''}${holidayTotal > 0 ? ', and $holidayTotal Holiday Leave entr${holidayTotal == 1 ? 'y' : 'ies'} synced' : ''}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _message = 'Calendar sync could not be completed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workingCount = _service.workingShifts(widget.shifts).length;
    final leaveCount = _service.annualLeaveShifts(widget.shifts).length;
    final holidayCount = _service.holidayLeaveShifts(widget.shifts).length;

    return Scaffold(
      appBar: AppBar(title: Text(widget.changeUpdateMode ? 'Update Calendar Changes' : 'Add to Calendar')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.changeUpdateMode) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.sync_problem_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Only the dates with detected schedule changes are shown here. Existing Web Schedule Manager events on those dates will be updated, replaced, or removed as needed.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Calendar destination', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          if (_calendars.isNotEmpty)
                            DropdownButtonFormField<String>(
                              value: _selectedCalendarId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Calendar',
                              ),
                              items: [
                                for (final calendar in _calendars)
                                  DropdownMenuItem(
                                    value: calendar.id,
                                    child: Text(
                                      calendar.accountName == null || calendar.accountName!.isEmpty
                                          ? calendar.name
                                          : '${calendar.name} • ${calendar.accountName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(() => _selectedCalendarId = value),
                            ),
                          const SizedBox(height: 16),
                          Text('$workingCount working shifts are ready to sync.'),
                          if (leaveCount > 0) ...[
                            const SizedBox(height: 6),
                            Text('$leaveCount Annual Leave entr${leaveCount == 1 ? 'y is' : 'ies are'} also ready to sync.'),
                          ],
                          if (holidayCount > 0) ...[
                            const SizedBox(height: 6),
                            Text('$holidayCount Holiday Leave entr${holidayCount == 1 ? 'y is' : 'ies are'} also ready to sync.'),
                          ],
                          const SizedBox(height: 8),
                          const Text('Work events use the exact WMT shift name as the calendar title and start at the time printed in that name. Holiday Leave is added as an all-day event.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reminders', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          const Text('Leave all options off for no reminders.'),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('24 hours before'),
                            value: _reminder24h,
                            onChanged: (value) => setState(() => _reminder24h = value ?? false),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('2 hours before'),
                            value: _reminder2h,
                            onChanged: (value) => setState(() => _reminder2h = value ?? false),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('30 minutes before'),
                            value: _reminder30m,
                            onChanged: (value) => setState(() => _reminder30m = value ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_message!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _calendars.isEmpty || _syncing ? null : _sync,
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.event_available_outlined),
                    label: Text(_syncing ? 'Syncing…' : widget.changeUpdateMode ? 'Update Changed Entries' : 'Sync Schedule'),
                  ),
                ],
              ),
      ),
    );
  }
}
