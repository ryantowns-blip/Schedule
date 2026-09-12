import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/leave_balance.dart';
import '../services/schedule_parser.dart';

class LeaveBalancePage extends StatefulWidget {
  const LeaveBalancePage({super.key});

  @override
  State<LeaveBalancePage> createState() => _LeaveBalancePageState();
}

class _LeaveBalancePageState extends State<LeaveBalancePage> {
  static const _scheduleEntriesKey = 'screenshot_schedule_entries';
  static const _leaveEntriesKey = 'screenshot_leave_entries_v1';

  final _projectionService = const LeaveProjectionService();
  final _parser = const ScheduleParser();
  final _annualBalance = TextEditingController();
  final _sickBalance = TextEditingController();
  final _annualAccrual = TextEditingController(text: '8');
  final _sickAccrual = TextEditingController(text: '4');
  final _carryoverLimit = TextEditingController(text: '240');

  DateTime _effectiveDate = DateTime.now();
  List<LeaveUsage> _usage = const [];
  LeaveBalanceSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _annualBalance.dispose();
    _sickBalance.dispose();
    _annualAccrual.dispose();
    _sickAccrual.dispose();
    _carryoverLimit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await LeaveBalanceSettings.load();
    final usage = <LeaveUsage>[];

    for (final row in prefs.getStringList(_scheduleEntriesKey) ?? const <String>[]) {
      final separator = row.indexOf('|');
      if (separator <= 0 || separator >= row.length - 1) continue;
      final date = DateTime.tryParse(row.substring(0, separator));
      if (date == null) continue;
      try {
        final shift = _parser.parse(row.substring(separator + 1));
        if (shift.isAnnualLeave) usage.add(LeaveUsage(date: date, kind: LeaveKind.annual));
        if (shift.isSickLeave) usage.add(LeaveUsage(date: date, kind: LeaveKind.sick));
      } catch (_) {}
    }

    for (final row in prefs.getStringList(_leaveEntriesKey) ?? const <String>[]) {
      try {
        final map = jsonDecode(row) as Map<String, dynamic>;
        final date = DateTime.tryParse(map['date'] as String? ?? '');
        final status = (map['status'] as String? ?? '').toLowerCase();
        final type = (map['type'] as String? ?? '').toLowerCase();
        if (date == null || status != 'approved') continue;
        if (type.contains('annual')) usage.add(LeaveUsage(date: date, kind: LeaveKind.annual));
        if (type.contains('sick')) usage.add(LeaveUsage(date: date, kind: LeaveKind.sick));
      } catch (_) {}
    }

    if (saved != null) {
      _effectiveDate = saved.effectiveDate;
      _annualBalance.text = _number(saved.annualBalance);
      _sickBalance.text = _number(saved.sickBalance);
      _annualAccrual.text = _number(saved.annualAccrualPerPayPeriod);
      _sickAccrual.text = _number(saved.sickAccrualPerPayPeriod);
      _carryoverLimit.text = _number(saved.annualCarryoverLimit);
    }
    if (!mounted) return;
    setState(() {
      _settings = saved;
      _usage = usage;
      _loading = false;
    });
  }

  double? _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  Future<void> _save() async {
    final annual = _value(_annualBalance);
    final sick = _value(_sickBalance);
    final annualAccrual = _value(_annualAccrual);
    final sickAccrual = _value(_sickAccrual);
    final carryover = _value(_carryoverLimit);
    final missingBalance = annual == null || sick == null;
    final invalidRule = [annualAccrual, sickAccrual, carryover]
        .any((value) => value == null || value! < 0);
    if (missingBalance || invalidRule) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid balances and non-negative accrual and carryover amounts.')),
      );
      return;
    }
    final settings = LeaveBalanceSettings(
      effectiveDate: _effectiveDate,
      annualBalance: annual!,
      sickBalance: sick!,
      annualAccrualPerPayPeriod: annualAccrual!,
      sickAccrualPerPayPeriod: sickAccrual!,
      annualCarryoverLimit: carryover!,
    );
    await settings.save();
    if (!mounted) return;
    setState(() => _settings = settings);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Leave balances updated.')),
    );
  }

  Future<void> _selectEffectiveDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(_effectiveDate.year - 2),
      lastDate: DateTime(_effectiveDate.year + 1),
    );
    if (selected != null) setState(() => _effectiveDate = selected);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final projection = settings == null
        ? null
        : _projectionService.calculate(settings: settings, usage: _usage);
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Balance')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _InfoBanner(
                    text: settings == null
                        ? 'Enter the balances from your latest LES. Future approved leave found in your schedule and My Leave imports will be deducted automatically.'
                        : 'Projection based on balances effective ${_date(settings.effectiveDate)} and approved leave currently saved in the app.',
                  ),
                  if (projection != null) ...[
                    const SizedBox(height: 12),
                    _ProjectionSummary(settings: settings!, projection: projection),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 16),
                  Text('Balance from latest LES', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.today_outlined),
                            title: const Text('Balance effective date'),
                            subtitle: Text(_date(_effectiveDate)),
                            trailing: const Icon(Icons.edit_calendar_outlined),
                            onTap: _selectEffectiveDate,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _HoursField(controller: _annualBalance, label: 'Annual balance')),
                              const SizedBox(width: 12),
                              Expanded(child: _HoursField(controller: _sickBalance, label: 'Sick balance')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Accrual and carryover', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _HoursField(controller: _annualAccrual, label: 'Annual per PP')),
                              const SizedBox(width: 12),
                              Expanded(child: _HoursField(controller: _sickAccrual, label: 'Sick per PP')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _HoursField(controller: _carryoverLimit, label: 'Annual carryover limit'),
                          const SizedBox(height: 8),
                          const Text('The standard federal defaults are 4, 6, or 8 annual hours per pay period, 4 sick hours, and a 240-hour annual carryover limit. A 6-hour annual rate automatically earns 10 hours in the final pay period.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.calculate_outlined),
                    label: Text(settings == null ? 'Save and Calculate' : 'Update Projection'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProjectionSummary extends StatelessWidget {
  const _ProjectionSummary({required this.settings, required this.projection});

  final LeaveBalanceSettings settings;
  final LeaveProjection projection;

  @override
  Widget build(BuildContext context) {
    final warnings = <String>[];
    if (settings.annualBalance < 0) {
      warnings.add('Your entered annual leave balance is ${_hours(-settings.annualBalance)} below zero.');
    }
    if (settings.sickBalance < 0) {
      warnings.add('Your entered sick leave balance is ${_hours(-settings.sickBalance)} below zero.');
    }
    if (projection.useOrLose > 0) {
      warnings.add('${_hours(projection.useOrLose)} of projected annual leave is above your carryover limit.');
    }
    if (projection.projectedAnnual < 0) {
      warnings.add('Annual leave is projected to fall ${_hours(-projection.projectedAnnual)} below zero.');
    }
    if (projection.projectedSick < 0) {
      warnings.add('Sick leave is projected to fall ${_hours(-projection.projectedSick)} below zero.');
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _BalanceCard(title: 'Annual now', hours: settings.annualBalance, icon: Icons.beach_access_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _BalanceCard(title: 'Sick now', hours: settings.sickBalance, icon: Icons.medical_services_outlined)),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Projected at leave-year end', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${_date(projection.leaveYearEnd)} • ${projection.remainingPayPeriods} pay periods remaining', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 14),
                _ProjectionRow(label: 'Annual', balance: settings.annualBalance, earned: projection.annualAccrued, planned: projection.annualPlanned, projected: projection.projectedAnnual),
                const Divider(height: 24),
                _ProjectionRow(label: 'Sick', balance: settings.sickBalance, earned: projection.sickAccrued, planned: projection.sickPlanned, projected: projection.projectedSick),
              ],
            ),
          ),
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(child: Text(warnings.join('\n'), style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.title, required this.hours, required this.icon});
  final String title;
  final double hours;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(_hours(hours), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(title, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _ProjectionRow extends StatelessWidget {
  const _ProjectionRow({required this.label, required this.balance, required this.earned, required this.planned, required this.projected});
  final String label;
  final double balance;
  final double earned;
  final double planned;
  final double projected;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('${_hours(balance)} current  +  ${_hours(earned)} earned  −  ${_hours(planned)} planned'),
          const SizedBox(height: 4),
          Text('${_hours(projected)} projected', style: TextStyle(fontWeight: FontWeight.w800, color: projected < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary)),
        ],
      );
}

class _HoursField extends StatelessWidget {
  const _HoursField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: 'hrs'),
      );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );

String _date(DateTime date) => '${date.month}/${date.day}/${date.year}';
String _number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
String _hours(double value) => '${_number(value)} hrs';
