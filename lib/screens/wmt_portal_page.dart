import 'dart:async';
import 'dart:convert';

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
  final List<String> _expectedPeriodValues = <String>[];
  int _noProgressRetries = 0;
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
            if (error.description.toUpperCase().contains('ERR_BLOCKED_BY_ORB')) return;
            if (error.isForMainFrame == false) return;
            if (mounted) setState(() => _error = error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.startUrl));
  }

  String _jsQuoted(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  String _normalizeJavaScriptString(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text.startsWith('<')) return text;
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) return decoded;
    } catch (_) {}
    return text;
  }

  Future<void> _handlePageFinished() async {
    if (_finishing) return;

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
        if (!candidate || (candidate.value || '').trim() === email) return;
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
      await Future<void>.delayed(const Duration(milliseconds: 700));
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
          if (direct.href) window.location.href = direct.href; else direct.click();
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
            if (mine.href) window.location.href = mine.href; else mine.click();
            return;
          }
          const fallback = Array.from(document.querySelectorAll('a')).find(a =>
            /my\s*schedule/i.test(textOf(a)) || /myschedule|my_schedule/i.test(a.href || ''));
          if (fallback) window.location.href = fallback.href;
        }, 500);
        return 'views';
      })();
    ''');

    if (result.toString().replaceAll('"', '') == 'no-views' && mounted) {
      setState(() => _error = 'WMT loaded, but the Views menu could not be found automatically.');
    }
  }

  Future<Map<String, dynamic>?> _readPayPeriodMetadata() async {
    final raw = await _controller.runJavaScriptReturningResult(r'''
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
          selectedValue:(select.value || select.options[select.selectedIndex]?.text || '').trim(),
          options:Array.from(select.options || []).map(o => ({
            value:(o.value || o.text || '').trim(),
            text:(o.text || '').trim()
          }))
        });
      })();
    ''');

    final text = _normalizeJavaScriptString(raw);
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> _captureScheduleAndAdvance() async {
    if (_finishing || _collectingPayPeriods) return;
    _collectingPayPeriods = true;

    try {
      final metadata = await _readPayPeriodMetadata();
      if (metadata == null || metadata['found'] != true) {
        _collectingPayPeriods = false;
        if (_capturedPages.isNotEmpty) await _finishWithCapturedPages();
        return;
      }

      final options = (metadata['options'] as List? ?? const [])
          .map((item) {
            if (item is! Map) return '';
            final value = (item['value'] ?? '').toString().trim();
            final text = (item['text'] ?? '').toString().trim();
            return value.isNotEmpty ? value : text;
          })
          .where((value) => value.isNotEmpty)
          .toList();

      final selectedValue = (metadata['selectedValue'] ?? '').toString().trim();

      // WMT My Schedule opens on the current pay period. Capture that period
      // and only the periods after it; older periods in the dropdown are ignored.
      if (_expectedPeriodValues.isEmpty) {
        var currentIndex = metadata['selectedIndex'] is int
            ? metadata['selectedIndex'] as int
            : options.indexOf(selectedValue);
        if (currentIndex < 0 || currentIndex >= options.length) {
          currentIndex = options.indexOf(selectedValue);
        }
        if (currentIndex < 0) currentIndex = 0;
        _expectedPeriodValues.addAll(options.skip(currentIndex));
      }

      if (selectedValue.isNotEmpty && !_capturedPeriodValues.contains(selectedValue)) {
        final rawHtml = await _controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
        final html = _normalizeJavaScriptString(rawHtml);
        if (html.isNotEmpty) {
          _capturedPages.add(html);
          _capturedPeriodValues.add(selectedValue);
          _noProgressRetries = 0;
        }
      }

      String? nextValue;
      for (final value in _expectedPeriodValues) {
        if (!_capturedPeriodValues.contains(value)) {
          nextValue = value;
          break;
        }
      }

      if (nextValue == null) {
        _collectingPayPeriods = false;
        await _finishWithCapturedPages();
        return;
      }

      final jsNextValue = _jsQuoted(nextValue);
      final advanceRaw = await _controller.runJavaScriptReturningResult('''
        (() => {
          const targetValue = '$jsNextValue';
          const selects = Array.from(document.querySelectorAll('select'));
          const select = selects.find(s => {
            const nearby = ((s.parentElement?.innerText || '') + ' ' +
              (s.previousElementSibling?.textContent || '')).replace(/\\s+/g, ' ');
            return /pay\\s*period/i.test(nearby) ||
              Array.from(s.options || []).some(o => /^\\d{6}\$/.test((o.value || o.text || '').trim()));
          });
          if (!select) return 'no-select';
          const option = Array.from(select.options || []).find(o =>
            ((o.value || o.text || '').trim() === targetValue));
          if (!option) return 'no-option';
          select.value = option.value;
          if (select.value !== option.value) select.selectedIndex = option.index;
          select.dispatchEvent(new Event('input', {bubbles:true}));
          select.dispatchEvent(new Event('change', {bubbles:true}));
          try {
            if (typeof select.onchange === 'function') select.onchange();
          } catch (_) {}
          setTimeout(() => {
            const parent = select.parentElement || document;
            const controls = Array.from(parent.querySelectorAll('button,input[type="submit"],input[type="button"],a'));
            const go = controls.find(el => /^(go|view|submit|select)\$/i.test(
              ((el.innerText || el.value || el.textContent || '') + '').trim()));
            if (go) { try { go.click(); } catch (_) {} }
          }, 150);
          return 'advanced:' + targetValue;
        })();
      ''');

      final advance = advanceRaw.toString().replaceAll('"', '');
      _collectingPayPeriods = false;

      if (advance == 'no-select' || advance == 'no-option') {
        _noProgressRetries++;
        if (_noProgressRetries >= 5) {
          if (mounted) {
            setState(() => _error =
                'WMT offered ${_expectedPeriodValues.length} current/future pay periods, but only ${_capturedPeriodValues.length} could be loaded.');
          }
          await _finishWithCapturedPages();
          return;
        }
      }

      Future<void>.delayed(const Duration(seconds: 3), () async {
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
              'Complete the normal FAA MyAccess sign-in. ATC Schedule Manager will fill your FAA email when possible, then try to open My Schedule and collect the current and all future available pay periods automatically. Your password stays inside the FAA page and is not stored by the app.',
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
