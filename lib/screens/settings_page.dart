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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all colors?'),
        content: const Text('This restores every schedule and calendar color to its default.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _settings = ScheduleDisplaySettings.defaults);
    await _settings.save();
  }

  void _setColor(_ColorTarget target, Color? color) {
    setState(() {
      switch (target) {
        case _ColorTarget.regular:
          _settings = _settings.copyWith(
            regularColor: color,
            clearRegular: color == null,
          );
          break;
        case _ColorTarget.overtime:
          _settings = _settings.copyWith(
            overtimeColor: color,
            clearOvertime: color == null,
          );
          break;
        case _ColorTarget.off:
          _settings = _settings.copyWith(
            offColor: color,
            clearOff: color == null,
          );
          break;
        case _ColorTarget.annualLeave:
          _settings = _settings.copyWith(
            annualLeaveColor: color,
            clearAnnualLeave: color == null,
          );
          break;
        case _ColorTarget.sick:
          _settings = _settings.copyWith(
            sickColor: color,
            clearSick: color == null,
          );
          break;
        case _ColorTarget.holiday:
          _settings = _settings.copyWith(
            holidayColor: color,
            clearHoliday: color == null,
          );
          break;
        case _ColorTarget.annualLeaveCalendar:
          _settings = _settings.copyWith(
            annualLeaveCalendarColor: color,
            clearAnnualLeaveCalendar: color == null,
          );
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
      case _ColorTarget.annualLeaveCalendar:
        return _settings.annualLeaveCalendarColor;
    }
  }

  Future<void> _pickCustomColor(_ColorTarget target) async {
    final current = _valueFor(target) ?? const Color(0xFF5C6BC0);
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _CustomColorDialog(initialColor: current),
    );
    if (picked != null) _setColor(target, picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [TextButton(onPressed: _reset, child: const Text('Reset'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeading(
            icon: Icons.calendar_view_week_outlined,
            title: 'Schedule colors',
            description: 'Choose the background used for each type of schedule entry. Use Custom to pick any color.',
          ),
          const SizedBox(height: 16),
          _ColorRow(
            label: 'Regular shift',
            value: _valueFor(_ColorTarget.regular),
            palette: _palette,
            onChanged: (c) => _setColor(_ColorTarget.regular, c),
            onCustom: () => _pickCustomColor(_ColorTarget.regular),
          ),
          _ColorRow(
            label: 'Overtime',
            value: _valueFor(_ColorTarget.overtime),
            palette: _palette,
            onChanged: (c) => _setColor(_ColorTarget.overtime, c),
            onCustom: () => _pickCustomColor(_ColorTarget.overtime),
          ),
          _ColorRow(
            label: 'Day Off',
            value: _valueFor(_ColorTarget.off),
            palette: _palette,
            onChanged: (c) => _setColor(_ColorTarget.off, c),
            onCustom: () => _pickCustomColor(_ColorTarget.off),
          ),
          _ColorRow(
            label: 'Annual Leave',
            value: _valueFor(_ColorTarget.annualLeave),
            palette: _palette,
            onChanged: (c) => _setColor(_ColorTarget.annualLeave, c),
            onCustom: () => _pickCustomColor(_ColorTarget.annualLeave),
          ),
          _ColorRow(
            label: 'Sick Leave',
            value: _valueFor(_ColorTarget.sick),
            palette: _palette,
            onChanged: (c) => _setColor(_ColorTarget.sick, c),
            onCustom: () => _pickCustomColor(_ColorTarget.sick),
          ),
          _ColorRow(
            label: 'Holiday Leave',
            value: _valueFor(_ColorTarget.holiday),
            palette: _palette,
            onChanged: (c) => _setColor(_ColorTarget.holiday, c),
            onCustom: () => _pickCustomColor(_ColorTarget.holiday),
          ),
          const SizedBox(height: 24),
          const _SectionHeading(
            icon: Icons.event_outlined,
            title: 'Calendar colors',
            description: 'Annual Leave uses its own calendar color. Work shifts and Holiday Leave use the destination calendar color selected during sync.',
          ),
          const SizedBox(height: 16),
          _ColorRow(
            label: 'Annual Leave calendar',
            value: _valueFor(_ColorTarget.annualLeaveCalendar),
            palette: _palette.whereType<Color>().toList(),
            onChanged: (c) {
              if (c != null) _setColor(_ColorTarget.annualLeaveCalendar, c);
            },
            onCustom: () => _pickCustomColor(_ColorTarget.annualLeaveCalendar),
            allowNone: false,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saveAndClose,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ColorTarget {
  regular,
  overtime,
  off,
  annualLeave,
  sick,
  holiday,
  annualLeaveCalendar,
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.value,
    required this.palette,
    required this.onChanged,
    required this.onCustom,
    this.allowNone = true,
  });

  final String label;
  final Color? value;
  final List<Color?> palette;
  final ValueChanged<Color?> onChanged;
  final VoidCallback onCustom;
  final bool allowNone;

  bool _same(Color? a, Color? b) => a?.value == b?.value;

  String _hex(Color color) =>
      '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final choices = allowNone ? palette : palette.where((c) => c != null).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (value != null)
                  Text(
                    _hex(value!),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final color in choices)
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
                          color: _same(value, color)
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
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
                OutlinedButton.icon(
                  onPressed: onCustom,
                  icon: const Icon(Icons.palette_outlined, size: 18),
                  label: const Text('Custom'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late double _red;
  late double _green;
  late double _blue;

  @override
  void initState() {
    super.initState();
    _red = widget.initialColor.red.toDouble();
    _green = widget.initialColor.green.toDouble();
    _blue = widget.initialColor.blue.toDouble();
  }

  Color get _color => Color.fromARGB(255, _red.round(), _green.round(), _blue.round());

  String get _hex =>
      '#${_color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom color'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 70,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            const SizedBox(height: 8),
            Text(_hex, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            _RgbSlider(
              label: 'Red',
              value: _red,
              onChanged: (v) => setState(() => _red = v),
            ),
            _RgbSlider(
              label: 'Green',
              value: _green,
              onChanged: (v) => setState(() => _green = v),
            ),
            _RgbSlider(
              label: 'Blue',
              value: _blue,
              onChanged: (v) => setState(() => _blue = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Use Color'),
        ),
      ],
    );
  }
}

class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            divisions: 255,
            value: value,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
