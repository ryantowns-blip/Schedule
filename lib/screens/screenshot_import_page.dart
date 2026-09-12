import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/dated_shift.dart';
import '../services/pdf_schedule_import_service.dart';
import '../services/schedule_parser.dart';
import '../services/screenshot_schedule_importer.dart';

class ScheduleScreenshotReviewResult {
  const ScheduleScreenshotReviewResult({
    required this.shifts,
    required this.sourceImages,
    required this.deleteSourceImages,
  });

  final List<DatedShift> shifts;
  final List<XFile> sourceImages;
  final bool deleteSourceImages;
}

class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({super.key});

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _picker = ImagePicker();
  final _importer = const ScreenshotScheduleImporter();
  final _pdfRenderer = const PdfScheduleImportService();
  final _parser = const ScheduleParser();

  List<XFile> _images = const [];
  List<String> _analysisPaths = const [];
  List<String> _temporaryPdfImages = const [];
  String? _pdfFileName;
  ScreenshotImportResult? _result;
  List<DatedShift> _reviewedShifts = const [];
  bool _busy = false;
  bool _reviewedWarnings = false;
  bool _deleteSourceScreenshots = false;
  String? _error;

  bool get _usingPdf => _pdfFileName != null;

  @override
  void dispose() {
    if (_temporaryPdfImages.isNotEmpty) {
      unawaited(_pdfRenderer.deleteTemporaryImages(_temporaryPdfImages));
    }
    super.dispose();
  }

  Future<void> _clearTemporaryPdfImages() async {
    final paths = _temporaryPdfImages;
    _temporaryPdfImages = const [];
    if (paths.isNotEmpty) await _pdfRenderer.deleteTemporaryImages(paths);
  }

  void _resetReviewState() {
    _result = null;
    _reviewedShifts = const [];
    _reviewedWarnings = false;
    _deleteSourceScreenshots = false;
    _error = null;
  }

  Future<void> _pickScreenshots() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty) return;
    await _clearTemporaryPdfImages();
    if (!mounted) return;
    setState(() {
      _images = images;
      _analysisPaths = images.map((e) => e.path).toList();
      _pdfFileName = null;
      _resetReviewState();
    });
    await _analyze();
  }

  Future<void> _pickPdf() async {
    if (_busy) return;
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
    );
    if (selected == null || selected.files.isEmpty) return;
    final file = selected.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      setState(() => _error = 'The selected PDF could not be opened from this device.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _reviewedShifts = const [];
      _reviewedWarnings = false;
    });

    try {
      await _clearTemporaryPdfImages();
      final renderedPages = await _pdfRenderer.renderToTemporaryImages(path);
      if (!mounted) return;
      setState(() {
        _images = const [];
        _analysisPaths = renderedPages;
        _temporaryPdfImages = renderedPages;
        _pdfFileName = file.name;
        _deleteSourceScreenshots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not prepare the selected PDF: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    await _analyze();
  }

  Future<void> _analyze() async {
    if (_analysisPaths.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _importer.importFiles(_analysisPaths);
      if (!mounted) return;
      setState(() {
        _result = result;
        _reviewedShifts = List<DatedShift>.from(result.shifts);
        _reviewedWarnings = result.unrecognizedLines.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _usingPdf
          ? 'Could not read the selected PDF: $e'
          : 'Could not read the selected screenshots: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime value) => '${value.month}/${value.day}/${value.year}';

  Future<void> _editEntry(int index) async {
    final current = _reviewedShifts[index];
    var selectedDate = current.date;
    final shiftController = TextEditingController(text: current.shift.raw);
    String? validationError;

    final updated = await showDialog<DatedShift>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review Schedule Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(selectedDate.year - 1),
                    lastDate: DateTime(selectedDate.year + 2),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date(selectedDate)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: shiftController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Shift code',
                  hintText: '0500L, X, HL, A<0500>',
                  errorText: validationError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('The shift must match a supported ATC Schedule Manager code before it can be saved.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final parsed = _parser.parse(shiftController.text.trim());
                  Navigator.of(context).pop(DatedShift(date: selectedDate, shift: parsed));
                } catch (_) {
                  setDialogState(() => validationError = 'Shift code not recognized');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    shiftController.dispose();
    if (updated == null || !mounted) return;
    setState(() {
      final copy = List<DatedShift>.from(_reviewedShifts);
      copy[index] = updated;
      copy.sort((a, b) => a.date.compareTo(b.date));
      _reviewedShifts = copy;
    });
  }

  void _removeEntry(int index) {
    setState(() {
      final copy = List<DatedShift>.from(_reviewedShifts)..removeAt(index);
      _reviewedShifts = copy;
    });
  }

  void _finishImport() {
    Navigator.of(context).pop(
      ScheduleScreenshotReviewResult(
        shifts: List<DatedShift>.from(_reviewedShifts),
        sourceImages: List<XFile>.from(_images),
        deleteSourceImages: _deleteSourceScreenshots,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unresolved = _result?.unrecognizedLines ?? const <String>[];
    final canImport = _reviewedShifts.isNotEmpty && (unresolved.isEmpty || _reviewedWarnings);

    return Scaffold(
      appBar: AppBar(title: const Text('Import Schedule')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Screenshots are the quickest option. You can also import a PDF saved from WMT. Everything is processed locally on this device.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _pickScreenshots,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_images.isEmpty ? 'Import Screenshots' : 'Choose Different Screenshots'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Import PDF'),
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${_images.length} screenshot${_images.length == 1 ? '' : 's'} selected'),
            ],
            if (_pdfFileName != null) ...[
              const SizedBox(height: 10),
              Text('PDF selected: $_pdfFileName (${_analysisPaths.length} page${_analysisPaths.length == 1 ? '' : 's'})'),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 10),
              Text(_usingPdf ? 'Preparing and reading PDF…' : 'Reading screenshots…', textAlign: TextAlign.center),
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
                          '${_reviewedShifts.length} schedule entr${_reviewedShifts.length == 1 ? 'y' : 'ies'} recognized${unresolved.isEmpty ? '.' : ', with ${unresolved.length} line${unresolved.length == 1 ? '' : 's'} needing review.'}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('Recognized entries', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (var i = 0; i < _reviewedShifts.length; i++)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(_date(_reviewedShifts[i].date)),
                    subtitle: Text(_reviewedShifts[i].shift.raw),
                    trailing: Wrap(
                      spacing: 2,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          onPressed: () => _editEntry(i),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _removeEntry(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              if (unresolved.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Needs review', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text('OCR found schedule-like text that it could not safely turn into an entry. Review these lines before importing.'),
                        const SizedBox(height: 8),
                        for (final line in unresolved.take(12))
                          Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('• $line')),
                        if (unresolved.length > 12)
                          Text('…and ${unresolved.length - 12} more line${unresolved.length - 12 == 1 ? '' : 's'}'),
                      ],
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reviewedWarnings,
                  onChanged: (value) => setState(() => _reviewedWarnings = value ?? false),
                  title: const Text('I reviewed the unrecognized text'),
                  subtitle: const Text('Required before importing when OCR reports unresolved schedule-like text.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 8),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Import diagnostics (temporary)'),
                  subtitle: const Text('Open and copy this when schedule recognition is incomplete.'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _result!.diagnostics));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Import diagnostics copied')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy diagnostics'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _result!.diagnostics,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_usingPdf) ...[
                const SizedBox(height: 8),
                Card(
                  child: CheckboxListTile(
                    value: _deleteSourceScreenshots,
                    onChanged: (value) => setState(() => _deleteSourceScreenshots = value ?? false),
                    title: const Text('Delete source screenshots after import'),
                    subtitle: const Text(
                      'Optional. After the schedule is saved, Lite will request photo-library access and the phone may ask you to confirm deletion. Images are deleted only when filename and file size uniquely match the screenshots you selected.',
                    ),
                    secondary: const Icon(Icons.delete_sweep_outlined),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: canImport ? _finishImport : null,
                icon: const Icon(Icons.check),
                label: Text('Import ${_reviewedShifts.length} Entries'),
              ),
              if (_reviewedShifts.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _usingPdf
                      ? 'No valid schedule entries were recognized. Try a PDF exported directly from WMT or use screenshots instead.'
                      : 'No valid schedule entries were recognized. Try screenshots that clearly show both the dates and shift codes.',
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
