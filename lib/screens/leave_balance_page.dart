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
  static const _manualEntriesKey = 'manual_leave_usage_v1';

  final _projectionService = const LeaveProjectionService();
  final _parser = const ScheduleParser();
  final _annualBalance = TextEditingController();
  final _sickBalance = TextEditingController();
  final _annualAccrual = TextEditingController(text: '8');
  final _sickAccrual = TextEditingController(text: '4');
  final _carryoverLimit = TextEditingController(text: '240');

  DateTime _effectiveDate = DateTime.now();
  List<LeaveUsage> _importedUsage = const [];
  List<LeaveUsage> _manualUsage = const [];
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
    final manualUsage = <LeaveUsage>[];

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

    for (final row in prefs.getStringList(_manualEntriesKey) ?? const <String>[]) {
      try {
        final map = jsonDecode(row) as Map<String, dynamic>;
        final date = DateTime.tryParse(map['date'] as String? ?? '');
        final hours = (map['hours'] as num?)?.toDouble();
        final kindName = map['kind'] as String? ?? '';
        final id = map['id'] as String?;
        if (date == null || hours == null || hours <= 0 || id == null) continue;
        manualUsage.add(LeaveUsage(
          id: id,
          date: date,
          hours: hours,
          kind: kindName == LeaveKind.sick.name ? LeaveKind.sick : LeaveKind.annual,
        ));
      } catch (_) {}
    }
    manualUsage.sort((a, b) => a.date.compareTo(b.date));

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
      _importedUsage = usage;
      _manualUsage = manualUsage;
      _loading = false;
    });
  }

  Future<void> _saveManualUsage(List<LeaveUsage> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _manualEntriesKey,
      entries
          .map((entry) => jsonEncode({
                'id': entry.id,
                'date': entry.date.toIso8601String(),
                'kind': entry.kind.name,
                'hours': entry.hours,
              }))
          .toList(),
    );
    if (!mounted) return;
    setState(() => _manualUsage = entries);
  }

  Future<void> _addManualUsage() async {
    final entry = await _showManualUsageDialog();
    if (entry == null) return;
    final updated = [..._manualUsage, entry]..sort((a, b) => a.date.compareTo(b.date));
    await _saveManualUsage(updated);
  }

  Future<void> _editManualUsage(LeaveUsage existing) async {
    final entry = await _showManualUsageDialog(existing: existing);
    if (entry == null) return;
    final updated = [
      for (final item in _manualUsage) if (item.id == existing.id) entry else item,
    ]..sort((a, b) => a.date.compareTo(b.date));
    await _saveManualUsage(updated);
  }

  Future<void> _deleteManualUsage(LeaveUsage entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete leave entry?'),
        content: Text('${_leaveKind(entry.kind)} • ${_date(entry.date)} • ${_hours(entry.hours)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _saveManualUsage(_manualUsage.where((item) => item.id != entry.id).toList());
  }

  Future<LeaveUsage?> _showManualUsageDialog({LeaveUsage? existing}) async {
    var date = existing?.date ?? DateTime.now();
    var kind = existing?.kind ?? LeaveKind.annual;
    final hours = TextEditingController(text: existing == null ? '8' : _number(existing.hours));
    final result = await showDialog<LeaveUsage>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Leave Used' : 'Edit Leave Used'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Date used'),
                  subtitle: Text(_date(date)),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(date.year - 2),
                      lastDate: DateTime(date.year + 2),
                    );
                    if (selected != null) setDialogState(() => date = selected);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<LeaveKind>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Leave type'),
                  items: const [
                    DropdownMenuItem(value: LeaveKind.annual, child: Text('Annual Leave')),
                    DropdownMenuItem(value: LeaveKind.sick, child: Text('Sick Leave')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hours,
                  autofocus: existing == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Hours used', suffixText: 'hrs'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(hours.text.trim());
                if (value == null || value <= 0) return;
                Navigator.pop(
                  context,
                  LeaveUsage(
                    id: existing?.id ?? 'manual-${DateTime.now().microsecondsSinceEpoch}',
                    date: date,
                    kind: kind,
                    hours: value,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    hours.dispose();
    return result;
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
        : _projectionService.calculate(
            settings: settings,
            usage: [..._importedUsage, ..._manualUsage],
          );
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
                  Row(
                    children: [
                      Expanded(child: Text('Manual leave used', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                      TextButton.icon(
                        onPressed: _addManualUsage,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: _manualUsage.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No manual leave usage entered. Add unscheduled leave that does not appear in your imported schedule.'),
                          )
                        : Column(
                            children: [
                              for (var index = 0; index < _manualUsage.length; index++) ...[
                                ListTile(
                                  leading: Icon(_manualUsage[index].kind == LeaveKind.annual ? Icons.beach_access_outlined : Icons.medical_services_outlined),
                                  title: Text('${_leaveKind(_manualUsage[index].kind)} • ${_hours(_manualUsage[index].hours)}'),
                                  subtitle: Text(_date(_manualUsage[index].date)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit entry',
                                        onPressed: () => _editManualUsage(_manualUsage[index]),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete entry',
                                        onPressed: () => _deleteManualUsage(_manualUsage[index]),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                                if (index != _manualUsage.length - 1) const Divider(height: 1),
                              ],
                            ],
                          ),
                  ),
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
    if (projection.currentAnnual < 0) {
      warnings.add('Your current annual leave balance is ${_hours(-projection.currentAnnual)} below zero.');
    }
    if (projection.currentSick < 0) {
      warnings.add('Your current sick leave balance is ${_hours(-projection.currentSick)} below zero.');
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
            Expanded(child: _BalanceCard(title: 'Annual now', hours: projection.currentAnnual, icon: Icons.beach_access_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _BalanceCard(title: 'Sick now', hours: projection.currentSick, icon: Icons.medical_services_outlined)),
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
}

String _date(DateTime date) => '${date.month}/${date.day}/${date.year}';
String _leaveKind(LeaveKind kind) => kind == LeaveKind.annual ? 'Annual Leave' : 'Sick Leave';
String _number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
String _hours(double value) => '${_number(value)} hrs';
