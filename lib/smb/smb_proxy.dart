import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'smb_client.dart';

class _Served {
  _Served(this.fh, this.size, this.name);
  final int fh;
  final int size;
  final String name;
}

/// 把 SMB 文件以 HTTP Range 的形式暴露给 libmpv（127.0.0.1）。
///
/// 这样不需要给 mpv 写自定义流协议：mpv 原生支持 http，按 Range 拉数据即可。
class SmbProxy {
  SmbProxy._(this._server, this._client);

  final HttpServer _server;
  final SmbClient _client;
  final Map<String, _Served> _files = {};
  final Random _rnd = Random.secure();

  static Future<SmbProxy> start(SmbClient client) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = SmbProxy._(server, client);
    server.listen(proxy._handle);
    return proxy;
  }

  int get port => _server.port;

  Future<String> expose(String smbPath, {String? name}) async {
    final (fh, size) = await _client.open(smbPath);
    debugPrint('[smb] open $smbPath fh=$fh size=$size');
    final token = List.generate(16, (_) => _rnd.nextInt(16).toRadixString(16)).join();
    _files[token] = _Served(fh, size, name ?? smbPath.split('/').last);
    return 'http://127.0.0.1:$port/s/$token';
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segs = req.uri.pathSegments;
      if (segs.length != 2 || segs[0] != 's') {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      final served = _files[segs[1]];
      if (served == null) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final total = served.size;
      var start = 0;
      var end = total - 1;
      var partial = false;

      final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final spec = rangeHeader.substring(6).split(',');
        final first = spec.first.trim();
        final dash = first.indexOf('-');
        if (dash >= 0) {
          final a = first.substring(0, dash);
          final b = first.substring(dash + 1);
          if (a.isNotEmpty) start = int.tryParse(a) ?? 0;
          if (b.isNotEmpty) end = min(int.tryParse(b) ?? (total - 1), total - 1);
          partial = true;
        }
      }

      if (start > end || start >= total) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await req.response.close();
        return;
      }

      final length = end - start + 1;
      final res = req.response;
      res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      res.headers.contentType = ContentType.binary;
      res.headers.set(HttpHeaders.contentLengthHeader, '$length');
      if (partial) {
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }

      if (req.method == 'HEAD') {
        await res.close();
        return;
      }

      const chunk = 256 * 1024;
      var offset = start;
      var remaining = length;
      while (remaining > 0) {
        final want = min(chunk, remaining);
        final data = await _client.read(served.fh, offset, want);
        if (data.isEmpty) break;
        res.add(data);
        offset += data.length;
        remaining -= data.length;
        if (data.length < want) break;
      }
      await res.close();
    } catch (e) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _server.close(force: true);
  }
}