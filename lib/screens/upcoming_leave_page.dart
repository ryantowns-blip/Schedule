import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_display_settings.dart';
import '../models/upcoming_leave.dart';
import '../services/leave_calendar_service.dart';
import '../services/screenshot_cleanup_service.dart';
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
  final _cleanup = const ScreenshotCleanupService();
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final date = DateTime.tryParse(map['date'] as String? ?? '');
        if (date == null) continue;
        if (DateTime(date.year, date.month, date.day).isBefore(today)) continue;
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

  Future<UpcomingLeaveEntry?> _editLeaveEntry(UpcomingLeaveEntry entry) async {
    var date = entry.date;
    var type = entry.type;
    var status = entry.status;
    const types = ['Annual', 'Holiday', 'Sick'];
    const statuses = ['Approved', 'Pending', 'Denied', 'Cancelled'];
    if (!types.contains(type)) type = 'Annual';
    if (!statuses.contains(status)) status = 'Pending';

    return showDialog<UpcomingLeaveEntry>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Leave Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Date'),
                subtitle: Text(_date(date)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(date.year - 2),
                    lastDate: DateTime(date.year + 5),
                  );
                  if (selected != null) setDialogState(() => date = selected);
                },
              ),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Leave type'),
                items: [for (final value in types) DropdownMenuItem(value: value, child: Text(value))],
                onChanged: (value) {
                  if (value != null) setDialogState(() => type = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final value in statuses) DropdownMenuItem(value: value, child: Text(value))],
                onChanged: (value) {
                  if (value != null) setDialogState(() => status = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                UpcomingLeaveEntry(date: date, type: type, status: status),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_LeaveReviewDecision?> _reviewLeaveImport(ScreenshotLeaveImportResult result) async {
    var reviewedWarnings = result.unrecognizedLines.isEmpty;
    var deleteSourceScreenshots = false;
    final entries = List<UpcomingLeaveEntry>.from(result.entries);

    return showDialog<_LeaveReviewDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final approved = entries.where((entry) => entry.isApproved).length;
          return AlertDialog(
            title: const Text('Review Leave Import'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entries.length} leave entr${entries.length == 1 ? 'y' : 'ies'} ready, including $approved approved.'),
                    const SizedBox(height: 8),
                    const Text('Tap an entry to correct the date, leave type, or status before saving.'),
                    const SizedBox(height: 12),
                    for (var index = 0; index < entries.length; index++)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 12, right: 4),
                          leading: const Icon(Icons.calendar_today_outlined, size: 18),
                          title: Text(_date(entries[index].date)),
                          subtitle: Text('${entries[index].type} • ${entries[index].status}'),
                          onTap: () async {
                            final edited = await _editLeaveEntry(entries[index]);
                            if (edited != null) setDialogState(() => entries[index] = edited);
                          },
                          trailing: IconButton(
                            tooltip: 'Remove entry',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setDialogState(() => entries.removeAt(index)),
                          ),
                        ),
                      ),
                    if (result.unrecognizedLines.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Needs review', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('OCR found leave-like text it could not safely match:'),
                      const SizedBox(height: 6),
                      for (final line in result.unrecognizedLines.take(10))
                        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $line')),
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
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: deleteSourceScreenshots,
                      onChanged: (value) => setDialogState(() => deleteSourceScreenshots = value ?? false),
                      title: const Text('Delete source screenshots after import'),
                      subtitle: const Text(
                        'Optional. Leave data is saved first. Lite then requests photo-library access and deletes only uniquely matched source images.',
                      ),
                      secondary: const Icon(Icons.delete_sweep_outlined),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: entries.isEmpty || !reviewedWarnings
                    ? null
                    : () => Navigator.of(context).pop(
                          _LeaveReviewDecision(
                            entries: List<UpcomingLeaveEntry>.from(entries),
                            deleteSourceImages: deleteSourceScreenshots,
                          ),
                        ),
                child: const Text('Save Leave'),
              ),
            ],
          );
        },
      ),
    );
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
      final scanned = await _importer.importFiles(images.map((e) => e.path).toList());
      final result = _importer.filterUpcoming(scanned);
      if (!mounted) return;

      final decision = await _reviewLeaveImport(result);
      if (!mounted || decision == null) return;
      final reviewedEntries = decision.entries..sort((a, b) => a.date.compareTo(b.date));

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _entriesKey,
        reviewedEntries
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
        _entries = reviewedEntries;
        _lastUpdated = now;
        _message = 'Imported ${reviewedEntries.length} reviewed leave entr${reviewedEntries.length == 1 ? 'y' : 'ies'} from ${images.length} screenshot${images.length == 1 ? '' : 's'}.';
      });

      if (decision.deleteSourceImages) {
        final cleanup = await _cleanup.deleteSourceImages(images);
        if (!mounted) return;
        setState(() {
          if (cleanup.permissionDenied) {
            _message = '${_message!} Screenshot deletion was skipped because photo-library access was not granted.';
          } else if (cleanup.deleted == cleanup.requested) {
            _message = '${_message!} Deleted ${cleanup.deleted} source screenshot${cleanup.deleted == 1 ? '' : 's'}.';
          } else {
            _message = '${_message!} Deleted ${cleanup.deleted} of ${cleanup.requested} source screenshots; unmatched or ambiguous images were left on the phone.';
          }
        });
      }
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

class _LeaveReviewDecision {
  const _LeaveReviewDecision({required this.entries, required this.deleteSourceImages});

  final List<UpcomingLeaveEntry> entries;
  final bool deleteSourceImages;
}
