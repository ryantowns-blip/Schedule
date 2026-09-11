import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/upcoming_leave.dart';

class ScreenshotLeaveImportResult {
  const ScreenshotLeaveImportResult({
    required this.entries,
    required this.unrecognizedLines,
    required this.rawText,
  });

  final List<UpcomingLeaveEntry> entries;
  final List<String> unrecognizedLines;
  final String rawText;
}

class ScreenshotLeaveImporter {
  const ScreenshotLeaveImporter();

  Future<ScreenshotLeaveImportResult> importFiles(List<String> paths) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final entries = <UpcomingLeaveEntry>[];
      final unresolved = <String>[];
      final raw = StringBuffer();

      for (final path in paths) {
        final image = InputImage.fromFilePath(path);
        final recognized = await recognizer.processImage(image);
        raw.writeln(recognized.text);
        final parsed = parseRecognizedText(recognized.text);
        entries.addAll(parsed.$1);
        unresolved.addAll(parsed.$2);
      }

      final byDate = <String, UpcomingLeaveEntry>{};
      for (final entry in entries) {
        final key = '${entry.date.year}-${entry.date.month}-${entry.date.day}-${entry.type.toLowerCase()}';
        byDate[key] = entry;
      }
      final output = byDate.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      return ScreenshotLeaveImportResult(
        entries: output,
        unrecognizedLines: unresolved,
        rawText: raw.toString().trim(),
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Parses OCR text without requiring an image, allowing regression tests for
  /// WMT My Leave layout and wording independently from ML Kit.
  (List<UpcomingLeaveEntry>, List<String>) parseRecognizedText(String text) {
    final entries = <UpcomingLeaveEntry>[];
    final unresolved = <String>[];
    DateTime? pendingDate;
    String? pendingType;

    final lines = text.split(RegExp(r'\r?\n'));
    for (final original in lines) {
      final line = original.trim();
      if (line.isEmpty) continue;

      final date = _findDate(line);
      final type = _findType(line);
      final status = _findStatus(line);

      if (date != null && status != null) {
        entries.add(UpcomingLeaveEntry(
          date: date,
          type: type ?? 'Annual',
          status: status,
        ));
        pendingDate = null;
        pendingType = null;
        continue;
      }

      if (date != null) {
        pendingDate = date;
        pendingType = type;
        continue;
      }

      if (pendingDate != null && status != null) {
        entries.add(UpcomingLeaveEntry(
          date: pendingDate,
          type: type ?? pendingType ?? 'Annual',
          status: status,
        ));
        pendingDate = null;
        pendingType = null;
        continue;
      }

      if (_looksLeaveLike(line)) unresolved.add(line);
    }

    return (entries, unresolved);
  }

  DateTime? _findDate(String line) {
    final match = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b').firstMatch(line);
    if (match == null) return null;
    final month = int.tryParse(match.group(1) ?? '');
    final day = int.tryParse(match.group(2) ?? '');
    var year = int.tryParse(match.group(3) ?? '');
    if (month == null || day == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  String? _findStatus(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('approved')) return 'Approved';
    if (lower.contains('denied') || lower.contains('disapproved')) return 'Denied';
    if (lower.contains('pending')) return 'Pending';
    if (lower.contains('cancelled') || lower.contains('canceled')) return 'Cancelled';
    return null;
  }

  String? _findType(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('annual') || RegExp(r'\bAL\b', caseSensitive: false).hasMatch(line)) return 'Annual';
    if (lower.contains('holiday') || RegExp(r'\bHL\b', caseSensitive: false).hasMatch(line)) return 'Holiday';
    if (lower.contains('sick') || RegExp(r'\bSL\b', caseSensitive: false).hasMatch(line)) return 'Sick';
    return null;
  }

  bool _looksLeaveLike(String line) {
    return _findDate(line) != null || _findStatus(line) != null || _findType(line) != null;
  }
}
