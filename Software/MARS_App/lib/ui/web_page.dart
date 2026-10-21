/// A bundled web page (assets/web/...) in a WebView, with a message bridge, as DYNABO's game view:
///   app -> page:  [setGlobal] runs `window.<name> = <json>` (newest value wins while a call runs)
///   page -> app:  `<channel>.postMessage(text)`   (JavaScript channel)
/// Tests can't create a platform WebView, so pages are built through [webPagesEnabled].
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/asset_server.dart';
import 'theme.dart' as th;

/// False in widget tests: pages show a placeholder instead of a WebView.
bool webPagesEnabled = true;

class LocalWebPage {
  LocalWebPage({required this.path, required this.channel, this.onMessage, Color background = th.card}) {
    if (!webPagesEnabled) return;
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(background)
      ..addJavaScriptChannel(channel, onMessageReceived: (m) => onMessage?.call(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // only the app's own pages, never the internet
        onNavigationRequest: (r) => r.url.startsWith('http://127.0.0.1:') ? NavigationDecision.navigate : NavigationDecision.prevent,
      ));
    AssetServer.instance.url(path).then((u) => _ctl!.loadRequest(u));
  }

  final String path;
  final String channel;
  void Function(String message)? onMessage;
  WebViewController? _ctl;

  final Map<String, String> _pending = {};
  final Set<String> _busy = {};

  Widget build() {
    final c = _ctl;
    if (c == null) {
      return const Center(child: Text('(web page: not available here)', style: th.faint));
    }
    return WebViewWidget(controller: c);
  }

  /// `window.<name> = <value as JSON>`. Values that come faster than the page takes them are
  /// replaced by the newest one, so the bridge never builds up a queue.
  void setGlobal(String name, Object? value) {
    final c = _ctl;
    if (c == null) return;
    final js = 'window.$name = ${jsonEncode(value)};';
    if (_busy.contains(name)) {
      _pending[name] = js;
      return;
    }
    _run(c, name, js);
  }

  void _run(WebViewController c, String name, String js) {
    _busy.add(name);
    c.runJavaScript(js).catchError((_) {}).whenComplete(() {
      _busy.remove(name);
      final next = _pending.remove(name);
      if (next != null) _run(c, name, next);
    });
  }

  Future<void> reload() async => _ctl?.reload();

  /// Runs `js` in the page and returns its result as a string ('' when there is no page or it fails).
  Future<String> evaluate(String js) async {
    final c = _ctl;
    if (c == null) return '';
    try {
      final r = await c.runJavaScriptReturningResult(js);
      final v = r.toString();
      return v.length >= 2 && v.startsWith('"') && v.endsWith('"') ? v.substring(1, v.length - 1) : v;
    } catch (_) {
      return '';
    }
  }
}
