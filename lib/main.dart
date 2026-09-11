import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/dated_shift.dart';
import 'models/schedule_display_settings.dart';
import 'screens/calendar_sync_page.dart';
import 'screens/pay_period_schedule_view.dart';
import 'screens/screenshot_import_page.dart';
import 'screens/settings_page.dart';
import 'screens/upcoming_leave_page.dart';
import 'services/schedule_parser.dart';

void main() => runApp(const AtcScheduleManagerApp());

class AtcScheduleManagerApp extends StatelessWidget {
  const AtcScheduleManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ATC Schedule Manager Lite',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ScheduleHomePage(),
    );
  }
}

class ScheduleHomePage extends StatefulWidget {
  const ScheduleHomePage({super.key});

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage> {
  static const _entriesKey = 'screenshot_schedule_entries';
  static const _updatedKey = 'screenshot_schedule_updated_at';
  static const _changesKey = 'screenshot_schedule_changes';

  final _parser = const ScheduleParser();
  List<DatedShift> _shifts = const [];
  List<String> _scheduleChanges = const [];
  DateTime? _lastUpdated;
  ScheduleDisplaySettings _displaySettings = ScheduleDisplaySettings.defaults;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedSchedule();
  }

  Future<void> _loadSavedSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEntries = prefs.getStringList(_entriesKey) ?? const <String>[];
    final updated = prefs.getString(_updatedKey);
    final savedChanges = prefs.getStringList(_changesKey) ?? const <String>[];
    final displaySettings = await ScheduleDisplaySettings.load();

    final shifts = <DatedShift>[];
    for (final row in savedEntries) {
      final separator = row.indexOf('|');
      if (separator <= 0 || separator >= row.length - 1) continue;
      final date = DateTime.tryParse(row.substring(0, separator));
      if (date == null) continue;
      try {
        final shift = _parser.parse(row.substring(separator + 1));
        shifts.add(DatedShift(date: date, shift: shift));
      } catch (_) {}
    }
    shifts.sort((a, b) => a.date.compareTo(b.date));

    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _scheduleChanges = savedChanges;
      _lastUpdated = updated == null ? null : DateTime.tryParse(updated);
      _displaySettings = displaySettings;
      _loading = false;
    });
  }

  Future<void> _importScreenshots() async {
    final imported = await Navigator.of(context).push<List<DatedShift>>(
      MaterialPageRoute(builder: (_) => const ScreenshotImportPage()),
    );
    if (!mounted || imported == null || imported.isEmpty) return;

    final changes = _detectScheduleChanges(_shifts, imported);
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _entriesKey,
      imported
          .map((entry) => '${entry.date.toIso8601String()}|${entry.shift.raw}')
          .toList(),
    );
    await prefs.setString(_updatedKey, now.toIso8601String());
    await prefs.setStringList(_changesKey, changes);

    if (!mounted) return;
    setState(() {
      _shifts = imported;
      _scheduleChanges = changes;
      _lastUpdated = now;
      _error = null;
    });
  }

  Future<void> _openUpcomingLeave() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UpcomingLeavePage(displaySettings: _displaySettings),
      ),
    );
  }

  List<String> _detectScheduleChanges(
    List<DatedShift> previous,
    List<DatedShift> current,
  ) {
    if (previous.isEmpty || current.isEmpty) return const [];

    String dayKey(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    final oldByDay = <String, DatedShift>{
      for (final entry in previous) dayKey(entry.date): entry,
    };
    final newByDay = <String, DatedShift>{
      for (final entry in current) dayKey(entry.date): entry,
    };

    final commonDays = oldByDay.keys.where(newByDay.containsKey).toList()..sort();
    final changes = <String>[];
    for (final key in commonDays) {
      final oldEntry = oldByDay[key]!;
      final newEntry = newByDay[key]!;
      final oldShift = oldEntry.shift.raw.trim();
      final newShift = newEntry.shift.raw.trim();
      if (oldShift.toUpperCase() == newShift.toUpperCase()) continue;
      final date = newEntry.date;
      changes.add('${date.month}/${date.day}/${date.year}: $oldShift → $newShift');
    }
    return changes;
  }

  Set<String> _changedDayKeys() {
    final keys = <String>{};
    final datePattern = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4}):');
    for (final change in _scheduleChanges) {
      final match = datePattern.firstMatch(change);
      if (match == null) continue;
      final month = int.tryParse(match.group(1)!);
      final day = int.tryParse(match.group(2)!);
      final year = int.tryParse(match.group(3)!);
      if (month == null || day == null || year == null) continue;
      keys.add('$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
    }
    return keys;
  }

  List<DatedShift> _changedShifts() {
    final keys = _changedDayKeys();
    return _shifts.where((entry) {
      final key = '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}-${entry.date.day.toString().padLeft(2, '0')}';
      return keys.contains(key);
    }).toList();
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<ScheduleDisplaySettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initialSettings: _displaySettings),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _displaySettings = result);
  }

  Future<void> _openCalendarSync({bool changesOnly = false}) async {
    final shifts = changesOnly ? _changedShifts() : _shifts;
    if (shifts.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CalendarSyncPage(
          shifts: shifts,
          displaySettings: _displaySettings,
          changeUpdateMode: changesOnly,
        ),
      ),
    );
  }

  String _formatUpdated(DateTime date) {
    final hour = date.hour == 0 ? 12 : date.hour > 12 ? date.hour - 12 : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.month}/${date.day}/${date.year} at $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ATC Schedule Manager Lite'),
        actions: [
          IconButton(
            tooltip: 'Upcoming Leave',
            onPressed: _openUpcomingLeave,
            icon: const Icon(Icons.beach_access_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Import screenshots',
            onPressed: _importScreenshots,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.shield_outlined),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Lite screenshot edition: this app does not log into WMT or connect to the FAA website. Import screenshots from your phone to update the schedule.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_error!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_shifts.isNotEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PayPeriodScheduleView(
                          shifts: _shifts,
                          displaySettings: _displaySettings,
                        ),
                      ),
                    ),
                    if (_lastUpdated != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Schedule data last updated: ${_formatUpdated(_lastUpdated!)}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _importScreenshots,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Import New Screenshots'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _openUpcomingLeave,
                      icon: const Icon(Icons.beach_access_outlined),
                      label: const Text('Upcoming Leave'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _openCalendarSync(),
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('Add to Calendar'),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Schedule Changes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            if (_scheduleChanges.isEmpty)
                              const Text('No shift changes detected since the previous screenshot import.')
                            else ...[
                              for (final change in _scheduleChanges)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text('• $change'),
                                ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _changedShifts().isEmpty ? null : () => _openCalendarSync(changesOnly: true),
                                  icon: const Icon(Icons.edit_calendar_outlined),
                                  label: Text('Update Calendar (${_scheduleChanges.length})'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 70),
                    Icon(
                      Icons.photo_library_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No schedule imported yet',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Take screenshots of your schedule pages, then select them here. The app will read the dates and shift codes locally and let you review the results before saving.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _importScreenshots,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Import Schedule Screenshots'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _openUpcomingLeave,
                      icon: const Icon(Icons.beach_access_outlined),
                      label: const Text('Upcoming Leave'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
