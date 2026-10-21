/// A tiny web server on 127.0.0.1 that serves the app's own `assets/web/` folder to its WebViews.
///
/// The 3D model page and the game are three.js ES modules (assets/web/lib), and Android's WebView
/// blocks module imports for pages loaded from file://. Only this device can reach the server
/// (loopback), and it serves nothing but the bundled assets. It keeps one port when it can, so the
/// pages' origin stays the same and the game's saved arm calibration and settings (localStorage)
/// survive app restarts.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  /// The pages' port (their origin, so their localStorage belongs to it).
  static const fixedPort = 47811;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final Map<String, Uint8List> _cache = {};

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    'ttf': 'font/ttf',
    'png': 'image/png',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'css': 'text/css',
    'txt': 'text/plain; charset=utf-8',
  };

  /// `http://127.0.0.1:<port>/<path>` for a file under assets/web/.
  Future<Uri> url(String path) async {
    final s = await (_starting ??= _start());
    return Uri.parse('http://127.0.0.1:${s.port}/$path');
  }

  Future<HttpServer> _start() async {
    HttpServer s;
    try {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, fixedPort);
    } on SocketException {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // taken: any port (settings reset)
    }
    s.listen(_serve);
    _server = s;
    return s;
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path.endsWith('/')) path += 'index.html';
      if (path.contains('..')) throw const FileSystemException('bad path');
      final key = 'assets/web$path';
      final bytes = _cache[key] ??= (await rootBundle.load(key)).buffer.asUint8List();
      final ext = path.split('.').last.toLowerCase();
      res.headers
        ..set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      res.contentLength = bytes.length;
      res.add(bytes);
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }

  /// Drops cached files when no page needs them.
  void releaseCache() => _cache.clear();

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
    _cache.clear();
  }
}
