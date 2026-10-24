import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'smb_worker.dart';

class SmbEntry {
  const SmbEntry({required this.name, required this.size, required this.isDir});

  final String name;
  final int size;
  final bool isDir;

  factory SmbEntry.fromMap(Map<dynamic, dynamic> m) => SmbEntry(
        name: (m['name'] as String?) ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        isDir: (m['isDir'] as bool?) ?? false,
      );
}

class SmbException implements Exception {
  SmbException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 把 libsmb2 的 NTSTATUS 转成用户能看懂的中文。
String smbFriendlyError(String raw) {
  const map = <String, String>{
    '0xc000006d': '用户名或密码错误',
    '0xc000006a': '密码错误',
    '0xc0000234': '账号已被锁定（多次密码错误），请等待 10 分钟或联系管理员解锁',
    '0xc00000cc': '共享名不存在',
    '0xc0000022': '拒绝访问（账号无权限）',
    '0xc00000bb': '服务器不支持该操作',
    '0xc0000120': '操作已取消',
    '0xc00000c9': '网络名不存在',
  };
  final m = RegExp(r'\((0x[0-9a-fA-F]{8})\)').firstMatch(raw);
  if (m != null) {
    final code = (m.group(1) ?? '').toLowerCase();
    final friendly = map[code];
    if (friendly != null) return '$friendly（$code）';
  }
  if (raw.contains('Connection refused') || raw.contains('rc=-1')) {
    return '无法连接到服务器（检查 IP、端口 445 和防火墙）';
  }
  return raw;
}

/// 对 worker isolate 的同步式封装（内部全部是异步消息）。
class SmbClient {
  SmbClient._(this._isolate, this._tx, this._sub);

  final Isolate _isolate;
  final SendPort _tx;
  final StreamSubscription<dynamic> _sub;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _next = 1;

  static Future<SmbClient> spawn() async {
    final rx = ReceivePort();
    final isolate = await Isolate.spawn(smbWorkerMain, rx.sendPort,
        debugName: 'smb-worker', errorsAreFatal: false);
    final ready = Completer<SendPort>();
    late SmbClient client;
    final sub = rx.listen((dynamic msg) {
      if (msg is Map && msg['ready'] == true) {
        ready.complete(msg['port'] as SendPort);
        return;
      }
      if (msg is Map && msg['id'] is int) {
        final id = msg['id'] as int;
        final c = client._pending.remove(id);
        if (c != null && !c.isCompleted) c.complete(msg.cast<String, Object?>());
      }
    });
    final tx = await ready.future;
    client = SmbClient._(isolate, tx, sub);
    return client;
  }

  Future<Map<String, Object?>> _call(String op, Map<String, Object?> args) {
    final id = _next++;
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    _tx.send({'id': id, 'op': op, ...args});
    return c.future;
  }

  Future<void> connect({
    required String server,
    required String share,
    required String user,
    required String pass,
    String domain = '',
  }) async {
    final r = await _call('connect', {
      'server': server,
      'share': share,
      'user': user,
      'pass': pass,
      'domain': domain,
    });
    if (r['ok'] != true) {
      throw SmbException('连接失败: ' + smbFriendlyError((r['error'] ?? '').toString()));
    }
  }

  Future<List<SmbEntry>> list(String path) async {
    final r = await _call('list', {'path': path});
    if (r['ok'] != true) {
      throw SmbException('列目录失败: ' + smbFriendlyError((r['error'] ?? '').toString()));
    }
    final raw = (r['entries'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => SmbEntry.fromMap(e))
        .where((e) => e.name != '.' && e.name != '..')
        .toList(growable: false);
  }

  /// 打开文件，返回 (句柄, 大小)。
  Future<(int, int)> open(String path) async {
    final r = await _call('open', {'path': path});
    if (r['ok'] != true) {
      throw SmbException('打开失败: ' + smbFriendlyError((r['error'] ?? '').toString()));
    }
    return ((r['fh'] as num).toInt(), (r['size'] as num).toInt());
  }

  Future<Uint8List> read(int fh, int offset, int length) async {
    final r = await _call('read', {'fh': fh, 'offset': offset, 'length': length});
    if (r['ok'] != true) {
      throw SmbException('读取失败: ' + smbFriendlyError((r['error'] ?? '').toString()));
    }
    final td = r['data'] as TransferableTypedData?;
    if (td == null) return Uint8List(0);
    return td.materialize().asUint8List();
  }

  Future<void> close(int fh) async {
    await _call('close', {'fh': fh});
  }

  Future<void> disconnect() async {
    await _call('disconnect', {});
    await _call('dispose', {});
    await _sub.cancel();
    _isolate.kill(priority: Isolate.immediate);
  }
}