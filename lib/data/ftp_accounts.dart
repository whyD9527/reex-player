import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FtpAccount {
  const FtpAccount({
    required this.host,
    this.port = 21,
    required this.user,
    required this.pass,
    this.alias = '',
  });

  final String host;
  final int port;
  final String user;
  final String pass;
  final String alias;

  String get label => alias.isNotEmpty ? alias : '$user@$host:$port';

  Map<String, Object?> toJson() => {
        'host': host,
        'port': port,
        'user': user,
        'pass': pass,
        'alias': alias,
      };

  factory FtpAccount.fromJson(Map<String, dynamic> m) => FtpAccount(
        host: (m['host'] as String?) ?? '',
        port: (m['port'] as num?)?.toInt() ?? 21,
        user: (m['user'] as String?) ?? '',
        pass: (m['pass'] as String?) ?? '',
        alias: (m['alias'] as String?) ?? '',
      );
}

class FtpAccountStore {
  static const _key = 'ftp_accounts';

  Future<List<FtpAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().map(FtpAccount.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<FtpAccount> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> add(FtpAccount a) async => save([...await load(), a]);

  Future<void> updateAt(int i, FtpAccount a) async {
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
