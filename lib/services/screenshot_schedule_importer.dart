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
        final textParsed = parseRecognizedText(recognized.text);

        // Spatial parsing is preferred for the WMT 7-column table. Merge in
        // text-only results only for dates the grid did not recover.
        if (spatial.isNotEmpty) {
          final byDay = <String, DatedShift>{for (final s in spatial) _dateKey(s.date): s};
          for (final s in textParsed.$1) {
            byDay.putIfAbsent(_dateKey(s.date), () => s);
          }
          final merged = byDay.values.toList();
          allShifts.addAll(merged);
          unrecognized.addAll(_spatialUnrecognized(recognized, merged));
          unrecognized.addAll(textParsed.$2);
        } else {
          allShifts.addAll(textParsed.$1);
          unrecognized.addAll(textParsed.$2);
        }
      }
      final byDay = <String, DatedShift>{};
      for (final shift in allShifts) {
        byDay[_dateKey(shift.date)] = shift;
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

    // WMT pay periods always start on Sunday and contain two 7-day rows.
    // Recover the Sunday anchor from any OCR-recognized date. This avoids
    // pairing a shift with an arbitrary nearby date when OCR misses cells.
    final anchors = dates.map((entry) {
      final d = entry.$2;
      final daysSinceSunday = d.weekday % 7;
      return DateTime(d.year, d.month, d.day).subtract(Duration(days: daysSinceSunday));
    }).toList()..sort();
    final start = anchors.first;

    // Fit the seven column centers from date positions + known weekdays.
    final xSamples = <(int, double)>[];
    final rowYSamples = <int, List<double>>{0: <double>[], 1: <double>[]};
    for (final entry in dates) {
      final dayOffset = DateTime(entry.$2.year, entry.$2.month, entry.$2.day).difference(start).inDays;
      if (dayOffset < 0 || dayOffset > 13) continue;
      final column = dayOffset % 7;
      final row = dayOffset ~/ 7;
      xSamples.add((column, entry.$1.centerX));
      rowYSamples[row]!.add(entry.$1.centerY);
    }
    if (xSamples.length < 2) return const [];

    final meanCol = xSamples.map((e) => e.$1.toDouble()).reduce((a, b) => a + b) / xSamples.length;
    final meanX = xSamples.map((e) => e.$2).reduce((a, b) => a + b) / xSamples.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (final sample in xSamples) {
      final dc = sample.$1 - meanCol;
      numerator += dc * (sample.$2 - meanX);
      denominator += dc * dc;
    }
    if (denominator == 0) return const [];
    final columnSpacing = numerator / denominator;
    if (columnSpacing.abs() < 20) return const [];
    final firstColumnX = meanX - columnSpacing * meanCol;

    double? mean(List<double> values) => values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
    var row0Y = mean(rowYSamples[0]!);
    var row1Y = mean(rowYSamples[1]!);
    if (row0Y == null && row1Y == null) return const [];
    // If OCR only found dates in one row, infer the other row from the shift
    // bands. The WMT rows are adjacent and have very similar cell heights.
    if (row0Y == null) row0Y = row1Y! - 55;
    if (row1Y == null) row1Y = row0Y + 55;
    final rowBoundary = (row0Y + row1Y) / 2;

    final resultByDay = <String, DatedShift>{};
    for (final shiftEntry in shifts) {
      final item = shiftEntry.$1;
      final rawColumn = (item.centerX - firstColumnX) / columnSpacing;
      final column = rawColumn.round();
      if (column < 0 || column > 6 || (rawColumn - column).abs() > 0.48) continue;

      final row = item.centerY < rowBoundary ? 0 : 1;
      final date = start.add(Duration(days: row * 7 + column));

      // A shift should sit below its row's date text and not wander into a
      // neighboring table/header/footer region.
      final dateRowY = row == 0 ? row0Y : row1Y;
      final verticalGap = item.centerY - dateRowY;
      if (verticalGap < 3 || verticalGap > 65) continue;

      final key = _dateKey(date);
      final existing = resultByDay[key];
      if (existing == null) {
        resultByDay[key] = DatedShift(date: date, shift: shiftEntry.$2);
      }
    }
    return resultByDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  List<String> _spatialUnrecognized(RecognizedText recognized, List<DatedShift> parsed) {
    final parsedRaw = parsed.map((e) => e.shift.raw.toUpperCase()).toSet();
    final parsedDates = parsed.map((e) => _dateKey(e.date)).toSet();
    final unresolved = <String>[];
    final recognizedDates = <String, DateTime>{};

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final text = element.text.trim();
          if (text.isEmpty) continue;
          final date = _findDate(text);
          if (date != null) {
            recognizedDates[_dateKey(date)] = date;
            continue;
          }
          final shift = _findShift(text);
          if (shift != null && !parsedRaw.contains(shift.raw.toUpperCase())) unresolved.add(text);
        }
      }
    }

    final missingDates = recognizedDates.entries.where((entry) => !parsedDates.contains(entry.key)).map((entry) => entry.value).toList()..sort();
    for (final date in missingDates) {
      unresolved.add('No shift recognized for ${date.month}/${date.day}/${date.year}');
    }
    return unresolved.toSet().toList();
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

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
    final normalized = line.replaceAll('O', '0').replaceAll('o', '0').replaceAll('Š', 'S').replaceAll('š', 's').replaceAll('—', '-').replaceAll('–', '-');
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
