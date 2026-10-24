import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavEntry {
  const WebDavEntry({
    required this.name,
    required this.href,
    required this.isDir,
    required this.size,
  });

  final String name;
  final String href;
  final bool isDir;
  final int size;

  String get sizeText => isDir ? '' : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 最小 WebDAV 客户端：PROPFIND 列目录 + 生成带 Basic Auth 的播放 URL。
class WebDavClient {
  WebDavClient({required String baseUrl, this.user = '', this.pass = ''})
      : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String baseUrl;
  final String user;
  final String pass;

  String get _authHeader => 'Basic ' + base64Encode(utf8.encode('$user:$pass'));

  Uri uriFor(String path) {
    final p = path.isEmpty || path == '/' ? '/' : (path.startsWith('/') ? path : '/$path');
    return Uri.parse('$baseUrl$p');
  }

  Future<List<WebDavEntry>> list(String path) async {
    final uri = uriFor(path);
    final req = http.Request('PROPFIND', uri);
    req.headers['Depth'] = '1';
    req.headers['Content-Type'] = 'application/xml; charset=utf-8';
    if (user.isNotEmpty) req.headers['Authorization'] = _authHeader;
    req.body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/><d:getcontentlength/><d:resourcetype/>'
        '</d:prop></d:propfind>';

    late http.StreamedResponse res;
    try {
      res = await http.Client().send(req).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw WebDavException('无法连接: $e');
    }
    final body = await res.stream.bytesToString();
    if (res.statusCode == 401) throw WebDavException('认证失败（用户名或密码错误）');
    if (res.statusCode != 207) {
      throw WebDavException('服务器返回 HTTP ${res.statusCode}');
    }
    return _parse(body, uri);
  }

  List<WebDavEntry> _parse(String body, Uri requestUri) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (e) {
      throw WebDavException('返回内容不是合法的 WebDAV XML');
    }
    final out = <WebDavEntry>[];
    for (final resp in doc.findAllElements('response', namespace: 'DAV:')) {
      String? href;
      var isDir = false;
      var size = 0;
      String? displayName;
      for (final el in resp.descendantElements) {
        switch (el.localName) {
          case 'href':
            href ??= el.innerText.trim();
          case 'displayname':
            displayName ??= el.innerText.trim();
          case 'getcontentlength':
            size = int.tryParse(el.innerText.trim()) ?? 0;
          case 'collection':
            isDir = true;
        }
      }
      if (href == null || href.isEmpty) continue;
      final entryUri = Uri.parse(href);
      final entryPath = entryUri.path;
      final selfPath = requestUri.path.endsWith('/')
          ? requestUri.path
          : '${requestUri.path}/';
      if (entryPath == selfPath || entryPath == requestUri.path) continue;
      final decoded = Uri.decodeComponent(
          entryPath.endsWith('/') ? entryPath.substring(0, entryPath.length - 1) : entryPath);
      final name = displayName?.isNotEmpty == true
          ? displayName!
          : decoded.split('/').where((s) => s.isNotEmpty).last;
      out.add(WebDavEntry(
        name: name,
        href: decoded,
        isDir: isDir || entryPath.endsWith('/'),
        size: size,
      ));
    }
    return out;
  }

  /// mpv 直接播放用的 URL（带 Basic Auth）。
  String playUrl(String href) {
    final u = Uri.parse('$baseUrl$href');
    if (user.isEmpty) return u.toString();
    return u.replace(userInfo: '${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}').toString();
  }
}