class UpcomingLeaveEntry {
  const UpcomingLeaveEntry({
    required this.date,
    required this.type,
    required this.status,
    this.requestedAt,
  });

  final DateTime date;
  final String type;
  final String status;
  final String? requestedAt;

  bool get isApproved => status.trim().toLowerCase() == 'approved';
}
