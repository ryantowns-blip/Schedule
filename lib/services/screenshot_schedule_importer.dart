import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/dated_shift.dart';
import '../models/parsed_shift.dart';
import 'schedule_parser.dart';

class ScreenshotImportResult {
  const ScreenshotImportResult({required this.shifts, required this.unrecognizedLines, required this.rawText});
  final List<DatedShift> shifts;
  final List<String> unrecognizedLines;
  final String rawText;
}

class _OcrItem {
  const _OcrItem(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => (right - left).abs();
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
        final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
        raw.writeln(recognized.text);
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
        byDay['${shift.date.year}-${shift.date.month}-${shift.date.day}'] = shift;
      }
      final shifts = byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
      return ScreenshotImportResult(shifts: shifts, unrecognizedLines: unrecognized.toSet().toList(), rawText: raw.toString().trim());
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
          final item = _OcrItem(element.text.trim(), box.left, box.top, box.right, box.bottom);
          final date = _findDate(item.text);
          if (date != null) dates.add((item, date));
          final shift = _findShift(item.text);
          if (shift != null) shifts.add((item, shift));
        }
      }
    }
    if (dates.length < 2 || shifts.isEmpty) return const [];

    // The earlier implementation limited vertical distance using the printed
    // date's width. Real WMT screenshots vary enough in zoom/font size that
    // this rejected valid cells. Instead infer the seven-column spacing from
    // neighboring date centers and pair each shift with the nearest date above
    // it in the same column. The nearest-above rule naturally selects Week 2
    // over Week 1 when the x coordinate repeats.
    final xs = dates.map((e) => e.$1.centerX).toList()..sort();
    final gaps = <double>[];
    for (var i = 1; i < xs.length; i++) {
      final gap = xs[i] - xs[i - 1];
      if (gap > 8) gaps.add(gap);
    }
    gaps.sort();
    final inferredColumnWidth = gaps.isEmpty ? 80.0 : gaps[gaps.length ~/ 2];
    final horizontalTolerance = inferredColumnWidth * 0.48;

    final result = <DatedShift>[];
    for (final shiftEntry in shifts) {
      final shiftItem = shiftEntry.$1;
      final candidates = dates.where((dateEntry) {
        final dateItem = dateEntry.$1;
        return shiftItem.centerY > dateItem.centerY &&
            (shiftItem.centerX - dateItem.centerX).abs() <= horizontalTolerance;
      }).toList();
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) {
        final ay = shiftItem.centerY - a.$1.centerY;
        final by = shiftItem.centerY - b.$1.centerY;
        if ((ay - by).abs() > 4) return ay.compareTo(by);
        return (shiftItem.centerX - a.$1.centerX).abs().compareTo((shiftItem.centerX - b.$1.centerX).abs());
      });
      result.add(DatedShift(date: candidates.first.$2, shift: shiftEntry.$2));
    }
    return result;
  }

  List<String> _spatialUnrecognized(RecognizedText recognized, List<DatedShift> parsed) {
    final parsedRaw = parsed.map((e) => e.shift.raw.toUpperCase()).toSet();
    final unresolved = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final text = element.text.trim();
          if (text.isEmpty || _findDate(text) != null) continue;
          final shift = _findShift(text);
          if (shift != null && !parsedRaw.contains(shift.raw.toUpperCase())) unresolved.add(text);
        }
      }
    }
    return unresolved.toSet().toList();
  }

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
      } else if (inlineDate != null) {
        pendingDate = inlineDate;
      } else if (pendingDate != null && inlineShift != null) {
        shifts.add(DatedShift(date: pendingDate, shift: inlineShift));
        pendingDate = null;
      } else if (_looksScheduleLike(line)) {
        unrecognized.add(line);
      }
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
        .replaceAll('O', '0').replaceAll('o', '0')
        .replaceAll('Š', 'S').replaceAll('š', 's')
        .replaceAll('—', '-').replaceAll('–', '-');
    final annual = RegExp(r'A\s*[<\[]\s*([A-Za-z0-9$]+)\s*[>\]]', caseSensitive: false).firstMatch(normalized);
    if (annual != null) {
      final parsed = _tryParse('A<${annual.group(1)}>');
      if (parsed != null) return parsed;
    }
    for (final raw in normalized.split(RegExp(r'\s+'))) {
      final token = raw.replaceAll(RegExp(r'^[^A-Za-z0-9$]+|[^A-Za-z0-9$]+$'), '');
      final parsed = _tryParse(token);
      if (parsed != null) return parsed;
    }
    return null;
  }

  ParsedShift? _tryParse(String token) {
    if (token.isEmpty) return null;
    final fixed = _repairCommonOcr(token);
    if (!RegExp(r'^(?:X|SL|HL|A<[^>]+>|[LSCQ$]*(?:Xtra)?\d{3,4}[LSCQ$]*(?:Xtra)?|Xt\d{3,4}ra)$', caseSensitive: false).hasMatch(fixed)) return null;
    try { return parser.parse(fixed); } catch (_) { return null; }
  }

  String _repairCommonOcr(String token) {
    var value = token.trim().replaceAll('Š', 'S').replaceAll('š', 's');
    if (RegExp(r'\d').hasMatch(value)) value = value.replaceAll('O', '0').replaceAll('o', '0');
    return value;
  }

  bool _looksScheduleLike(String line) => RegExp(r'\d{3,4}|\b(?:X|SL|HL)\b|A\s*[<\[]', caseSensitive: false).hasMatch(line);
}
