import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WebDavAccount {
  const WebDavAccount({required this.url, required this.user, required this.pass, this.alias = ''});

  final String url;
  final String user;
  final String pass;
  final String alias;

  String get label => alias.isNotEmpty ? alias : (user.isEmpty ? url : '$user@$url');

  Map<String, Object?> toJson() => {'url': url, 'user': user, 'pass': pass, 'alias': alias};

  factory WebDavAccount.fromJson(Map<String, dynamic> m) => WebDavAccount(
        url: (m['url'] as String?) ?? '',
        user: (m['user'] as String?) ?? '',
        pass: (m['pass'] as String?) ?? '',
        alias: (m['alias'] as String?) ?? '',
      );
}

class WebDavAccountStore {
  static const _key = 'webdav_accounts';

  Future<List<WebDavAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().map(WebDavAccount.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<WebDavAccount> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> add(WebDavAccount a) async => save([...await load(), a]);

  Future<void> replace(WebDavAccount oldAccount, WebDavAccount next) async {
    final list = [...await load()];
    for (var i = 0; i < list.length; i++) {
      if (list[i].url == oldAccount.url && list[i].user == oldAccount.user) {
        list[i] = next;
        await save(list);
        return;
      }
    }
  }

  Future<void> updateAt(int i, WebDavAccount a) async {
    final list = [...await load()];
    if (i >= 0 && i < list.length) {
      list[i] = a;
      await save(list);
    }
  }

  Future<void> removeAt(int i) async {
    final list = [...await load()];
    if (i >= 0 && i < list.length) {
      list.removeAt(i);
      await save(list);
    }
  }
}