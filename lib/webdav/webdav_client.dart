import 'dart:convert';

import 'dart:io';

import '../data/webdav_accounts.dart';
import '../util/text.dart';

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
    } on HandshakeException {
      throw WebDavException(
          'TLS 握手失败：这个地址用的是 https://，但服务器看起来只支持 http://。请把地址改成 http:// 开头。');
    } on SocketException catch (e) {
      throw WebDavException('无法连接服务器（检查地址、端口和防火墙）: $e');
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

class WebDavResult {
  WebDavResult(this.client, this.entries);
  final WebDavClient client;
  final List<WebDavEntry> entries;
}

/// 列目录；如果地址误写成 https 而服务器只支持 http，会自动降级重试并写回账号。
Future<WebDavResult> listWebDav(WebDavAccount account, String path) async {
  // 依次尝试：原样 → https 降级 http → 全角转半角（凭据）→ 两者组合
  final candidates = <WebDavAccount>[account];
  if (account.url.startsWith('https://')) {
    candidates.add(WebDavAccount(
      url: 'http://${account.url.substring('https://'.length)}',
      user: account.user,
      pass: account.pass,
      alias: account.alias,
    ));
  }
  final u = toHalfWidth(account.user);
  final pw = toHalfWidth(account.pass);
  if (u != account.user || pw != account.pass) {
    for (final c in [...candidates]) {
      candidates.add(WebDavAccount(
        url: c.url,
        user: u,
        pass: pw,
        alias: account.alias,
      ));
    }
  }

  WebDavException? last;
  for (final c in candidates) {
    try {
      final client = WebDavClient(baseUrl: c.url, user: c.user, pass: c.pass);
      final entries = await client.list(path);
      if (c.url != account.url || c.user != account.user || c.pass != account.pass) {
        await WebDavAccountStore().replace(account, c);
      }
      return WebDavResult(client, entries);
    } on WebDavException catch (e) {
      last = e;
    }
  }
  throw last ?? WebDavException('连接失败');
}