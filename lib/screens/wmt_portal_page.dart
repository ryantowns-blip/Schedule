import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WmtPortalPage extends StatefulWidget {
  const WmtPortalPage({
    super.key,
    required this.startUrl,
    required this.faaEmail,
  });

  final String startUrl;
  final String faaEmail;

  @override
  State<WmtPortalPage> createState() => _WmtPortalPageState();
}

class _WmtPortalPageState extends State<WmtPortalPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;
  bool _finishing = false;
  bool _collectingPayPeriods = false;
  final List<String> _capturedPages = <String>[];
  final Set<String> _capturedPeriodValues = <String>{};
  String? _lastAutomationUrl;

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

  String _jsQuoted(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
  }

  Future<void> _handlePageFinished() async {
    if (_finishing) return;

    // First, fill the FAA/MyAccess email field when that page is visible.
    final email = _jsQuoted(widget.faaEmail);
    await _controller.runJavaScript('''
      (() => {
        const email = '$email';
        if (!email) return;
        const inputs = Array.from(document.querySelectorAll('input'));
        const candidate = inputs.find(i => {
          const haystack = [i.type, i.name, i.id, i.placeholder, i.autocomplete, i.getAttribute('aria-label')]
            .filter(Boolean).join(' ').toLowerCase();
          return i.type === 'email' || /email|user|login|username|identifier/.test(haystack);
        });
        if (!candidate) return;
        if ((candidate.value || '').trim() === email) return;
        candidate.focus();
        candidate.value = email;
        candidate.dispatchEvent(new Event('input', {bubbles:true}));
        candidate.dispatchEvent(new Event('change', {bubbles:true}));
      })();
    ''');

    final pageKind = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const text = (document.body?.innerText || '').replace(/\s+/g, ' ');
        const title = document.title || '';
        const hasSchedule = /Individual schedule/i.test(text);
        const hasPayPeriod = /Select Pay Period/i.test(text) && document.querySelector('select');
        if (hasSchedule && hasPayPeriod) return 'schedule';

        const hasWmtBrand = /WMT Scheduler/i.test(text) || /WMT Scheduler/i.test(title);
        const hasViews = Array.from(document.querySelectorAll('a,button,input,[onclick],td,span'))
          .some(el => /^views$/i.test(((el.innerText || el.value || el.textContent || '') + '').trim()));
        if (hasWmtBrand && hasViews) return 'wmt-home';
        return 'other';
      })();
    ''');

    final kind = pageKind.toString().replaceAll('"', '');
    if (kind == 'schedule') {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _captureScheduleAndAdvance();
      return;
    }

    if (kind != 'wmt-home') return;

    final currentUrl = await _controller.currentUrl();
    if (currentUrl != null && currentUrl == _lastAutomationUrl) return;
    _lastAutomationUrl = currentUrl;

    await _openMyScheduleFromHome();
  }

  Future<void> _openMyScheduleFromHome() async {
    final result = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const textOf = el => ((el.innerText || el.value || el.textContent || '') + '')
          .replace(/\s+/g, ' ').trim();
        const all = () => Array.from(document.querySelectorAll(
          'a, button, input, td, span, div, [role="button"], [role="menuitem"], [onclick]'
        ));

        const direct = all().find(el => /^my\s*schedule$/i.test(textOf(el)));
        if (direct) {
          if (direct.href) window.location.href = direct.href;
          else direct.click();
          return 'direct';
        }

        const scheduleLink = Array.from(document.querySelectorAll('a')).find(a => {
          const t = textOf(a);
          const href = (a.getAttribute('href') || '').toLowerCase();
          return /my\s*schedule/i.test(t) || (/schedule/.test(href) && /view|individual|my/.test(href));
        });
        if (scheduleLink) {
          window.location.href = scheduleLink.href;
          return 'href';
        }

        const views = all().find(el => /^views$/i.test(textOf(el)));
        if (!views) return 'no-views';

        for (const type of ['mouseover','mouseenter','pointerover']) {
          try { views.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, view:window})); } catch (_) {}
        }
        try { views.click(); } catch (_) {}

        setTimeout(() => {
          const mine = all().find(el => /^my\s*schedule$/i.test(textOf(el)));
          if (mine) {
            if (mine.href) window.location.href = mine.href;
            else mine.click();
            return;
          }
          const anchors = Array.from(document.querySelectorAll('a'));
          const fallback = anchors.find(a => /my\s*schedule/i.test(textOf(a)) || /myschedule|my_schedule/i.test(a.href || ''));
          if (fallback) window.location.href = fallback.href;
        }, 500);
        return 'views';
      })();
    ''');

    final value = result.toString().replaceAll('"', '');
    if (value == 'no-views' && mounted) {
      setState(() => _error = 'WMT loaded, but the Views menu could not be found automatically.');
    }
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
          return JSON.stringify({
            found:true,
            selectedIndex:select.selectedIndex,
            selectedValue:(select.value || '').trim(),
            optionCount:select.options.length
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
          select.dispatchEvent(new Event('change', {bubbles:true}));
          if (typeof select.onchange === 'function') {
            try { select.onchange(); } catch (_) {}
          }
          return 'advanced:' + nextValue;
        })();
      ''');

      final value = advanceResult.toString().replaceAll('"', '');
      if (value == 'done' || value == 'no-select') {
        await _finishWithCapturedPages();
        return;
      }

      _collectingPayPeriods = false;
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (!mounted || _finishing || _collectingPayPeriods) return;
        await _captureScheduleAndAdvance();
      });
    } catch (e) {
      _collectingPayPeriods = false;
      if (mounted) setState(() => _error = 'Automatic schedule collection paused: $e');
    }
  }

  Future<void> _finishWithCapturedPages() async {
    if (_finishing) return;
    _finishing = true;
    if (!mounted) return;
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
              'Complete the normal FAA MyAccess sign-in. ATC Schedule Manager will fill your FAA email when possible, then try to open My Schedule and collect the selected and future pay periods automatically. Your password stays inside the FAA page and is not stored by the app.',
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
