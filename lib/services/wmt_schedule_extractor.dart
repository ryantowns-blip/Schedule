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
    } catch (_) {}
    return text;
  }

  List<DatedShift> extract(String capturedHtml) {
    final html = normalizeCapturedHtml(capturedHtml);
    if (html.isEmpty) return const [];

    final results = <DatedShift>[];
    final cellPattern = RegExp(r'<t[dh]\b[^>]*>([\s\S]*?)</t[dh]>', caseSensitive: false);
    for (final match in cellPattern.allMatches(html)) {
      final text = _stripTags(match.group(1) ?? '');
      final dateMatch = RegExp(r'\b(\d{1,2}/\d{1,2}/\d{2,4})\b').firstMatch(text);
      if (dateMatch == null) continue;
      final date = _parseDate(dateMatch.group(1));
      if (date == null) continue;
      final afterDate = text.substring(dateMatch.end).trim();
      final shift = _findShift(afterDate);
      if (shift != null) results.add(DatedShift(date: date, shift: shift));
    }
    if (results.isNotEmpty) return _dedupeAndSort(results);

    final datedElement = RegExp(
      r'''<[^>]*(?:data-date|date)\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</[^>]+>''',
      caseSensitive: false,
    );
    for (final match in datedElement.allMatches(html)) {
      final date = _parseDate(match.group(1));
      if (date == null) continue;
      final shift = _findShift(_stripTags(match.group(2) ?? ''));
      if (shift != null) results.add(DatedShift(date: date, shift: shift));
    }
    if (results.isNotEmpty) return _dedupeAndSort(results);

    final text = _stripTags(html);
    final pairPattern = RegExp(
      r'\b(\d{1,2}/\d{1,2}/\d{2,4})\b\s+([^\s]+)',
      caseSensitive: false,
    );
    for (final match in pairPattern.allMatches(text)) {
      final date = _parseDate(match.group(1));
      final shift = _tryParseShift(match.group(2) ?? '');
      if (date != null && shift != null) results.add(DatedShift(date: date, shift: shift));
    }
    return _dedupeAndSort(results);
  }

  List<DatedShift> _dedupeAndSort(List<DatedShift> input) {
    final byDay = <String, DatedShift>{};
    for (final item in input) {
      final key = '${item.date.year}-${item.date.month}-${item.date.day}';
      byDay[key] = item;
    }
    final output = byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return output;
  }

  ParsedShift? _findShift(String text) {
    for (final token in text.split(RegExp(r'\s+'))) {
      final parsed = _tryParseShift(token);
      if (parsed != null) return parsed;
    }
    return null;
  }

  ParsedShift? _tryParseShift(String raw) {
    var token = raw.trim();
    if (token.isEmpty) return null;

    final annualMatch = RegExp(r'A<[^>]+>', caseSensitive: false).firstMatch(token);
    if (annualMatch != null) {
      token = annualMatch.group(0)!;
    } else {
      token = token.replaceAll(RegExp(r'^[^A-Za-z0-9$]+|[^A-Za-z0-9$]+$'), '');
    }

    if (token.isEmpty) return null;
    if (!RegExp(
      r'^(?:X|SL|HL|A<[^>]+>|[LSCQ$]*(?:Xtra)?\d{3,4}[LSCQ$]*(?:Xtra)?|Xt\d{3,4}ra)$',
      caseSensitive: false,
    ).hasMatch(token)) return null;
    try {
      return parser.parse(token);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final text = value.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
    if (iso != null) return DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
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
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
