import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/dated_shift.dart';
import '../models/parsed_shift.dart';
import 'schedule_parser.dart';

class ScreenshotImportResult {
  const ScreenshotImportResult({
    required this.shifts,
    required this.unrecognizedLines,
    required this.rawText,
    required this.diagnostics,
  });
  final List<DatedShift> shifts;
  final List<String> unrecognizedLines;
  final String rawText;
  final String diagnostics;
}

class _OcrItem {
  const _OcrItem(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
}

class _ShiftCandidate {
  const _ShiftCandidate(this.item, this.shift, {required this.fromLine});
  final _OcrItem item;
  final ParsedShift shift;
  final bool fromLine;
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
      final diagnostics = StringBuffer('ATC Schedule Manager OCR diagnostics\n');
      for (var imageIndex = 0; imageIndex < paths.length; imageIndex++) {
        final path = paths[imageIndex];
        final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
        raw.writeln(recognized.text);
        final spatial = _parseSpatialTable(recognized);
        diagnostics
          ..writeln('\n=== IMAGE ${imageIndex + 1} ===')
          ..writeln('OCR blocks: ${recognized.blocks.length}')
          ..writeln('Spatial matches: ${spatial.length}')
          ..writeln('Parser mode: ${spatial.isNotEmpty ? 'spatial grid' : 'plain-text fallback'}')
          ..writeln(_diagnosticItems(recognized))
          ..writeln('--- RAW OCR ---')
          ..writeln(recognized.text);

        // Once a WMT grid is found, its geometry is authoritative. ML Kit can
        // emit table text in a misleading reading order, so plain-text pairing
        // is only used if no usable WMT table can be reconstructed at all.
        if (spatial.isNotEmpty) {
          allShifts.addAll(spatial);
          unrecognized.addAll(_spatialUnrecognized(recognized, spatial));
        } else {
          final textParsed = parseRecognizedText(recognized.text);
          allShifts.addAll(textParsed.$1);
          unrecognized.addAll(textParsed.$2);
        }
      }
      final byDay = <String, DatedShift>{};
      for (final shift in allShifts) {
        byDay[_dateKey(shift.date)] = shift;
      }
      final shifts = byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
      return ScreenshotImportResult(
        shifts: shifts,
        unrecognizedLines: unrecognized.toSet().toList(),
        rawText: raw.toString().trim(),
        diagnostics: diagnostics.toString().trim(),
      );
    } finally {
      await recognizer.close();
    }
  }

  String _diagnosticItems(RecognizedText recognized) {
    final output = StringBuffer('--- OCR LINES (left,top,right,bottom) ---');
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        final date = _findDate(line.text);
        final shift = _findShift(line.text);
        final classification = date != null
            ? 'DATE ${_dateKey(date)}'
            : shift != null
                ? 'SHIFT ${shift.raw}'
                : _looksScheduleLike(line.text)
                    ? 'REJECTED-SCHEDULE-LIKE'
                    : 'OTHER';
        output.writeln(
          '${box.left.round()},${box.top.round()},${box.right.round()},${box.bottom.round()} '
          '[$classification] ${line.text.trim()}',
        );
      }
    }
    return output.toString();
  }

  List<DatedShift> _parseSpatialTable(RecognizedText recognized) {
    final dates = <(_OcrItem, DateTime)>[];
    final candidates = <_ShiftCandidate>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final lineBox = line.boundingBox;
        final lineItem = _OcrItem(
          line.text.trim(),
          lineBox.left,
          lineBox.top,
          lineBox.right,
          lineBox.bottom,
        );
        // ML Kit sometimes keeps a complete date as the line text while
        // splitting its elements into fragments such as "9/" and "6/2026".
        // Keep both representations; duplicates are harmless and are reduced
        // to medians below.
        final lineDate = _findDate(lineItem.text);
        if (lineDate != null) dates.add((lineItem, lineDate));
        final lineShift = _findShift(lineItem.text);
        if (lineShift != null) {
          candidates.add(_ShiftCandidate(lineItem, lineShift, fromLine: true));
        }

        for (final element in line.elements) {
          final box = element.boundingBox;
          final item = _OcrItem(element.text.trim(), box.left, box.top, box.right, box.bottom);
          final date = _findDate(item.text);
          if (date != null) dates.add((item, date));
          final shift = _findShift(item.text);
          if (shift != null) {
            candidates.add(_ShiftCandidate(item, shift, fromLine: false));
          }
        }
      }
    }
    if (dates.length < 4 || candidates.isEmpty) return const [];

    // Every WMT pay period is two consecutive Sunday-Saturday rows. Each week
    // creates its own Sunday anchor, so choose the earliest of the two strongest
    // adjacent anchors. Unrelated page dates (for example "Today's date") have
    // far less support and are ignored.
    final weeklyCounts = <String, (DateTime, int)>{};
    for (final entry in dates) {
      final d = entry.$2;
      final anchor = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday % 7));
      final key = _dateKey(anchor);
      final old = weeklyCounts[key];
      weeklyCounts[key] = (anchor, (old?.$2 ?? 0) + 1);
    }
    final weeks = weeklyCounts.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    DateTime? start;
    var bestSupport = -1;
    for (var i = 0; i < weeks.length; i++) {
      final first = weeks[i];
      var support = first.$2;
      for (var j = 0; j < weeks.length; j++) {
        if (weeks[j].$1.difference(first.$1).inDays == 7) support += weeks[j].$2;
      }
      if (support > bestSupport) {
        bestSupport = support;
        start = first.$1;
      }
    }
    if (start == null || bestSupport < 4) return const [];

    final tableDates = dates.where((entry) {
      final d = DateTime(entry.$2.year, entry.$2.month, entry.$2.day);
      final offset = d.difference(start!).inDays;
      return offset >= 0 && offset <= 13;
    }).toList();
    if (tableDates.length < 4) return const [];

    // Derive the seven physical column centers directly from the printed date
    // positions. This is more stable than fitting one regression line and works
    // across different screenshot zoom levels.
    final byColumn = <int, List<double>>{for (var c = 0; c < 7; c++) c: <double>[]};
    final rowDateYs = <int, List<double>>{0: <double>[], 1: <double>[]};
    for (final entry in tableDates) {
      final d = DateTime(entry.$2.year, entry.$2.month, entry.$2.day);
      final offset = d.difference(start).inDays;
      final row = offset ~/ 7;
      final column = offset % 7;
      byColumn[column]!.add(entry.$1.centerX);
      rowDateYs[row]!.add(entry.$1.centerY);
    }

    final knownCenters = <int, double>{};
    for (var c = 0; c < 7; c++) {
      if (byColumn[c]!.isNotEmpty) knownCenters[c] = _median(byColumn[c]!);
    }
    if (knownCenters.length < 3) return const [];

    final spacingSamples = <double>[];
    final knownCols = knownCenters.keys.toList()..sort();
    for (var i = 1; i < knownCols.length; i++) {
      final leftCol = knownCols[i - 1];
      final rightCol = knownCols[i];
      spacingSamples.add((knownCenters[rightCol]! - knownCenters[leftCol]!) / (rightCol - leftCol));
    }
    if (spacingSamples.isEmpty) return const [];
    final spacing = _median(spacingSamples);
    if (spacing.abs() < 15) return const [];

    final referenceCol = knownCols.first;
    final referenceX = knownCenters[referenceCol]!;
    final columnCenters = List<double>.generate(7, (c) {
      if (knownCenters.containsKey(c)) return knownCenters[c]!;
      return referenceX + (c - referenceCol) * spacing;
    });

    if (rowDateYs[0]!.isEmpty || rowDateYs[1]!.isEmpty) return const [];
    final row0Y = _median(rowDateYs[0]!);
    final row1Y = _median(rowDateYs[1]!);
    final rowHeight = row1Y - row0Y;
    if (rowHeight.abs() < 12) return const [];

    // WMT shift text lives below each date inside the same cell. Use the next
    // row's date as the natural bottom edge of row 1, and one row-height beyond
    // row 2. This avoids hard-coded pixel gaps.
    final row0Top = row0Y - rowHeight * 0.05;
    final row0Bottom = row1Y - rowHeight * 0.05;
    final row1Top = row1Y - rowHeight * 0.05;
    final row1Bottom = row1Y + rowHeight * 0.95;

    final resultByDay = <String, DatedShift>{};

    // Prefer an observed date's own position over the inferred column center.
    // On real WMT screenshots, proportional date text and partially cropped
    // columns can move the inferred center far enough to reject a perfectly
    // readable shift.  The shift is printed below the date in the same cell,
    // so this nearest-neighbour pass is the strongest relationship available.
    for (final entry in tableDates) {
      final dateItem = entry.$1;
      final date = DateTime(entry.$2.year, entry.$2.month, entry.$2.day);
      final offset = date.difference(start).inDays;
      if (offset < 0 || offset > 13) continue;
      final maxVerticalGap = rowHeight.abs() * 0.90;
      final nearby = candidates.where((candidate) {
        final item = candidate.item;
        final verticalGap = item.centerY - dateItem.centerY;
        if (verticalGap < -rowHeight.abs() * 0.05 || verticalGap > maxVerticalGap) return false;
        if ((item.centerX - dateItem.centerX).abs() > spacing.abs() * 0.55) return false;
        if (candidate.fromLine && item.width > spacing.abs() * 1.35) return false;
        return true;
      }).toList();
      nearby.sort((a, b) {
        double score(_ShiftCandidate value) {
          final dx = (value.item.centerX - dateItem.centerX).abs() / spacing.abs();
          final dy = (value.item.centerY - dateItem.centerY).abs() / rowHeight.abs();
          return dx * 2 + dy + (value.fromLine ? 0.1 : 0);
        }
        return score(a).compareTo(score(b));
      });
      if (nearby.isNotEmpty) {
        resultByDay[_dateKey(date)] = DatedShift(date: date, shift: nearby.first.shift);
      }
    }

    // Fill dates whose printed date was missed or fragmented by OCR from the
    // reconstructed grid. Never replace a stronger observed-date match.
    for (var offset = 0; offset < 14; offset++) {
      final row = offset ~/ 7;
      final column = offset % 7;
      final targetX = columnCenters[column];
      final xHalfWidth = spacing.abs() * 0.48;
      final top = row == 0 ? row0Top : row1Top;
      final bottom = row == 0 ? row0Bottom : row1Bottom;

      final inCell = candidates.where((candidate) {
        final item = candidate.item;
        if (item.centerX < targetX - xHalfWidth || item.centerX > targetX + xHalfWidth) return false;
        if (item.centerY < top || item.centerY > bottom) return false;
        // A full OCR line that spans several WMT cells is not a trustworthy
        // single-cell candidate. Element candidates are always allowed.
        if (candidate.fromLine && item.width > spacing.abs() * 1.35) return false;
        return true;
      }).toList();

      if (inCell.isEmpty) continue;

      // Prefer the candidate closest to the cell's column center, then prefer
      // element-level OCR over a wider line-level fallback when tied.
      inCell.sort((a, b) {
        final ax = (a.item.centerX - targetX).abs();
        final bx = (b.item.centerX - targetX).abs();
        final byX = ax.compareTo(bx);
        if (byX != 0) return byX;
        if (a.fromLine != b.fromLine) return a.fromLine ? 1 : -1;
        return a.item.centerY.compareTo(b.item.centerY);
      });

      final date = start.add(Duration(days: offset));
      resultByDay.putIfAbsent(
        _dateKey(date),
        () => DatedShift(date: date, shift: inCell.first.shift),
      );
    }

    return resultByDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  List<String> _spatialUnrecognized(RecognizedText recognized, List<DatedShift> parsed) {
    if (parsed.isEmpty) return const [];
    final parsedDates = parsed.map((e) => _dateKey(e.date)).toSet();
    final parsedDays = parsed.map((e) => DateTime(e.date.year, e.date.month, e.date.day)).toList()..sort();
    final start = parsedDays.first.subtract(Duration(days: parsedDays.first.weekday % 7));
    final unresolved = <String>[];

    // A reconstructed WMT grid should report only genuinely missing cells.
    // Valid standalone OCR tokens and page labels are not useful review items.
    for (var offset = 0; offset < 14; offset++) {
      final date = start.add(Duration(days: offset));
      if (!parsedDates.contains(_dateKey(date))) {
        unresolved.add('No shift recognized for ${date.month}/${date.day}/${date.year}');
      }
    }
    return unresolved;
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
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
    final normalized = line
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('Š', 'S')
        .replaceAll('š', 's')
        .replaceAll('—', '-')
        .replaceAll('–', '-');
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
    if (!RegExp(
      r'^(?:X|SL|HL|A<[^>]+>|[LSCQ$]*(?:Xtra)?\d{3,4}[LSCQ$]*(?:Xtra)?|Xt\d{3,4}ra)$',
      caseSensitive: false,
    ).hasMatch(fixed)) {
      return null;
    }
    try {
      return parser.parse(fixed);
    } catch (_) {
      return null;
    }
  }

  String _repairCommonOcr(String token) {
    var value = token.trim().replaceAll('Š', 'S').replaceAll('š', 's');
    if (RegExp(r'\d').hasMatch(value)) value = value.replaceAll('O', '0').replaceAll('o', '0');
    return value;
  }

  bool _looksScheduleLike(String line) =>
      RegExp(r'\d{3,4}|\b(?:X|SL|HL)\b|A\s*[<\[]', caseSensitive: false).hasMatch(line);
}
