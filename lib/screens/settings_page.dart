import 'package:flutter/material.dart';

import '../models/schedule_display_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initialSettings});

  final ScheduleDisplaySettings initialSettings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ScheduleDisplaySettings _settings;

  static const _palette = <Color?>[
    null,
    Color(0xFFFFDAD6),
    Color(0xFFFFE0B2),
    Color(0xFFFFF3B0),
    Color(0xFFD8F3DC),
    Color(0xFFD7E3FC),
    Color(0xFFE8DEF8),
    Color(0xFFE2E2E6),
  ];

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  Future<void> _saveAndClose() async {
    await _settings.save();
    if (!mounted) return;
    Navigator.of(context).pop(_settings);
  }

  Future<void> _reset() async {
    setState(() => _settings = ScheduleDisplaySettings.defaults);
    await _settings.save();
  }

  void _setColor(_ColorTarget target, Color? color) {
    setState(() {
      switch (target) {
        case _ColorTarget.regular:
          _settings = _settings.copyWith(regularColor: color, clearRegular: color == null);
          break;
        case _ColorTarget.overtime:
          _settings = _settings.copyWith(overtimeColor: color, clearOvertime: color == null);
          break;
        case _ColorTarget.off:
          _settings = _settings.copyWith(offColor: color, clearOff: color == null);
          break;
        case _ColorTarget.annualLeave:
          _settings = _settings.copyWith(annualLeaveColor: color, clearAnnualLeave: color == null);
          break;
        case _ColorTarget.sick:
          _settings = _settings.copyWith(sickColor: color, clearSick: color == null);
          break;
        case _ColorTarget.holiday:
          _settings = _settings.copyWith(holidayColor: color, clearHoliday: color == null);
          break;
      }
    });
  }

  Color? _valueFor(_ColorTarget target) {
    switch (target) {
      case _ColorTarget.regular:
        return _settings.regularColor;
      case _ColorTarget.overtime:
        return _settings.overtimeColor;
      case _ColorTarget.off:
        return _settings.offColor;
      case _ColorTarget.annualLeave:
        return _settings.annualLeaveColor;
      case _ColorTarget.sick:
        return _settings.sickColor;
      case _ColorTarget.holiday:
        return _settings.holidayColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Settings'),
        actions: [TextButton(onPressed: _reset, child: const Text('Reset'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Shift colors', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Choose the background used for each type of schedule entry. Annual Leave also uses this color for its dedicated calendar.'),
          const SizedBox(height: 16),
          _ColorRow(label: 'Regular shift', value: _valueFor(_ColorTarget.regular), palette: _palette, onChanged: (c) => _setColor(_ColorTarget.regular, c)),
          _ColorRow(label: 'Overtime', value: _valueFor(_ColorTarget.overtime), palette: _palette, onChanged: (c) => _setColor(_ColorTarget.overtime, c)),
          _ColorRow(label: 'Day Off', value: _valueFor(_ColorTarget.off), palette: _palette, onChanged: (c) => _setColor(_ColorTarget.off, c)),
          _ColorRow(label: 'Annual Leave', value: _valueFor(_ColorTarget.annualLeave), palette: _palette, onChanged: (c) => _setColor(_ColorTarget.annualLeave, c)),
          _ColorRow(label: 'Sick Leave', value: _valueFor(_ColorTarget.sick), palette: _palette, onChanged: (c) => _setColor(_ColorTarget.sick, c)),
          _ColorRow(label: 'Holiday Leave', value: _valueFor(_ColorTarget.holiday), palette: _palette, onChanged: (c) => _setColor(_ColorTarget.holiday, c)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _saveAndClose, icon: const Icon(Icons.save_outlined), label: const Text('Save Settings')),
        ],
      ),
    );
  }
}

enum _ColorTarget { regular, overtime, off, annualLeave, sick, holiday }

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.label, required this.value, required this.palette, required this.onChanged});

  final String label;
  final Color? value;
  final List<Color?> palette;
  final ValueChanged<Color?> onChanged;

  bool _same(Color? a, Color? b) => a?.value == b?.value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in palette)
                  InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => onChanged(color),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color ?? Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: _same(value, color) ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                          width: _same(value, color) ? 3 : 1,
                        ),
                      ),
                      child: color == null
                          ? const Icon(Icons.block, size: 18)
                          : _same(value, color)
                              ? const Icon(Icons.check, size: 18)
                              : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
