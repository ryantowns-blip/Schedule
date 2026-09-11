import 'parsed_shift.dart';

class DatedShift {
  const DatedShift({required this.date, required this.shift});

  final DateTime date;
  final ParsedShift shift;
}
