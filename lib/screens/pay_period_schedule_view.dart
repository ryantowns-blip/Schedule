import 'package:flutter/material.dart';

import '../services/wmt_schedule_extractor.dart';

class PayPeriodSchedule {
  const PayPeriodSchedule({required this.start, required this.end, required this.shifts});

  final DateTime start;
  final DateTime end;
  final List<DatedShift> shifts;

  String get label => '${start.month}/${start.day}–${end.month}/${end.day}';
}

List<PayPeriodSchedule> buildPayPeriods(List<DatedShift> shifts) {
  if (shifts.isEmpty) return const [];
  final sorted = [...shifts]..sort((a, b) => a.date.compareTo(b.date));
  final periods = <PayPeriodSchedule>[];
  var index = 0;
  while (index < sorted.length) {
    final start = sorted[index].date;
    final end = start.add(const Duration(days: 13));
    final items = sorted.where((e) => !e.date.isBefore(start) && !e.date.isAfter(end)).toList();
    periods.add(PayPeriodSchedule(start: start, end: end, shifts: items));
    index += items.length;
  }
  return periods;
}

class PayPeriodScheduleView extends StatelessWidget {
  const PayPeriodScheduleView({super.key, required this.shifts});

  final List<DatedShift> shifts;

  @override
  Widget build(BuildContext context) {
    final periods = buildPayPeriods(shifts);
    if (periods.isEmpty) return const SizedBox.shrink();

    return DefaultTabController(
      length: periods.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('My Schedule', style: Theme.of(context).textTheme.titleMedium)),
              Text('${shifts.length} entries', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            isScrollable: periods.length > 2,
            tabs: [for (final period in periods) Tab(text: period.label)],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < periods.length; i++)
            _PeriodBody(period: periods[i], visibleIndex: i),
        ],
      ),
    );
  }
}

class _PeriodBody extends StatefulWidget {
  const _PeriodBody({required this.period, required this.visibleIndex});
  final PayPeriodSchedule period;
  final int visibleIndex;

  @override
  State<_PeriodBody> createState() => _PeriodBodyState();
}

class _PeriodBodyState extends State<_PeriodBody> {
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.index != widget.visibleIndex) return const SizedBox.shrink();
        final byDate = <String, DatedShift>{
          for (final item in widget.period.shifts) _key(item.date): item,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeekRow(title: 'Week 1', start: widget.period.start, byDate: byDate),
            const SizedBox(height: 12),
            _WeekRow(title: 'Week 2', start: widget.period.start.add(const Duration(days: 7)), byDate: byDate),
          ],
        );
      },
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.title, required this.start, required this.byDate});
  final String title;
  final DateTime start;
  final Map<String, DatedShift> byDate;

  @override
  Widget build(BuildContext context) {
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 6 ? 0 : 3),
                  child: _DayCell(
                    dayName: dayNames[i],
                    date: start.add(Duration(days: i)),
                    entry: byDate[_key(start.add(Duration(days: i)))],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.dayName, required this.date, this.entry});
  final String dayName;
  final DateTime date;
  final DatedShift? entry;

  @override
  Widget build(BuildContext context) {
    final shift = entry?.shift;
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    final status = shift == null
        ? '—'
        : shift.isAnnualLeave
            ? 'Off'
            : shift.isHolidayLeave
                ? 'HL'
                : shift.isSickLeave
                    ? 'Sick'
                    : shift.isDayOff
                        ? 'Off'
                        : shift.raw;

    final scheme = Theme.of(context).colorScheme;
    final background = shift?.isOvertime == true
        ? scheme.errorContainer
        : shift?.isSickLeave == true
            ? scheme.secondaryContainer
            : shift?.isAnnualLeave == true || shift?.isDayOff == true || shift?.isHolidayLeave == true
                ? scheme.surfaceContainerHighest
                : null;

    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: isToday ? scheme.primary : scheme.outlineVariant,
          width: isToday ? 2.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: background,
      ),
      child: Column(
        children: [
          if (isToday)
            Text(
              'TODAY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
            ),
          Text(dayName, style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
          Text('${date.month}/${date.day}', style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              status,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

String _key(DateTime date) => '${date.year}-${date.month}-${date.day}';
