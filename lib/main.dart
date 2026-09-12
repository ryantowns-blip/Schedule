import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/dated_shift.dart';
import 'models/schedule_display_settings.dart';
import 'screens/calendar_sync_page.dart';
import 'screens/leave_balance_page.dart';
import 'screens/pay_period_schedule_view.dart';
import 'screens/screenshot_import_page.dart';
import 'screens/settings_page.dart';
import 'screens/upcoming_leave_page.dart';
import 'services/schedule_parser.dart';
import 'services/screenshot_cleanup_service.dart';
import 'theme/app_theme.dart';

void main() => runApp(const AtcScheduleManagerApp());

class AtcScheduleManagerApp extends StatelessWidget {
  const AtcScheduleManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Web Schedule Manager',
      theme: AppTheme.light,
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
  final _cleanup = const ScreenshotCleanupService();
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
    final reviewed = await Navigator.of(context).push<ScheduleScreenshotReviewResult>(
      MaterialPageRoute(builder: (_) => const ScreenshotImportPage()),
    );
    if (!mounted || reviewed == null || reviewed.shifts.isEmpty) return;

    final imported = reviewed.shifts;
    final changes = _detectScheduleChanges(_shifts, imported);
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _entriesKey,
      imported.map((entry) => '${entry.date.toIso8601String()}|${entry.shift.raw}').toList(),
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

    if (reviewed.deleteSourceImages && reviewed.sourceImages.isNotEmpty) {
      try {
        final result = await _cleanup.deleteSourceImages(reviewed.sourceImages);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        if (result.permissionDenied) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Schedule saved. Screenshot deletion was skipped because photo-library access was not granted.')),
          );
        } else if (result.deleted == result.requested) {
          messenger.showSnackBar(
            SnackBar(content: Text('Schedule saved. Deleted ${result.deleted} source screenshot${result.deleted == 1 ? '' : 's'}.')),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Schedule saved. Deleted ${result.deleted} of ${result.requested} source screenshots; unmatched or ambiguous images were left on the phone.',
              ),
            ),
          );
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule saved, but the source screenshots could not be deleted.')),
        );
      }
    }
  }

  Future<void> _openUpcomingLeave() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UpcomingLeavePage(displaySettings: _displaySettings),
      ),
    );
  }

  Future<void> _openLeaveBalance() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LeaveBalancePage()),
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

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Web Schedule Manager',
      applicationVersion: '0.12.0 beta',
      applicationIcon: const Icon(Icons.calendar_month_outlined, size: 42),
      children: const [
        Text(
          'Import WMT schedule and leave screenshots, review the results, and add approved entries to your calendar. Screenshots are processed only on this device.',
        ),
      ],
    );
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
        title: const Text('Web Schedule Manager'),
        actions: [
          IconButton(
            tooltip: 'Upcoming Leave',
            onPressed: _openUpcomingLeave,
            icon: const Icon(Icons.beach_access_outlined),
          ),
          IconButton(
            tooltip: 'Import screenshots',
            onPressed: _importScreenshots,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'settings') _openSettings();
              if (value == 'about') _showAbout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 20),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Private by design: screenshots stay on this device. The app never signs in to WMT.',
                          ),
                        ),
                      ],
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
                    _HomeActions(
                      onImport: _importScreenshots,
                      onLeave: _openUpcomingLeave,
                      onCalendar: () => _openCalendarSync(),
                      onBalance: _openLeaveBalance,
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
                    const SizedBox(height: 36),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.calendar_month_outlined,
                                size: 38,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Your schedule starts here',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Take screenshots of your WMT schedule, then select them here. You will review every entry before anything is saved.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _importScreenshots,
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                label: const Text('Import Schedule Screenshots'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openUpcomingLeave,
                        icon: const Icon(Icons.beach_access_outlined),
                        label: const Text('Import Upcoming Leave'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openLeaveBalance,
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Leave Balance'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _HomeActions extends StatelessWidget {
  const _HomeActions({
    required this.onImport,
    required this.onLeave,
    required this.onCalendar,
    required this.onBalance,
  });

  final VoidCallback onImport;
  final VoidCallback onLeave;
  final VoidCallback onCalendar;
  final VoidCallback onBalance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Update Schedule'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onLeave,
                icon: const Icon(Icons.beach_access_outlined),
                label: const Text('Leave'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCalendar,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Calendar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onBalance,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Leave Balance'),
        ),
      ],
    );
  }
}
