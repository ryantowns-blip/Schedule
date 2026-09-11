import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/dated_shift.dart';
import '../models/parsed_shift.dart';
import 'schedule_parser.dart';

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

class _OcrItem {
  const _OcrItem(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
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

        // WMT is a 7-column table. ML Kit's plain text output often joins all
        // dates in a row and all shifts in another row, destroying the cell
        // relationship. Use OCR element coordinates first so each shift is
        // paired with the date directly above it in the same table column.
        final spatial = _parseSpatialTable(recognized);
        if (spatial.isNotEmpty) {
          allShifts.addAll(spatial);
          unrecognized.addAll(_spatialUnrecognized(recognized, spatial));
        } else {
          final parsed = parseRecognizedText(recognized.text);
          allShifts.addAll(parsed.$1);
          unrecognized.addAll(parsed.$2);
        }
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
        unrecognizedLines: unrecognized.toSet().toList(),
        rawText: raw.toString().trim(),
      );
    } finally {
      await recognizer.close();
    }
  }

  List<DatedShift> _parseSpatialTable(RecognizedText recognized) {
    final dates = <(_OcrItem, DateTime)>[];
    final shifts = <(_OcrItem, ParsedShift)>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final box = element.boundingBox;
          final item = _OcrItem(
            element.text.trim(),
            box.left,
            box.top,
            box.right,
            box.bottom,
          );
          final date = _findDate(item.text);
          if (date != null) dates.add((item, date));
          final shift = _findShift(item.text);
          if (shift != null) shifts.add((item, shift));
        }
      }
    }

    if (dates.length < 2 || shifts.isEmpty) return const [];

    final result = <DatedShift>[];
    for (final shiftEntry in shifts) {
      final shiftItem = shiftEntry.$1;
      final candidates = dates.where((dateEntry) {
        final dateItem = dateEntry.$1;
        final verticalGap = shiftItem.centerY - dateItem.centerY;
        final dateWidth = (dateItem.right - dateItem.left).abs();
        final horizontalGap = (shiftItem.centerX - dateItem.centerX).abs();
        // Shift must be below its date and horizontally inside roughly the
        // same WMT cell. The width-relative tolerance scales across phones.
        return verticalGap > 0 &&
            verticalGap < dateWidth * 2.2 &&
            horizontalGap < dateWidth * 0.65;
      }).toList();
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) {
        final da = (shiftItem.centerY - a.$1.centerY).abs() +
            (shiftItem.centerX - a.$1.centerX).abs();
        final db = (shiftItem.centerY - b.$1.centerY).abs() +
            (shiftItem.centerX - b.$1.centerX).abs();
        return da.compareTo(db);
      });
      result.add(DatedShift(date: candidates.first.$2, shift: shiftEntry.$2));
    }
    return result;
  }

  List<String> _spatialUnrecognized(
    RecognizedText recognized,
    List<DatedShift> parsed,
  ) {
    // Do not flag headers, pay-period numbers, or ML Kit's concatenated table
    // rows merely because they contain digits. The editable review already
    // shows every spatially paired entry. Only surface genuinely shift-like
    // tokens that were not represented by a parsed shift.
    final parsedRaw = parsed.map((e) => e.shift.raw.toUpperCase()).toSet();
    final unresolved = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final text = element.text.trim();
          if (text.isEmpty || _findDate(text) != null) continue;
          final shift = _findShift(text);
          if (shift != null && !parsedRaw.contains(shift.raw.toUpperCase())) {
            unresolved.add(text);
          }
        }
      }
    }
    return unresolved.toSet().toList();
  }

  /// Parses OCR text without requiring an image. Kept public so OCR repair
  /// rules can be regression-tested independently from ML Kit.
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
      final parsed = _tryParse('A<${annual.group(1)}>');
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
