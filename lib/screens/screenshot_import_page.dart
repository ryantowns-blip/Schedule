import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/screenshot_schedule_importer.dart';
import '../services/wmt_schedule_extractor.dart';

class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({super.key});

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _picker = ImagePicker();
  final _importer = const ScreenshotScheduleImporter();
  List<XFile> _images = const [];
  ScreenshotImportResult? _result;
  bool _busy = false;
  String? _error;

  Future<void> _pickScreenshots() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty) return;
    setState(() {
      _images = images;
      _result = null;
      _error = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    if (_images.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _importer.importFiles(_images.map((e) => e.path).toList());
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not read the selected screenshots: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime value) => '${value.month}/${value.day}/${value.year}';

  @override
  Widget build(BuildContext context) {
    final shifts = _result?.shifts ?? const <DatedShift>[];
    final unresolved = _result?.unrecognizedLines ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Import Schedule Screenshots')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Select one or more screenshots of your schedule. The images are read on this device and are not uploaded by ATC Schedule Manager.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _pickScreenshots,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_images.isEmpty ? 'Select Screenshots' : 'Choose Different Screenshots'),
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${_images.length} screenshot${_images.length == 1 ? '' : 's'} selected'),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 10),
              const Text('Reading screenshots…', textAlign: TextAlign.center),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
            if (_result != null && !_busy) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${shifts.length} schedule entr${shifts.length == 1 ? 'y' : 'ies'} recognized${unresolved.isEmpty ? '.' : ', with ${unresolved.length} line${unresolved.length == 1 ? '' : 's'} needing review.'}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final entry in shifts)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(_date(entry.date)),
                    subtitle: Text(entry.shift.raw),
                    trailing: const Icon(Icons.check_circle_outline),
                  ),
                ),
              if (unresolved.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Needs review', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final line in unresolved.take(12))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(line),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: shifts.isEmpty ? null : () => Navigator.of(context).pop(shifts),
                icon: const Icon(Icons.check),
                label: Text('Import ${shifts.length} Entries'),
              ),
              if (shifts.isEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'No valid schedule entries were recognized. Try screenshots that clearly show both the dates and shift codes.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
