import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WmtPortalPage extends StatefulWidget {
  const WmtPortalPage({
    super.key,
    required this.startUrl,
  });

  final String startUrl;

  @override
  State<WmtPortalPage> createState() => _WmtPortalPageState();
}

class _WmtPortalPageState extends State<WmtPortalPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;
  bool _finishing = false;
  bool _automationStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageFinished: (_) => _handlePageFinished(),
          onWebResourceError: (error) {
            // Android WebView can report ORB for a blocked subresource while the
            // FAA/WMT page itself continues to load and work normally. Do not
            // surface that nonfatal subresource error as an alarming banner.
            if (error.description.toUpperCase().contains('ERR_BLOCKED_BY_ORB')) {
              return;
            }
            if (error.isForMainFrame == false) return;
            if (mounted) setState(() => _error = error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.startUrl));
  }

  Future<void> _handlePageFinished() async {
    if (_finishing) return;

    final state = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const text = (document.body?.innerText || '').replace(/\s+/g, ' ');
        if (/Individual schedule/i.test(text) || /My Schedule/i.test(document.title || '')) {
          return 'schedule';
        }
        return 'other';
      })();
    ''');

    final value = state.toString().replaceAll('"', '');
    if (value == 'schedule') {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _captureCurrentPage();
      return;
    }

    if (_automationStarted) return;
    _automationStarted = true;

    // After MyAccess has handed us back to WMT, try the normal Views ->
    // My Schedule path automatically. If WMT changes its markup, this simply
    // does nothing and the page remains usable as a fallback.
    await _controller.runJavaScript(r'''
      (() => {
        const label = el => ((el.innerText || el.value || el.textContent || '') + '').trim();
        const candidates = Array.from(document.querySelectorAll('a, button, input, [role="button"], [role="menuitem"]'));
        const views = candidates.find(el => /^views$/i.test(label(el)));
        if (!views) return;
        views.click();
        setTimeout(() => {
          const all = Array.from(document.querySelectorAll('a, button, input, [role="button"], [role="menuitem"]'));
          const mine = all.find(el => /^my\s*schedule$/i.test(label(el)));
          if (mine) mine.click();
        }, 350);
      })();
    ''');
  }

  Future<void> _captureCurrentPage() async {
    if (_finishing) return;
    _finishing = true;

    final html = await _controller.runJavaScriptReturningResult(
      'document.documentElement.outerHTML',
    );

    if (!mounted) return;
    Navigator.of(context).pop(html.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAA MyAccess / WMT'),
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text(
              'Complete the normal FAA MyAccess sign-in. After WMT loads, ATC Schedule Manager will try to open My Schedule and capture it automatically. Your password stays inside the FAA page and is not stored by the app.',
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
