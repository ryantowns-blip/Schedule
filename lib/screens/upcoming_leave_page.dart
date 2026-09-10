import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_display_settings.dart';
import '../models/upcoming_leave.dart';
import '../services/leave_calendar_service.dart';
import '../services/wmt_leave_extractor.dart';
import 'update_leave_page.dart';

class UpcomingLeavePage extends StatefulWidget {
  const UpcomingLeavePage({super.key, required this.displaySettings});

  final ScheduleDisplaySettings displaySettings;

  @override
  State<UpcomingLeavePage> createState() => _UpcomingLeavePageState();
}

class _UpcomingLeavePageState extends State<UpcomingLeavePage> {
  static const _htmlKey = 'saved_wmt_my_leave_html';
  static const _updatedKey = 'saved_wmt_my_leave_updated_at';

  final _extractor = const WmtLeaveExtractor();
  final _calendar = LeaveCalendarService();
  List<UpcomingLeaveEntry> _entries = const [];
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _syncing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final html = prefs.getString(_htmlKey);
    final updated = prefs.getString(_updatedKey);
    if (!mounted) return;
    setState(() {
      _entries = html == null ? const [] : _extractor.extract(html);
      _lastUpdated = updated == null ? null : DateTime.tryParse(updated);
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final html = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const UpdateLeavePage()),
    );
    if (!mounted || html == null || html.isEmpty) return;

    final entries = _extractor.extract(html);
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_htmlKey, html);
    await prefs.setString(_updatedKey, now.toIso8601String());

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _lastUpdated = now;
      _message = entries.isEmpty
          ? 'My Leave was refreshed, but no future Annual leave entries were found.'
          : 'Upcoming leave refreshed.';
    });
  }

  Future<void> _syncApproved() async {
    final approved = _entries.where((entry) => entry.isApproved).toList();
    if (approved.isEmpty || _syncing) return;
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final color = widget.displaySettings.annualLeaveColor ?? const Color(0xFFD8F3DC);
      final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      final result = await _calendar.syncApprovedLeave(entries: approved, colorHex: hex);
      if (!mounted) return;
      setState(() {
        _message = 'Calendar sync complete: ${result.created} added, ${result.skipped} already present.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Could not sync leave to calendar: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _date(DateTime date) => '${date.month}/${date.day}/${date.year}';

  String _updatedText(DateTime date) {
    final hour = date.hour == 0 ? 12 : date.hour > 12 ? date.hour - 12 : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.month}/${date.day}/${date.year} at $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final approvedCount = _entries.where((entry) => entry.isApproved).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming Leave'),
        actions: [
          IconButton(
            tooltip: 'Refresh from WMT',
            onPressed: _refresh,
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
                  if (_message != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_entries.isEmpty) ...[
                    const SizedBox(height: 60),
                    Icon(
                      Icons.beach_access_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No upcoming leave saved',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Refresh from WMT to read future Annual leave from Views → My Leave. Sick leave and past dates are ignored.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.sync),
                      label: const Text('Get Upcoming Leave'),
                    ),
                  ] else ...[
                    for (final entry in _entries)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            entry.isApproved ? Icons.check_circle_outline : Icons.pending_outlined,
                          ),
                          title: Text(_date(entry.date)),
                          subtitle: Text('Annual Leave • ${entry.status}'),
                          trailing: entry.isApproved
                              ? const Chip(label: Text('Approved'))
                              : Chip(label: Text(entry.status)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: approvedCount == 0 || _syncing ? null : _syncApproved,
                      icon: _syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.event_available_outlined),
                      label: Text('Add Approved Leave to Calendar ($approvedCount)'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh from WMT'),
                    ),
                    if (_lastUpdated != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Leave data last updated: ${_updatedText(_lastUpdated!)}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
