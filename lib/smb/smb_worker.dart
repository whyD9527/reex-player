import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'libsmb2.dart';

/// SMB worker isolate：所有 libsmb2 调用都发生在这里，绝不阻塞 UI。
void smbWorkerMain(SendPort tx) {
  final rx = ReceivePort();
  tx.send({'ready': true, 'port': rx.sendPort});

  final smb = LibSmb2.open();
  Pointer<Void>? ctx;
  final fhs = <int, Pointer<Void>>{};
  var nextFh = 1;

  String err() => ctx == null ? 'not connected' : smb.error(ctx!);

  // libsmb2 的路径是相对共享根的，不能带前导 '/'
  String rel(String p) {
    var s = p;
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    return s;
  }

  void reply(Map<String, Object?> msg) => tx.send(msg);

  rx.listen((dynamic raw) {
    final msg = (raw as Map).cast<String, Object?>();
    final id = msg['id'] as int? ?? 0;
    final op = msg['op'] as String? ?? '';
    try {
      switch (op) {
        case 'connect':
          if (ctx != null) {
            smb.disconnect(ctx!);
            smb.destroy(ctx!);
            ctx = null;
          }
          ctx = smb.initContext();
          final rc = smb.connect(
            ctx!,
            msg['server'] as String? ?? '',
            msg['share'] as String? ?? '',
            msg['user'] as String? ?? '',
            msg['pass'] as String? ?? '',
            msg['domain'] as String? ?? '',
          );
          if (rc != 0) {
            reply({'id': id, 'ok': false, 'error': 'connect rc=$rc ${err()}'});
          } else {
            reply({'id': id, 'ok': true});
          }
        case 'list':
          if (ctx == null) {
            reply({'id': id, 'ok': false, 'error': 'not connected'});
            break;
          }
          final path = msg['path'] as String? ?? '/';
          final dir = smb.opendir(ctx!, rel(path));
          if (dir == nullptr) {
            reply({'id': id, 'ok': false, 'error': err()});
            break;
          }
          final entries = <Map<String, Object?>>[];
          try {
            while (true) {
              final ent = smb.readdir(ctx!, dir);
              if (ent == nullptr) break;
              final e = ent.ref;
              final name = e.name == nullptr ? '' : e.name.toDartString();
              if (name.isEmpty) continue;
              final st = e.st;
              entries.add({
                'name': name,
                'size': st.size,
                'isDir': st.type == 1,
              });
            }
          } finally {
            smb.closedir(ctx!, dir);
          }
          reply({'id': id, 'ok': true, 'entries': entries});
        case 'open':
          if (ctx == null) {
            reply({'id': id, 'ok': false, 'error': 'not connected'});
            break;
          }
          final fh = smb.open(ctx!, rel(msg['path'] as String? ?? ''));
          if (fh == nullptr) {
            reply({'id': id, 'ok': false, 'error': err()});
            break;
          }
          final st = malloc<Smb2Stat>();
          var size = -1;
          try {
            if (smb.fstat(ctx!, fh, st) == 0) size = st.ref.size;
          } finally {
            malloc.free(st);
          }
          final fid = nextFh++;
          fhs[fid] = fh;
          reply({'id': id, 'ok': true, 'fh': fid, 'size': size});
        case 'read':
          if (ctx == null) {
            reply({'id': id, 'ok': false, 'error': 'not connected'});
            break;
          }
          final fh = fhs[msg['fh'] as int? ?? 0];
          if (fh == null) {
            reply({'id': id, 'ok': false, 'error': 'bad fh'});
            break;
          }
          final want = msg['length'] as int? ?? 0;
          final offset = msg['offset'] as int? ?? 0;
          final buf = malloc<Uint8>(want);
          try {
            final got = smb.pread(ctx!, fh, buf, want, offset);
            if (got < 0) {
              reply({'id': id, 'ok': false, 'error': 'pread $got ${err()}'});
            } else {
              final bytes = Uint8List.fromList(buf.asTypedList(got));
              reply({
                'id': id,
                'ok': true,
                'read': got,
                'data': TransferableTypedData.fromList([bytes]),
              });
            }
          } finally {
            malloc.free(buf);
          }
        case 'close':
          final fh = fhs.remove(msg['fh'] as int? ?? 0);
          if (fh != null && ctx != null) smb.close(ctx!, fh);
          reply({'id': id, 'ok': true});
        case 'disconnect':
          for (final fh in fhs.values) {
            if (ctx != null) smb.close(ctx!, fh);
          }
          fhs.clear();
          if (ctx != null) {
            smb.disconnect(ctx!);
            smb.destroy(ctx!);
            ctx = null;
          }
          reply({'id': id, 'ok': true});
        case 'dispose':
          reply({'id': id, 'ok': true});
          rx.close();
        default:
          reply({'id': id, 'ok': false, 'error': 'unknown op $op'});
      }
    } catch (e) {
      reply({'id': id, 'ok': false, 'error': e.toString()});
    }
  });
}