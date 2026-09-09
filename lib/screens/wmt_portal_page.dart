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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => setState(() => _progress = progress),
          onWebResourceError: (error) {
            setState(() => _error = error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.startUrl));
  }

  Future<void> _captureCurrentPage() async {
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
        actions: [
          IconButton(
            tooltip: 'Capture WMT page',
            onPressed: _captureCurrentPage,
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
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
              'Complete the normal FAA MyAccess sign-in here. Password entry stays inside the secure browser page; ATC Schedule Manager does not store it. Once WMT is visible, tap the download icon to capture the current page for schedule parsing.',
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
