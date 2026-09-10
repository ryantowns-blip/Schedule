import 'package:flutter/material.dart';

import '../services/wmt_auth_service.dart';
import 'wmt_leave_portal_page.dart';

const _wmtLoginUrl = 'https://wmtscheduler.faa.gov/WMT_LogOn/';

class UpdateLeavePage extends StatefulWidget {
  const UpdateLeavePage({super.key});

  @override
  State<UpdateLeavePage> createState() => _UpdateLeavePageState();
}

class _UpdateLeavePageState extends State<UpdateLeavePage> {
  final _emailController = TextEditingController();
  final _auth = WmtAuthService();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _beginLogin() => setState(_auth.beginLogin);
  void _submitEmail() => setState(() => _auth.submitEmail(_emailController.text));

  Future<void> _openMyAccess() async {
    final email = (_auth.state.email ?? _emailController.text).trim();
    final html = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WmtLeavePortalPage(
          startUrl: _wmtLoginUrl,
          faaEmail: email,
        ),
      ),
    );
    if (!mounted || html == null || html.isEmpty) return;
    Navigator.of(context).pop(html);
  }

  @override
  Widget build(BuildContext context) {
    final state = _auth.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Refresh Upcoming Leave')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.beach_access_outlined),
                        const SizedBox(width: 8),
                        Text('WMT My Leave', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.step == WmtAuthStep.signedOut) ...[
                      const Text('Sign in through FAA MyAccess to refresh future annual-leave requests from Views → My Leave.'),
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
                    ] else ...[
                      Text('Step 2 of 2 — MyAccess sign-in for ${state.email ?? 'your FAA account'}.'),
                      const SizedBox(height: 8),
                      const Text('Your password stays inside the FAA page and is not stored by Web Schedule Manager.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _openMyAccess,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Open FAA MyAccess'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
