import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WmtLeavePortalPage extends StatefulWidget {
  const WmtLeavePortalPage({
    super.key,
    required this.startUrl,
    required this.faaEmail,
  });

  final String startUrl;
  final String faaEmail;

  @override
  State<WmtLeavePortalPage> createState() => _WmtLeavePortalPageState();
}

class _WmtLeavePortalPageState extends State<WmtLeavePortalPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;
  bool _finishing = false;
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

    final pageKindRaw = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const text = (document.body?.innerText || '').replace(/\s+/g, ' ');
        const title = document.title || '';
        if (/My Leave for/i.test(text) && /Final Status/i.test(text) && /Requested/i.test(text)) return 'leave';
        const hasWmtBrand = /WMT Scheduler/i.test(text) || /WMT Scheduler/i.test(title);
        const hasViews = Array.from(document.querySelectorAll('a,button,input,[onclick],td,span'))
          .some(el => /^views$/i.test(((el.innerText || el.value || el.textContent || '') + '').trim()));
        if (hasWmtBrand && hasViews) return 'wmt-home';
        return 'other';
      })();
    ''');

    final kind = pageKindRaw.toString().replaceAll('"', '');
    if (kind == 'leave') {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final rawHtml = await _controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      final html = _normalizeJavaScriptString(rawHtml);
      if (html.isNotEmpty && mounted) {
        _finishing = true;
        Navigator.of(context).pop(html);
      }
      return;
    }

    if (kind != 'wmt-home') return;
    final currentUrl = await _controller.currentUrl();
    if (currentUrl != null && currentUrl == _lastAutomationUrl) return;
    _lastAutomationUrl = currentUrl;
    await _openMyLeaveFromHome();
  }

  Future<void> _openMyLeaveFromHome() async {
    final result = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const textOf = el => ((el.innerText || el.value || el.textContent || '') + '')
          .replace(/\s+/g, ' ').trim();
        const all = () => Array.from(document.querySelectorAll(
          'a, button, input, td, span, div, [role="button"], [role="menuitem"], [onclick]'
        ));

        const direct = all().find(el => /^my\s*leave$/i.test(textOf(el)));
        if (direct) {
          if (direct.href) window.location.href = direct.href; else direct.click();
          return 'direct';
        }

        const leaveLink = Array.from(document.querySelectorAll('a')).find(a => {
          const t = textOf(a);
          const href = (a.getAttribute('href') || '').toLowerCase();
          return /^my\s*leave$/i.test(t) || (/leave/.test(href) && /my|view/.test(href));
        });
        if (leaveLink) {
          window.location.href = leaveLink.href;
          return 'href';
        }

        const views = all().find(el => /^views$/i.test(textOf(el)));
        if (!views) return 'no-views';
        for (const type of ['mouseover','mouseenter','pointerover']) {
          try { views.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, view:window})); } catch (_) {}
        }
        try { views.click(); } catch (_) {}
        setTimeout(() => {
          const mine = all().find(el => /^my\s*leave$/i.test(textOf(el)));
          if (mine) {
            if (mine.href) window.location.href = mine.href; else mine.click();
            return;
          }
          const fallback = Array.from(document.querySelectorAll('a')).find(a =>
            /^my\s*leave$/i.test(textOf(a)) || /myleave|my_leave/i.test(a.href || ''));
          if (fallback) window.location.href = fallback.href;
        }, 500);
        return 'views';
      })();
    ''');

    if (result.toString().replaceAll('"', '') == 'no-views' && mounted) {
      setState(() => _error = 'WMT loaded, but the Views menu could not be found automatically.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAA MyAccess / My Leave')),
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
              'Complete the normal FAA MyAccess sign-in. Web Schedule Manager will open Views → My Leave and save your future annual-leave requests. Sick leave is ignored here because the normal schedule update already handles it.',
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
