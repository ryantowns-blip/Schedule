import '../models/upcoming_leave.dart';

class WmtLeaveExtractor {
  const WmtLeaveExtractor();

  List<UpcomingLeaveEntry> extract(String html, {DateTime? now}) {
    final todaySource = now ?? DateTime.now();
    final today = DateTime(todaySource.year, todaySource.month, todaySource.day);
    final results = <UpcomingLeaveEntry>[];

    final rowPattern = RegExp(r'<tr\b[^>]*>([\s\S]*?)</tr>', caseSensitive: false);
    final cellPattern = RegExp(r'<t[dh]\b[^>]*>([\s\S]*?)</t[dh]>', caseSensitive: false);

    for (final rowMatch in rowPattern.allMatches(html)) {
      final cells = cellPattern
          .allMatches(rowMatch.group(1) ?? '')
          .map((m) => _stripTags(m.group(1) ?? ''))
          .where((text) => text.isNotEmpty)
          .toList();
      if (cells.length < 3) continue;

      final dateIndex = cells.indexWhere((cell) => RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(cell));
      if (dateIndex < 0 || dateIndex + 2 >= cells.length) continue;
      final date = _parseDate(cells[dateIndex]);
      if (date == null || !date.isAfter(today)) continue;

      final type = cells[dateIndex + 1].trim();
      if (type.toLowerCase() != 'annual') continue;

      final status = cells[dateIndex + 2].trim();
      final requestedAt = dateIndex + 3 < cells.length ? cells[dateIndex + 3].trim() : null;
      results.add(UpcomingLeaveEntry(
        date: date,
        type: type,
        status: status,
        requestedAt: requestedAt?.isEmpty == true ? null : requestedAt,
      ));
    }

    final byDay = <String, UpcomingLeaveEntry>{};
    for (final entry in results) {
      final key = '${entry.date.year}-${entry.date.month}-${entry.date.day}';
      byDay[key] = entry;
    }
    final output = byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return output;
  }

  DateTime? _parseDate(String text) {
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(text.trim());
    if (match == null) return null;
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    return DateTime(year, int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  String _stripTags(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
