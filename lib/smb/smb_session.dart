import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/smb_accounts.dart';
import 'smb_client.dart';
import 'smb_proxy.dart';

/// 当前 SMB 会话（一个进程内只保留一个连接 + 一个代理）。
class SmbSession {
  static SmbClient? _client;
  static SmbProxy? _proxy;
  static String? _key;

  static String _keyOf(SmbAccount a) =>
      '${a.server}|${a.share}|${a.user}|${a.domain}';

  static Future<SmbClient> client(SmbAccount account) async {
    final key = _keyOf(account);
    if (_client != null && _key == key) return _client!;
    await reset();
    final c = await SmbClient.spawn();
    await c.connect(
      server: account.server,
      share: account.share,
      user: account.user,
      pass: account.pass,
      domain: account.domain,
    );
    debugPrint('[smb] connected $key');
    _client = c;
    _key = key;
    _proxy = await SmbProxy.start(c);
    return c;
  }

  static Future<SmbProxy> proxy(SmbAccount account) async {
    await client(account);
    return _proxy!;
  }

  /// 生成可交给 mpv 播放的本地 URL。
  static Future<String> urlFor(SmbAccount account, String path) async {
    final p = await proxy(account);
    final url = await p.expose(path);
    debugPrint('[smb] expose $path -> $url');
    return url;
  }

  static Future<void> reset() async {
    await _proxy?.dispose();
    _proxy = null;
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
    _key = null;
  }
}

/// smb://[user[:pass]@]host/share/path  或  smb2://{json}
class SmbUrl {
  SmbUrl({
    required this.server,
    required this.share,
    required this.path,
    required this.user,
    required this.pass,
    required this.domain,
  });

  final String server;
  final String share;
  final String path;
  final String user;
  final String pass;
  final String domain;

  static SmbUrl? parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme == 'smb2' || raw.startsWith('smb2://')) {
      final body = raw.substring('smb2://'.length);
      try {
        final m = jsonDecode(body) as Map<String, dynamic>;
        final p = (m['path'] as String?) ?? '/';
        return SmbUrl(
          server: (m['server'] as String?) ?? '',
          share: (m['share'] as String?) ?? '',
          path: p.startsWith('/') ? p : '/$p',
          user: (m['username'] as String?) ?? '',
          pass: (m['password'] as String?) ?? '',
          domain: (m['domain'] as String?) ?? '',
        );
      } catch (_) {
        return null;
      }
    }
    if (uri.scheme != 'smb') return null;
    final segs = uri.pathSegments;
    if (segs.isEmpty) return null;
    final share = segs.first;
    final path = segs.length > 1 ? '/${segs.skip(1).join("/")}' : '/';
    return SmbUrl(
      server: uri.host,
      share: share,
      path: path,
      user: uri.userInfo.split(':').first,
      pass: uri.userInfo.contains(':') ? uri.userInfo.split(':').sublist(1).join(':') : '',
      domain: '',
    );
  }

  SmbAccount toAccount() => SmbAccount(
        server: server,
        share: share,
        user: user,
        pass: pass,
        domain: domain,
      );
}