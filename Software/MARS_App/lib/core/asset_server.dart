/// A tiny web server on 127.0.0.1 that serves the app's own `assets/web/` folder to its WebViews.
///
/// The 3D model page (three.js modules + a glTF with a separate .bin) and the game (Godot web
/// export: .wasm + .pck) fetch their files, and Android's WebView blocks that for pages loaded from
/// file:// (DYNABO's game only needed plain scripts, so it could use loadFlutterAsset). Only this
/// device can reach the server (loopback), and it serves nothing but the bundled assets.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final Map<String, Uint8List> _cache = {};

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    'gltf': 'model/gltf+json',
    'bin': 'application/octet-stream',
    'wasm': 'application/wasm',
    'pck': 'application/octet-stream',
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
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
        ..set(HttpHeaders.cacheControlHeader, 'no-cache')
        // Godot's web export can also run threaded builds with these; harmless for the others
        ..set('Cross-Origin-Opener-Policy', 'same-origin')
        ..set('Cross-Origin-Embedder-Policy', 'require-corp');
      res.contentLength = bytes.length;
      res.add(bytes);
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }

  /// Drops cached files (the game's ~40 MB engine) when no page needs them.
  void releaseCache() => _cache.clear();

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
    _cache.clear();
  }
}
