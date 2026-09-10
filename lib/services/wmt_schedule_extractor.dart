import 'dart:convert';

import '../models/parsed_shift.dart';
import 'schedule_parser.dart';

class DatedShift {
  const DatedShift({required this.date, required this.shift});

  final DateTime date;
  final ParsedShift shift;
}

class WmtScheduleExtractor {
  const WmtScheduleExtractor({this.parser = const ScheduleParser()});

  final ScheduleParser parser;

  String normalizeCapturedHtml(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty) return '';
    if (text.startsWith('<')) return text;

    try {
      final decoded = jsonDecode(text);
      if (decoded is String) return decoded;
    } catch (_) {
      // Fall through and return the original text.
    }
    return text;
  }

  List<DatedShift> extract(String capturedHtml) {
    final html = normalizeCapturedHtml(capturedHtml);
    if (html.isEmpty) return const [];

    final results = <DatedShift>[];
    final rowPattern = RegExp(
      r'''<[^>]*(?:data-date|date)\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</[^>]+>''',
      caseSensitive: false,
    );

    for (final match in rowPattern.allMatches(html)) {
      final date = _parseDate(match.group(1));
      if (date == null) continue;
      final body = _stripTags(match.group(2) ?? '');
      final shift = _findShift(body);
      if (shift != null) results.add(DatedShift(date: date, shift: shift));
    }

    if (results.isNotEmpty) {
      results.sort((a, b) => a.date.compareTo(b.date));
      return results;
    }

    // Fallback for table layouts where date and shift are separate cells.
    final text = _stripTags(html);
    final tokens = text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    for (var i = 0; i < tokens.length; i++) {
      final date = _parseDate(tokens[i]);
      if (date == null) continue;
      for (var j = i + 1; j < tokens.length && j <= i + 6; j++) {
        final shift = _tryParseShift(tokens[j]);
        if (shift != null) {
          results.add(DatedShift(date: date, shift: shift));
          break;
        }
      }
    }

    results.sort((a, b) => a.date.compareTo(b.date));
    return results;
  }

  ParsedShift? _findShift(String text) {
    for (final token in text.split(RegExp(r'\s+'))) {
      final parsed = _tryParseShift(token);
      if (parsed != null) return parsed;
    }
    return null;
  }

  ParsedShift? _tryParseShift(String raw) {
    final token = raw.trim().replaceAll(RegExp(r'^[^A-Za-z0-9$]+|[^A-Za-z0-9$]+$'), '');
    if (token.isEmpty) return null;
    if (!RegExp(r'^(?:X|(?:Xtra)?[LSCQ$]*\d{3,4}(?:Xtra)?|Xt\d{3,4}ra)$', caseSensitive: false)
        .hasMatch(token)) {
      return null;
    }
    try {
      return parser.parse(token);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
    if (iso != null) {
      return DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(text);
    if (slash != null) {
      var year = int.parse(slash.group(3)!);
      if (year < 100) year += 2000;
      return DateTime(year, int.parse(slash.group(1)!), int.parse(slash.group(2)!));
    }

    return null;
  }

  String _stripTags(String value) => value
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
