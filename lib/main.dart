import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/dated_shift.dart';
import 'models/leave_balance.dart';
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
  LeaveBalanceSettings? _leaveBalanceSettings;
  LeaveProjection? _leaveProjection;
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
    final leaveSummary = _buildLeaveSummary(prefs, shifts);
    setState(() {
      _shifts = shifts;
      _scheduleChanges = savedChanges;
      _lastUpdated = updated == null ? null : DateTime.tryParse(updated);
      _displaySettings = displaySettings;
      _leaveBalanceSettings = leaveSummary.$1;
      _leaveProjection = leaveSummary.$2;
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
    await _refreshLeaveBalance();

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
    await _refreshLeaveBalance();
  }

  Future<void> _openLeaveBalance() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LeaveBalancePage()),
    );
    await _refreshLeaveBalance();
  }

  Future<void> _refreshLeaveBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final summary = _buildLeaveSummary(prefs, _shifts);
    if (!mounted) return;
    setState(() {
      _leaveBalanceSettings = summary.$1;
      _leaveProjection = summary.$2;
    });
  }

  (LeaveBalanceSettings?, LeaveProjection?) _buildLeaveSummary(
    SharedPreferences prefs,
    List<DatedShift> shifts,
  ) {
    final effective = DateTime.tryParse(prefs.getString('leave_balance_effective_date') ?? '');
    if (effective == null || !prefs.containsKey('leave_balance_annual_hours')) {
      return (null, null);
    }
    final settings = LeaveBalanceSettings(
      effectiveDate: effective,
      annualBalance: prefs.getDouble('leave_balance_annual_hours') ?? 0,
      sickBalance: prefs.getDouble('leave_balance_sick_hours') ?? 0,
      annualAccrualPerPayPeriod: prefs.getDouble('leave_balance_annual_accrual') ?? 8,
      sickAccrualPerPayPeriod: prefs.getDouble('leave_balance_sick_accrual') ?? 4,
      annualCarryoverLimit: prefs.getDouble('leave_balance_carryover_limit') ?? 240,
    );
    final usage = <LeaveUsage>[
      for (final entry in shifts)
        if (entry.shift.isAnnualLeave)
          LeaveUsage(date: entry.date, kind: LeaveKind.annual)
        else if (entry.shift.isSickLeave)
          LeaveUsage(date: entry.date, kind: LeaveKind.sick),
    ];
    for (final row in prefs.getStringList('screenshot_leave_entries_v1') ?? const <String>[]) {
      try {
        final map = jsonDecode(row) as Map<String, dynamic>;
        final date = DateTime.tryParse(map['date'] as String? ?? '');
        final status = (map['status'] as String? ?? '').toLowerCase();
        final type = (map['type'] as String? ?? '').toLowerCase();
        if (date == null || status != 'approved') continue;
        if (type.contains('annual')) usage.add(LeaveUsage(date: date, kind: LeaveKind.annual));
        if (type.contains('sick')) usage.add(LeaveUsage(date: date, kind: LeaveKind.sick));
      } catch (_) {}
    }
    for (final row in prefs.getStringList('manual_leave_usage_v1') ?? const <String>[]) {
      try {
        final map = jsonDecode(row) as Map<String, dynamic>;
        final date = DateTime.tryParse(map['date'] as String? ?? '');
        final hours = (map['hours'] as num?)?.toDouble();
        final id = map['id'] as String?;
        if (date == null || hours == null || hours <= 0 || id == null) continue;
        usage.add(LeaveUsage(
          id: id,
          date: date,
          hours: hours,
          kind: map['kind'] == LeaveKind.sick.name ? LeaveKind.sick : LeaveKind.annual,
        ));
      } catch (_) {}
    }
    return (
      settings,
      const LeaveProjectionService().calculate(settings: settings, usage: usage),
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
      applicationVersion: '0.12.1 beta',
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
                    if (_leaveBalanceSettings != null && _leaveProjection != null) ...[
                      const SizedBox(height: 12),
                      _HomeLeaveBalanceCard(
                        settings: _leaveBalanceSettings!,
                        projection: _leaveProjection!,
                        onTap: _openLeaveBalance,
                      ),
                    ],
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

class _HomeLeaveBalanceCard extends StatelessWidget {
  const _HomeLeaveBalanceCard({
    required this.settings,
    required this.projection,
    required this.onTap,
  });

  final LeaveBalanceSettings settings;
  final LeaveProjection projection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warning = projection.useOrLose > 0 ||
        projection.projectedAnnual < 0 ||
        projection.projectedSick < 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text('Leave Balance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (warning) Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Current and projected year-end hours',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _AnnualLeaveXpBar(
                current: projection.currentAnnual,
                projected: projection.projectedAnnual,
                carryoverLimit: settings.annualCarryoverLimit,
              ),
              const SizedBox(height: 18),
              _CompactSickLeaveRow(
                current: projection.currentSick,
                projected: projection.projectedSick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnualLeaveXpBar extends StatelessWidget {
  const _AnnualLeaveXpBar({
    required this.current,
    required this.projected,
    required this.carryoverLimit,
  });

  final double current;
  final double projected;
  final double carryoverLimit;

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final safeCurrent = current.clamp(0, double.infinity).toDouble();
    final safeProjected = projected.clamp(0, double.infinity).toDouble();
    final scaleMaximum = [carryoverLimit, safeCurrent, safeProjected]
        .reduce((a, b) => a > b ? a : b);
    final currentWithinLimit = safeCurrent.clamp(0, carryoverLimit).toDouble();
    final projectedGainWithinLimit =
        (safeProjected.clamp(0, carryoverLimit) - currentWithinLimit)
            .clamp(0, double.infinity)
            .toDouble();
    final projectedOverLimit =
        (safeProjected - carryoverLimit).clamp(0, double.infinity).toDouble();
    final limitPosition = scaleMaximum == 0 ? 1.0 : carryoverLimit / scaleMaximum;

    const currentColor = Color(0xFF176B37);
    const projectedColor = Color(0xFF8FD3A1);
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Annual leave', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Text(
              '${_format(current)} current  →  ${_format(projected)} projected',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double widthFor(double hours) =>
                  scaleMaximum == 0 ? 0 : constraints.maxWidth * hours / scaleMaximum;
              return SizedBox(
                height: 18,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: widthFor(currentWithinLimit),
                      child: const ColoredBox(color: currentColor),
                    ),
                    Positioned(
                      left: widthFor(currentWithinLimit),
                      top: 0,
                      bottom: 0,
                      width: widthFor(projectedGainWithinLimit),
                      child: const ColoredBox(color: projectedColor),
                    ),
                    if (projectedOverLimit > 0)
                      Positioned(
                        left: widthFor(carryoverLimit),
                        top: 0,
                        bottom: 0,
                        width: widthFor(projectedOverLimit),
                        child: ColoredBox(color: errorColor),
                      ),
                    if (limitPosition < 1)
                      Positioned(
                        left: widthFor(carryoverLimit) - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            const Text('0'),
            const Spacer(),
            Text(_format(carryoverLimit)),
            if (scaleMaximum > carryoverLimit) ...[
              const Spacer(),
              Text(_format(scaleMaximum)),
            ],
          ],
        ),
        if (projectedOverLimit > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 17, color: errorColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${_format(projectedOverLimit)} hours projected over the carryover limit',
                  style: TextStyle(color: errorColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const _LeaveBarKey(color: currentColor, label: 'Current'),
            const SizedBox(width: 12),
            const _LeaveBarKey(color: projectedColor, label: 'Projected'),
            const SizedBox(width: 12),
            _LeaveBarKey(color: errorColor, label: 'Over 240'),
          ],
        ),
      ],
    );
  }
}

class _LeaveBarKey extends StatelessWidget {
  const _LeaveBarKey({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _CompactSickLeaveRow extends StatelessWidget {
  const _CompactSickLeaveRow({required this.current, required this.projected});

  final double current;
  final double projected;

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(
            child: Text('Sick leave', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('Current  ${_format(current)}h'),
          const SizedBox(width: 14),
          Text(
            'Projected  ${_format(projected)}h',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: projected < 0
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      );
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
