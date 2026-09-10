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
  bool _navigationAttempted = false;
  bool _collectingPayPeriods = false;
  final List<String> _capturedPages = <String>[];
  final Set<String> _capturedPeriodValues = <String>{};

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
            // FAA/WMT page itself continues to load and work normally.
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

    final pageKind = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const text = (document.body?.innerText || '').replace(/\s+/g, ' ');
        const hasSchedule = /Individual schedule/i.test(text);
        const hasPayPeriod = /Select Pay Period/i.test(text) && document.querySelector('select');
        if (hasSchedule && hasPayPeriod) return 'schedule';
        return 'other';
      })();
    ''');

    final kind = pageKind.toString().replaceAll('"', '');
    if (kind == 'schedule') {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _captureScheduleAndAdvance();
      return;
    }

    if (_navigationAttempted) return;
    _navigationAttempted = true;

    // Try to follow WMT's Views -> My Schedule menu without user taps.
    await _controller.runJavaScript(r'''
      (() => {
        const textOf = el => ((el.innerText || el.value || el.textContent || '') + '')
            .replace(/\s+/g, ' ').trim();
        const clickable = () => Array.from(document.querySelectorAll(
          'a, button, input, option, [role="button"], [role="menuitem"], [onclick]'
        ));

        const direct = clickable().find(el => /^my\s*schedule$/i.test(textOf(el)));
        if (direct) {
          direct.click();
          return 'direct';
        }

        const views = clickable().find(el => /^views$/i.test(textOf(el)));
        if (!views) return 'none';
        views.click();
        setTimeout(() => {
          const mine = clickable().find(el => /^my\s*schedule$/i.test(textOf(el)));
          if (mine) mine.click();
        }, 600);
        return 'views';
      })();
    ''');
  }

  Future<void> _captureScheduleAndAdvance() async {
    if (_finishing || _collectingPayPeriods) return;
    _collectingPayPeriods = true;

    try {
      final metadata = await _controller.runJavaScriptReturningResult(r'''
        (() => {
          const selects = Array.from(document.querySelectorAll('select'));
          const select = selects.find(s => {
            const nearby = ((s.parentElement?.innerText || '') + ' ' +
              (s.previousElementSibling?.textContent || '')).replace(/\s+/g, ' ');
            return /pay\s*period/i.test(nearby) ||
              Array.from(s.options || []).some(o => /^\d{6}$/.test((o.value || o.text || '').trim()));
          });
          if (!select) return JSON.stringify({found:false});
          const options = Array.from(select.options).map((o, index) => ({
            index,
            value:(o.value || '').trim(),
            text:(o.text || '').trim()
          }));
          return JSON.stringify({
            found:true,
            selectedIndex:select.selectedIndex,
            selectedValue:(select.value || '').trim(),
            options
          });
        })();
      ''');

      final metaText = metadata.toString().replaceAll(r'\"', '"');
      final selectedMatch = RegExp(r'"selectedValue":"([^"]*)"').firstMatch(metaText);
      final selectedValue = selectedMatch?.group(1) ?? '';

      if (selectedValue.isNotEmpty && _capturedPeriodValues.contains(selectedValue)) {
        await _finishWithCapturedPages();
        return;
      }

      final html = await _controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      _capturedPages.add(html.toString());
      if (selectedValue.isNotEmpty) _capturedPeriodValues.add(selectedValue);

      final advanceResult = await _controller.runJavaScriptReturningResult(r'''
        (() => {
          const selects = Array.from(document.querySelectorAll('select'));
          const select = selects.find(s => {
            const nearby = ((s.parentElement?.innerText || '') + ' ' +
              (s.previousElementSibling?.textContent || '')).replace(/\s+/g, ' ');
            return /pay\s*period/i.test(nearby) ||
              Array.from(s.options || []).some(o => /^\d{6}$/.test((o.value || o.text || '').trim()));
          });
          if (!select) return 'no-select';
          const nextIndex = select.selectedIndex + 1;
          if (nextIndex >= select.options.length) return 'done';

          select.selectedIndex = nextIndex;
          const nextValue = (select.options[nextIndex].value || select.options[nextIndex].text || '').trim();

          // WMT may use either a normal change handler or an ASP.NET-style
          // postback. Dispatch change first, then invoke onchange if necessary.
          const event = new Event('change', {bubbles:true});
          select.dispatchEvent(event);
          if (typeof select.onchange === 'function') {
            try { select.onchange(); } catch (_) {}
          }
          return 'advanced:' + nextValue;
        })();
      ''');

      final result = advanceResult.toString().replaceAll('"', '');
      if (result == 'done' || result == 'no-select') {
        await _finishWithCapturedPages();
        return;
      }

      // A successful selection normally causes WMT to reload/post back. Release
      // the guard so onPageFinished can capture the next pay period.
      _collectingPayPeriods = false;

      // Fallback for pages that update in-place instead of navigating.
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (!mounted || _finishing || _collectingPayPeriods) return;
        await _captureScheduleAndAdvance();
      });
    } catch (e) {
      _collectingPayPeriods = false;
      if (mounted) {
        setState(() => _error = 'Automatic schedule collection paused: $e');
      }
    }
  }

  Future<void> _finishWithCapturedPages() async {
    if (_finishing) return;
    _finishing = true;
    if (!mounted) return;

    // The existing extractor scans the returned text for dated WMT cells, so
    // concatenating each captured pay-period page lets it parse all periods in
    // one pass without changing credential handling.
    Navigator.of(context).pop(_capturedPages.join('\n<!-- ATC_PAY_PERIOD_BREAK -->\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAA MyAccess / WMT')),
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
              'Complete the normal FAA MyAccess sign-in. ATC Schedule Manager will try to open My Schedule, then collect the selected and future pay periods automatically. Your password stays inside the FAA page and is not stored by the app.',
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
