import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/schedule_display_settings.dart';
import 'screens/calendar_sync_page.dart';
import 'screens/pay_period_schedule_view.dart';
import 'screens/settings_page.dart';
import 'screens/upcoming_leave_page.dart';
import 'screens/update_schedule_page.dart';
import 'services/wmt_schedule_extractor.dart';

void main() => runApp(const AtcScheduleManagerApp());

class AtcScheduleManagerApp extends StatelessWidget {
  const AtcScheduleManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Web Schedule Manager',
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
  static const _htmlKey = 'saved_wmt_schedule_html';
  static const _updatedKey = 'saved_wmt_schedule_updated_at';
  static const _changesKey = 'saved_wmt_schedule_changes';

  final _extractor = const WmtScheduleExtractor();
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
    final html = prefs.getString(_htmlKey);
    final updated = prefs.getString(_updatedKey);
    final savedChanges = prefs.getStringList(_changesKey) ?? const <String>[];
    final displaySettings = await ScheduleDisplaySettings.load();

    if (!mounted) return;

    if (html == null || html.isEmpty) {
      setState(() {
        _scheduleChanges = savedChanges;
        _displaySettings = displaySettings;
        _loading = false;
      });
      return;
    }

    try {
      final shifts = _extractor.extract(html);
      setState(() {
        _shifts = shifts;
        _scheduleChanges = savedChanges;
        _lastUpdated = updated == null ? null : DateTime.tryParse(updated);
        _displaySettings = displaySettings;
        _loading = false;
        _error = shifts.isEmpty ? 'Saved WMT data was found, but no schedule entries could be read.' : null;
      });
    } catch (e) {
      setState(() {
        _scheduleChanges = savedChanges;
        _displaySettings = displaySettings;
        _loading = false;
        _error = 'Could not load the saved schedule.';
      });
    }
  }

  Future<void> _updateSchedule() async {
    final html = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const UpdateSchedulePage()),
    );

    if (!mounted || html == null || html.isEmpty) return;

    final shifts = _extractor.extract(html);
    if (shifts.isEmpty) {
      setState(() => _error = 'The WMT page was captured, but no schedule entries were recognized.');
      return;
    }

    final changes = _detectScheduleChanges(_shifts, shifts);
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_htmlKey, html);
    await prefs.setString(_updatedKey, now.toIso8601String());
    await prefs.setStringList(_changesKey, changes);

    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _scheduleChanges = changes;
      _lastUpdated = now;
      _error = null;
    });
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

    final commonDays = oldByDay.keys
        .where(newByDay.containsKey)
        .toList()
      ..sort();

    final changes = <String>[];
    for (final key in commonDays) {
      final oldEntry = oldByDay[key]!;
      final newEntry = newByDay[key]!;
      final oldShift = oldEntry.shift.raw.trim();
      final newShift = newEntry.shift.raw.trim();
      if (oldShift.toUpperCase() == newShift.toUpperCase()) continue;

      final date = newEntry.date;
      changes.add(
        '${date.month}/${date.day}/${date.year}: $oldShift → $newShift',
      );
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

  Future<void> _openUpcomingLeave() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UpcomingLeavePage(displaySettings: _displaySettings),
      ),
    );
  }

  Future<void> _openCalendarSync() async {
    if (_shifts.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CalendarSyncPage(
          shifts: _shifts,
          displaySettings: _displaySettings,
        ),
      ),
    );
  }

  Future<void> _openChangedCalendarSync() async {
    final changed = _changedShifts();
    if (changed.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CalendarSyncPage(
          shifts: changed,
          displaySettings: _displaySettings,
          changeUpdateMode: true,
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
        title: const Text('Web Schedule Manager'),
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
            tooltip: 'Update schedule',
            onPressed: _updateSchedule,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.history, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Schedule data last updated: ${_formatUpdated(_lastUpdated!)}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _updateSchedule,
                      icon: const Icon(Icons.sync),
                      label: const Text('Update Schedule'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _openUpcomingLeave,
                      icon: const Icon(Icons.beach_access_outlined),
                      label: const Text('Upcoming Leave'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _openCalendarSync,
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
                            Row(
                              children: [
                                Icon(
                                  _scheduleChanges.isEmpty
                                      ? Icons.check_circle_outline
                                      : Icons.notification_important_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Schedule Changes',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_scheduleChanges.isEmpty)
                              const Text(
                                'No shift changes detected since the previous schedule update.',
                              )
                            else ...[
                              Text(
                                '${_scheduleChanges.length} change${_scheduleChanges.length == 1 ? '' : 's'} detected since the previous update:',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              for (final change in _scheduleChanges)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text('• $change'),
                                ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _changedShifts().isEmpty ? null : _openChangedCalendarSync,
                                  icon: const Icon(Icons.edit_calendar_outlined),
                                  label: Text(
                                    'Update Calendar (${_scheduleChanges.length})',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Only the dates with detected changes will be sent to calendar update mode.',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 80),
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved schedule yet',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect to WMT once to save your schedule on this phone. After that, the saved schedule will be the first thing you see when the app opens.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _updateSchedule,
                      icon: const Icon(Icons.sync),
                      label: const Text('Get Schedule'),
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
