import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/schedule_display_settings.dart';
import 'screens/pay_period_schedule_view.dart';
import 'screens/settings_page.dart';
import 'screens/update_schedule_page.dart';
import 'services/wmt_schedule_extractor.dart';

void main() => runApp(const AtcScheduleManagerApp());

class AtcScheduleManagerApp extends StatelessWidget {
  const AtcScheduleManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ATC Schedule Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ScheduleHomePage(),
    );
  }
}

class ScheduleHomePage extends StatefulWidget {
  const ScheduleHomePage({super.key});

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage> {
  static const _htmlKey = 'saved_wmt_schedule_html';
  static const _updatedKey = 'saved_wmt_schedule_updated_at';

  final _extractor = const WmtScheduleExtractor();
  List<DatedShift> _shifts = const [];
  DateTime? _lastUpdated;
  ScheduleDisplaySettings _displaySettings = ScheduleDisplaySettings.defaults;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedSchedule();
  }

  Future<void> _loadSavedSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final html = prefs.getString(_htmlKey);
    final updated = prefs.getString(_updatedKey);
    final displaySettings = await ScheduleDisplaySettings.load();

    if (!mounted) return;

    if (html == null || html.isEmpty) {
      setState(() {
        _displaySettings = displaySettings;
        _loading = false;
      });
      return;
    }

    try {
      final shifts = _extractor.extract(html);
      setState(() {
        _shifts = shifts;
        _lastUpdated = updated == null ? null : DateTime.tryParse(updated);
        _displaySettings = displaySettings;
        _loading = false;
        _error = shifts.isEmpty ? 'Saved WMT data was found, but no schedule entries could be read.' : null;
      });
    } catch (e) {
      setState(() {
        _displaySettings = displaySettings;
        _loading = false;
        _error = 'Could not load the saved schedule.';
      });
    }
  }

  Future<void> _updateSchedule() async {
    final html = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const UpdateSchedulePage()),
    );

    if (!mounted || html == null || html.isEmpty) return;

    final shifts = _extractor.extract(html);
    if (shifts.isEmpty) {
      setState(() => _error = 'The WMT page was captured, but no schedule entries were recognized.');
      return;
    }

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_htmlKey, html);
    await prefs.setString(_updatedKey, now.toIso8601String());

    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _lastUpdated = now;
      _error = null;
    });
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<ScheduleDisplaySettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initialSettings: _displaySettings),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _displaySettings = result);
  }

  String _formatUpdated(DateTime date) {
    final hour = date.hour == 0 ? 12 : date.hour > 12 ? date.hour - 12 : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.month}/${date.day}/${date.year} at $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ATC Schedule Manager'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Update schedule',
            onPressed: _updateSchedule,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_shifts.isNotEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PayPeriodScheduleView(
                          shifts: _shifts,
                          displaySettings: _displaySettings,
                        ),
                      ),
                    ),
                    if (_lastUpdated != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.history, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Schedule data last updated: ${_formatUpdated(_lastUpdated!)}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _updateSchedule,
                      icon: const Icon(Icons.sync),
                      label: const Text('Update Schedule'),
                    ),
                  ] else ...[
                    const SizedBox(height: 80),
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved schedule yet',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect to WMT once to save your schedule on this phone. After that, the saved schedule will be the first thing you see when the app opens.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _updateSchedule,
                      icon: const Icon(Icons.sync),
                      label: const Text('Get Schedule'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
