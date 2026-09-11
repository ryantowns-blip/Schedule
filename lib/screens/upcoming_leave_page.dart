import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_display_settings.dart';
import '../models/upcoming_leave.dart';
import '../services/leave_calendar_service.dart';
import '../services/screenshot_leave_importer.dart';

class UpcomingLeavePage extends StatefulWidget {
  const UpcomingLeavePage({super.key, required this.displaySettings});

  final ScheduleDisplaySettings displaySettings;

  @override
  State<UpcomingLeavePage> createState() => _UpcomingLeavePageState();
}

class _UpcomingLeavePageState extends State<UpcomingLeavePage> {
  static const _entriesKey = 'screenshot_leave_entries_v1';
  static const _updatedKey = 'screenshot_leave_updated_at';

  final _picker = ImagePicker();
  final _importer = const ScreenshotLeaveImporter();
  final _calendar = LeaveCalendarService();

  List<UpcomingLeaveEntry> _entries = const [];
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _importing = false;
  bool _syncing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_entriesKey) ?? const <String>[];
    final updated = prefs.getString(_updatedKey);
    final entries = <UpcomingLeaveEntry>[];
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final date = DateTime.tryParse(map['date'] as String? ?? '');
        if (date == null) continue;
        entries.add(UpcomingLeaveEntry(
          date: date,
          type: map['type'] as String? ?? 'Annual',
          status: map['status'] as String? ?? 'Pending',
        ));
      } catch (_) {}
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _lastUpdated = updated == null ? null : DateTime.tryParse(updated);
      _loading = false;
    });
  }

  Future<bool> _reviewLeaveImport(ScreenshotLeaveImportResult result) async {
    var reviewedWarnings = result.unrecognizedLines.isEmpty;
    final approved = result.entries.where((entry) => entry.isApproved).length;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Review Leave Import'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result.entries.length} leave entr${result.entries.length == 1 ? 'y' : 'ies'} recognized, including $approved approved.',
                      ),
                      const SizedBox(height: 12),
                      for (final entry in result.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${_date(entry.date)}  •  ${entry.type}  •  ${entry.status}'),
                              ),
                            ],
                          ),
                        ),
                      if (result.unrecognizedLines.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Needs review',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('OCR found leave-like text it could not safely match:'),
                        const SizedBox(height: 6),
                        for (final line in result.unrecognizedLines.take(10))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $line'),
                          ),
                        if (result.unrecognizedLines.length > 10)
                          Text('…and ${result.unrecognizedLines.length - 10} more line${result.unrecognizedLines.length - 10 == 1 ? '' : 's'}'),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: reviewedWarnings,
                          onChanged: (value) => setDialogState(() => reviewedWarnings = value ?? false),
                          title: const Text('I reviewed the unrecognized text'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: result.entries.isEmpty || !reviewedWarnings
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('Save Leave'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _importScreenshots() async {
    if (_importing) return;
    final images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() {
      _importing = true;
      _message = null;
    });
    try {
      final result = await _importer.importFiles(images.map((e) => e.path).toList());
      if (!mounted) return;

      final save = await _reviewLeaveImport(result);
      if (!mounted || !save) return;

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _entriesKey,
        result.entries
            .map((entry) => jsonEncode({
                  'date': entry.date.toIso8601String(),
                  'type': entry.type,
                  'status': entry.status,
                }))
            .toList(),
      );
      await prefs.setString(_updatedKey, now.toIso8601String());

      if (!mounted) return;
      setState(() {
        _entries = result.entries;
        _lastUpdated = now;
        _message = 'Imported ${result.entries.length} leave entr${result.entries.length == 1 ? 'y' : 'ies'} from ${images.length} screenshot${images.length == 1 ? '' : 's'}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Could not read leave screenshots: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _syncApproved() async {
    final approved = _entries.where((entry) => entry.isApproved).toList();
    if (approved.isEmpty || _syncing) return;
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final color = widget.displaySettings.annualLeaveCalendarColor ?? const Color(0xFFD8F3DC);
      final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      final result = await _calendar.syncApprovedLeave(entries: approved, colorHex: hex);
      if (!mounted) return;
      setState(() => _message = 'Calendar sync complete: ${result.created} added, ${result.skipped} already present.');
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
            tooltip: 'Import leave screenshots',
            onPressed: _importing ? null : _importScreenshots,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                children: [
                  if (_message != null) ...[
                    Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
                    const SizedBox(height: 10),
                  ],
                  if (_importing) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 10),
                    const Text('Reading leave screenshots on this device…', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                  if (_entries.isEmpty) ...[
                    const SizedBox(height: 50),
                    Icon(Icons.beach_access_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('No upcoming leave saved', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('Take screenshot(s) of the My Leave page, then import them here. Images are processed locally on this device.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _importing ? null : _importScreenshots,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Import Leave Screenshots'),
                    ),
                  ] else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Text('$approvedCount approved leave day${approvedCount == 1 ? '' : 's'}. Existing Annual Leave calendar entries are checked before anything is added.'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in _entries)
                      Card(
                        child: ListTile(
                          dense: true,
                          title: Text(_date(entry.date)),
                          subtitle: Text(entry.type),
                          trailing: Text(entry.status, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: approvedCount == 0 || _syncing ? null : _syncApproved,
                      icon: _syncing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.event_available_outlined),
                      label: Text('Add Approved Leave to Calendar ($approvedCount)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _importing ? null : _importScreenshots,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Import Updated Leave Screenshots'),
                    ),
                    if (_lastUpdated != null) ...[
                      const SizedBox(height: 10),
                      Text('Leave data last updated: ${_updatedText(_lastUpdated!)}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
