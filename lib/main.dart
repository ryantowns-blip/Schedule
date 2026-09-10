import 'package:flutter/material.dart';

import 'models/parsed_shift.dart';
import 'screens/wmt_portal_page.dart';
import 'services/schedule_parser.dart';
import 'services/wmt_auth_service.dart';
import 'services/wmt_schedule_extractor.dart';

const _wmtLoginUrl = 'https://wmtscheduler.faa.gov/WMT_LogOn/';

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
  final _emailController = TextEditingController();
  final _parser = const ScheduleParser();
  final _auth = WmtAuthService();
  final _extractor = const WmtScheduleExtractor();
  List<ParsedShift> _results = const [];
  List<DatedShift> _wmtShifts = const [];
  String? _error;
  String? _wmtError;
  String? _capturedWmtHtml;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
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

  void _beginLogin() => setState(_auth.beginLogin);

  void _submitEmail() {
    setState(() {
      _auth.submitEmail(_emailController.text);
    });
  }

  Future<void> _openMyAccess() async {
    final html = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const WmtPortalPage(startUrl: _wmtLoginUrl),
      ),
    );

    if (!mounted || html == null || html.isEmpty) return;

    final extracted = _extractor.extract(html);
    setState(() {
      _capturedWmtHtml = html;
      _wmtShifts = extracted;
      _wmtError = extracted.isEmpty
          ? 'WMT page captured, but no dated shifts were recognized yet.'
          : null;
      _auth.authenticationSucceeded();
    });
  }

  void _signOut() {
    _emailController.clear();
    setState(() {
      _capturedWmtHtml = null;
      _wmtShifts = const [];
      _wmtError = null;
      _auth.signOut();
    });
  }

  String _formatMinutes(int? minutes) {
    if (minutes == null) return '—';
    final normalized = ((minutes % 1440) + 1440) % 1440;
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    final nextDay = minutes >= 1440 ? ' +1d' : '';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}$nextDay';
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildWmtCard() {
    final state = _auth.state;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync),
                const SizedBox(width: 8),
                Text('WMT Scheduler', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (state.step == WmtAuthStep.signedOut) ...[
              const Text('Connect to WMT through the FAA MyAccess login flow.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _beginLogin,
                icon: const Icon(Icons.login),
                label: const Text('Connect to WMT'),
              ),
            ] else if (state.step == WmtAuthStep.email) ...[
              const Text('Step 1 of 2 — enter your FAA email address.'),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'FAA email',
                  border: const OutlineInputBorder(),
                  errorText: state.message,
                ),
                onSubmitted: (_) => _submitEmail(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _submitEmail, child: const Text('Continue')),
            ] else if (state.step == WmtAuthStep.password) ...[
              Text('Step 2 of 2 — MyAccess sign-in for ${state.email ?? 'your FAA account'}.'),
              const SizedBox(height: 8),
              const Text(
                'Your password is entered only inside the FAA MyAccess page and is not stored by ATC Schedule Manager.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openMyAccess,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open FAA MyAccess'),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle),
                title: const Text('WMT session captured'),
                subtitle: Text(
                  _capturedWmtHtml == null
                      ? (state.email ?? 'FAA account')
                      : '${state.email ?? 'FAA account'} • page captured',
                ),
              ),
              if (_wmtError != null) ...[
                Text(
                  _wmtError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              if (_wmtShifts.isNotEmpty) ...[
                Text(
                  'Review imported schedule (${_wmtShifts.length} shifts)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ..._wmtShifts.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(entry.shift.isDayOff
                        ? Icons.event_busy
                        : entry.shift.isOvertime
                            ? Icons.attach_money
                            : Icons.access_time),
                    title: Text('${_formatDate(entry.date)} • ${entry.shift.raw}'),
                    subtitle: entry.shift.isDayOff
                        ? const Text('Day off')
                        : Text(
                            '${entry.shift.label}\n${_formatMinutes(entry.shift.effectiveStartMinutes)} → ${_formatMinutes(entry.shift.effectiveEndMinutes)}',
                          ),
                  ),
                ),
              ],
              OutlinedButton(onPressed: _signOut, child: const Text('Disconnect')),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ATC Schedule Manager')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildWmtCard(),
            const SizedBox(height: 12),
            const Text(
              'Paste WMT shift codes below. One shift per line.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 6,
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
            ..._results.map(
              (shift) => ListTile(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
