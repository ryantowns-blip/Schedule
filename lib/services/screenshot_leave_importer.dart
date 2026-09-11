import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/upcoming_leave.dart';

class ScreenshotLeaveImportResult {
  const ScreenshotLeaveImportResult({required this.entries, required this.unrecognizedLines, required this.rawText});
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
        final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
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
      final output = byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
      return ScreenshotLeaveImportResult(entries: output, unrecognizedLines: unresolved, rawText: raw.toString().trim());
    } finally {
      await recognizer.close();
    }
  }

  /// Parses OCR text without requiring an image. WMT's narrow table borders are
  /// commonly recognized as |, l, I, or doubled punctuation immediately beside
  /// a date/status, so parsing deliberately does not require word boundaries
  /// around the date and tolerates those separators.
  (List<UpcomingLeaveEntry>, List<String>) parseRecognizedText(String text) {
    final entries = <UpcomingLeaveEntry>[];
    final unresolved = <String>[];
    DateTime? pendingDate;
    String? pendingType;
    String? pendingLine;

    void clearPending() { pendingDate = null; pendingType = null; pendingLine = null; }
    void flushPendingForReview() {
      final line = pendingLine;
      if (line != null && line.isNotEmpty && !unresolved.contains(line)) unresolved.add(line);
      clearPending();
    }

    for (final original in text.split(RegExp(r'\r?\n'))) {
      final line = original.trim();
      if (line.isEmpty) continue;
      final date = _findDate(line);
      final type = _findType(line);
      final status = _findStatus(line);

      if (date != null && status != null) {
        if (pendingDate != null) flushPendingForReview();
        entries.add(UpcomingLeaveEntry(date: date, type: type ?? 'Annual', status: status));
        continue;
      }
      if (date != null) {
        if (pendingDate != null) flushPendingForReview();
        pendingDate = date; pendingType = type; pendingLine = line;
        continue;
      }
      final resolvedPendingDate = pendingDate;
      if (resolvedPendingDate != null && status != null) {
        entries.add(UpcomingLeaveEntry(date: resolvedPendingDate, type: type ?? pendingType ?? 'Annual', status: status));
        clearPending();
        continue;
      }
      if (_looksLeaveLike(line)) unresolved.add(line);
    }
    if (pendingDate != null) flushPendingForReview();
    return (entries, unresolved);
  }

  DateTime? _findDate(String line) {
    // No \b anchors: OCR often emits "11/15/2026l" where the trailing l is a
    // misread vertical table border. Accept leading zeros and either / or -.
    final match = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})').firstMatch(line);
    if (match == null) return null;
    final month = int.tryParse(match.group(1) ?? '');
    final day = int.tryParse(match.group(2) ?? '');
    var year = int.tryParse(match.group(3) ?? '');
    if (month == null || day == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  String? _findStatus(String line) {
    final lower = line.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (lower.contains('approved')) return 'Approved';
    if (lower.contains('denied') || lower.contains('disapproved')) return 'Denied';
    if (lower.contains('pending')) return 'Pending';
    if (lower.contains('cancelled') || lower.contains('canceled')) return 'Cancelled';
    return null;
  }

  String? _findType(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('annual') || RegExp(r'(^|[^a-z])AL([^a-z]|$)', caseSensitive: false).hasMatch(line)) return 'Annual';
    if (lower.contains('holiday') || RegExp(r'(^|[^a-z])HL([^a-z]|$)', caseSensitive: false).hasMatch(line)) return 'Holiday';
    if (lower.contains('sick') || RegExp(r'(^|[^a-z])SL([^a-z]|$)', caseSensitive: false).hasMatch(line)) return 'Sick';
    return null;
  }

  bool _looksLeaveLike(String line) => _findDate(line) != null || _findStatus(line) != null || _findType(line) != null;
}
