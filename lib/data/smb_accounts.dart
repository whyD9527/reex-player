import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SmbAccount {
  const SmbAccount({
    required this.server,
    required this.share,
    required this.user,
    required this.pass,
    this.domain = '',
    this.alias = '',
  });

  final String server;
  final String share;
  final String user;
  final String pass;
  final String domain;
  final String alias;

  String get label => alias.isNotEmpty ? alias : '$user@$server/$share';

  Map<String, Object?> toJson() => {
        'server': server,
        'share': share,
        'user': user,
        'pass': pass,
        'domain': domain,
        'alias': alias,
      };

  factory SmbAccount.fromJson(Map<String, dynamic> m) => SmbAccount(
        server: (m['server'] as String?) ?? '',
        share: (m['share'] as String?) ?? '',
        user: (m['user'] as String?) ?? '',
        pass: (m['pass'] as String?) ?? '',
        domain: (m['domain'] as String?) ?? '',
        alias: (m['alias'] as String?) ?? '',
      );
}

class SmbAccountStore {
  static const _key = 'smb_accounts';

  Future<List<SmbAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SmbAccount.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<SmbAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(accounts.map((e) => e.toJson()).toList()));
  }

  Future<void> add(SmbAccount account) async {
    final list = [...await load(), account];
    await save(list);
  }

  Future<void> replace(SmbAccount oldAccount, SmbAccount next) async {
    final list = [...await load()];
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      if (a.server == oldAccount.server &&
          a.share == oldAccount.share &&
          a.user == oldAccount.user &&
          a.domain == oldAccount.domain) {
        list[i] = next;
        await save(list);
        return;
      }
    }
  }

  Future<void> updateAt(int index, SmbAccount account) async {
    final list = [...await load()];
    if (index >= 0 && index < list.length) {
      list[index] = account;
      await save(list);
    }
  }

  Future<void> removeAt(int index) async {
    final list = [...await load()];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await save(list);
    }
  }
}