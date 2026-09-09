import 'package:flutter/material.dart';

import 'models/parsed_shift.dart';
import 'services/schedule_parser.dart';

void main() {
  runApp(const AtcScheduleManagerApp());
}

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
      home: const ScheduleParserPage(),
    );
  }
}

class ScheduleParserPage extends StatefulWidget {
  const ScheduleParserPage({super.key});

  @override
  State<ScheduleParserPage> createState() => _ScheduleParserPageState();
}

class _ScheduleParserPageState extends State<ScheduleParserPage> {
  final _controller = TextEditingController(text: '1400\nL1400\nQ1400\n\$1400\nX\nXtra1400');
  final _parser = const ScheduleParser();
  List<ParsedShift> _results = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    try {
      final parsed = _parser.parseLines(_controller.text);
      setState(() {
        _results = parsed;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _results = const [];
        _error = e.toString();
      });
    }
  }

  String _formatMinutes(int? minutes) {
    if (minutes == null) return '—';
    final normalized = ((minutes % 1440) + 1440) % 1440;
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    final nextDay = minutes >= 1440 ? ' +1d' : '';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}$nextDay';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ATC Schedule Manager')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Paste WMT shift codes below. One shift per line.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '1400\nL1400\n\$1400\nX',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _parse,
                icon: const Icon(Icons.schedule),
                label: const Text('Parse schedule'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final shift = _results[index];
                    return ListTile(
                      leading: Icon(shift.isDayOff
                          ? Icons.event_busy
                          : shift.isOvertime
                              ? Icons.attach_money
                              : Icons.access_time),
                      title: Text('${shift.raw}  •  ${shift.label}'),
                      subtitle: shift.isDayOff
                          ? const Text('No calendar shift')
                          : Text(
                              '${_formatMinutes(shift.effectiveStartMinutes)} → ${_formatMinutes(shift.effectiveEndMinutes)}',
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
