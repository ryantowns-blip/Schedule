import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/parsed_shift.dart';
import 'schedule_parser.dart';
import 'wmt_schedule_extractor.dart';

class ScreenshotImportResult {
  const ScreenshotImportResult({
    required this.shifts,
    required this.unrecognizedLines,
    required this.rawText,
  });

  final List<DatedShift> shifts;
  final List<String> unrecognizedLines;
  final String rawText;
}

class ScreenshotScheduleImporter {
  const ScreenshotScheduleImporter({this.parser = const ScheduleParser()});

  final ScheduleParser parser;

  Future<ScreenshotImportResult> importFiles(List<String> paths) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final allShifts = <DatedShift>[];
      final unrecognized = <String>[];
      final raw = StringBuffer();

      for (final path in paths) {
        final image = InputImage.fromFilePath(path);
        final recognized = await recognizer.processImage(image);
        raw.writeln(recognized.text);
        final parsed = parseRecognizedText(recognized.text);
        allShifts.addAll(parsed.$1);
        unrecognized.addAll(parsed.$2);
      }

      final byDay = <String, DatedShift>{};
      for (final shift in allShifts) {
        final key = '${shift.date.year}-${shift.date.month}-${shift.date.day}';
        byDay[key] = shift;
      }
      final shifts = byDay.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      return ScreenshotImportResult(
        shifts: shifts,
        unrecognizedLines: unrecognized,
        rawText: raw.toString().trim(),
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Parses OCR text without requiring an image. Kept public so the WMT-specific
  /// OCR rules can be regression-tested independently from ML Kit.
  (List<DatedShift>, List<String>) parseRecognizedText(String text) {
    final shifts = <DatedShift>[];
    final unrecognized = <String>[];
    DateTime? pendingDate;

    for (final original in text.split(RegExp(r'\r?\n'))) {
      final line = original.trim();
      if (line.isEmpty) continue;

      final inlineDate = _findDate(line);
      final inlineShift = _findShift(line);
      if (inlineDate != null && inlineShift != null) {
        shifts.add(DatedShift(date: inlineDate, shift: inlineShift));
        pendingDate = null;
        continue;
      }

      if (inlineDate != null) {
        pendingDate = inlineDate;
        continue;
      }

      if (pendingDate != null && inlineShift != null) {
        shifts.add(DatedShift(date: pendingDate, shift: inlineShift));
        pendingDate = null;
        continue;
      }

      if (_looksScheduleLike(line)) unrecognized.add(line);
    }

    return (shifts, unrecognized);
  }

  DateTime? _findDate(String line) {
    final slash = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b').firstMatch(line);
    if (slash == null) return null;
    var year = int.tryParse(slash.group(3) ?? '');
    final month = int.tryParse(slash.group(1) ?? '');
    final day = int.tryParse(slash.group(2) ?? '');
    if (year == null || month == null || day == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  ParsedShift? _findShift(String line) {
    final normalized = line
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('—', '-')
        .replaceAll('–', '-');

    final annual = RegExp(r'A\s*[<\[]\s*([A-Za-z0-9$]+)\s*[>\]]', caseSensitive: false).firstMatch(normalized);
    if (annual != null) {
      final token = 'A<${annual.group(1)}>';
      final parsed = _tryParse(token);
      if (parsed != null) return parsed;
    }

    final tokens = normalized.split(RegExp(r'\s+'));
    for (final raw in tokens) {
      final token = raw.replaceAll(RegExp(r'^[^A-Za-z0-9$]+|[^A-Za-z0-9$]+$'), '');
      final parsed = _tryParse(token);
      if (parsed != null) return parsed;
    }
    return null;
  }

  ParsedShift? _tryParse(String token) {
    if (token.isEmpty) return null;
    final fixed = _repairCommonOcr(token);
    if (!RegExp(
      r'^(?:X|SL|HL|A<[^>]+>|[LSCQ$]*(?:Xtra)?\d{3,4}[LSCQ$]*(?:Xtra)?|Xt\d{3,4}ra)$',
      caseSensitive: false,
    ).hasMatch(fixed)) return null;
    try {
      return parser.parse(fixed);
    } catch (_) {
      return null;
    }
  }

  String _repairCommonOcr(String token) {
    var value = token.trim();
    if (RegExp(r'\d').hasMatch(value)) {
      value = value.replaceAll('O', '0').replaceAll('o', '0');
    }
    return value;
  }

  bool _looksScheduleLike(String line) {
    return RegExp(r'\d{3,4}|\b(?:X|SL|HL)\b|A\s*[<\[]', caseSensitive: false).hasMatch(line);
  }
}
