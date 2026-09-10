import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:flutter/material.dart';

import '../services/calendar_sync_service.dart';
import '../services/wmt_schedule_extractor.dart';

class CalendarSyncPage extends StatefulWidget {
  const CalendarSyncPage({super.key, required this.shifts});

  final List<DatedShift> shifts;

  @override
  State<CalendarSyncPage> createState() => _CalendarSyncPageState();
}

class _CalendarSyncPageState extends State<CalendarSyncPage> {
  final _service = CalendarSyncService();
  List<dc.Calendar> _calendars = const [];
  String? _selectedCalendarId;
  bool _loading = true;
  bool _syncing = false;
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
        _message = calendars.isEmpty
            ? 'No writable calendars were found on this device.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Calendar access is required before shifts can be added.';
      });
    }
  }

  Future<DuplicateHandling?> _chooseDuplicateHandling(int duplicateCount) {
    return showDialog<DuplicateHandling>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Existing shifts found'),
        content: Text(
          '$duplicateCount shift${duplicateCount == 1 ? '' : 's'} already appear to be in this calendar. What should ATC Schedule Manager do with all matching shifts?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(DuplicateHandling.createNew),
            child: const Text('Create New'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(DuplicateHandling.updateExisting),
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
      _message = 'Checking the selected calendar for existing shifts…';
    });

    try {
      final duplicateCount = await _service.countExistingMatches(
        calendarId: calendarId,
        shifts: widget.shifts,
      );
      if (!mounted) return;

      var handling = DuplicateHandling.updateExisting;
      if (duplicateCount > 0) {
        setState(() => _syncing = false);
        final choice = await _chooseDuplicateHandling(duplicateCount);
        if (!mounted || choice == null) {
          setState(() => _message = 'Calendar sync cancelled.');
          return;
        }
        handling = choice;
        setState(() {
          _syncing = true;
          _message = handling == DuplicateHandling.updateExisting
              ? 'Updating existing shifts and adding new ones…'
              : 'Creating new calendar events…';
        });
      } else {
        setState(() => _message = 'Adding shifts to the selected calendar…');
      }

      final result = await _service.syncWorkingShiftEvents(
        calendarId: calendarId,
        shifts: widget.shifts,
        duplicateHandling: handling,
      );
      if (!mounted) return;

      final parts = <String>[];
      if (result.created > 0) parts.add('${result.created} added');
      if (result.updated > 0) parts.add('${result.updated} updated');
      if (result.duplicates > 0 && handling == DuplicateHandling.createNew) {
        parts.add('${result.duplicates} duplicates created by choice');
      }
      if (parts.isEmpty) parts.add('No working shifts changed');

      setState(() {
        _syncing = false;
        _message = '${parts.join(' • ')}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _message = 'Calendar sync could not be completed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workingCount = _service.workingShifts(widget.shifts).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Add to Calendar')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calendar destination',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (_calendars.isNotEmpty)
                            DropdownButtonFormField<String>(
                              value: _selectedCalendarId,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Calendar',
                              ),
                              items: [
                                for (final calendar in _calendars)
                                  DropdownMenuItem(
                                    value: calendar.id,
                                    child: Text(
                                      calendar.accountName == null ||
                                              calendar.accountName!.isEmpty
                                          ? calendar.name
                                          : '${calendar.name} • ${calendar.accountName}',
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedCalendarId = value),
                            ),
                          const SizedBox(height: 16),
                          Text('$workingCount working shifts are ready to sync.'),
                          const SizedBox(height: 6),
                          const Text(
                            'Days off and leave are not added. If matching ATC Schedule Manager events already exist, you will be asked whether to update them or create new copies. The choice applies to all matches in this sync.',
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Events currently use three reminders: 24 hours, 2 hours, and 30 minutes before shift start.',
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
                    label: Text(_syncing ? 'Syncing shifts…' : 'Sync Working Shifts'),
                  ),
                ],
              ),
      ),
    );
  }
}
