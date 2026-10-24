import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// libsmb2 3.1.1（取自 Reex 内置 so）的最小同步 API 绑定。
///
/// 只在 SMB worker isolate 里使用，避免阻塞 UI。
final class Smb2Stat extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int nlink;
  @Uint64()
  external int ino;
  @Uint64()
  external int size;
  @Uint64()
  external int atime;
  @Uint64()
  external int mtime;
  @Uint64()
  external int ctime;
  @Uint64()
  external int btime;
  @Uint32()
  external int atimeNsec;
  @Uint32()
  external int mtimeNsec;
  @Uint32()
  external int ctimeNsec;
  @Uint32()
  external int btimeNsec;
}

final class Smb2Dirent extends Struct {
  external Pointer<Utf8> name;
  external Smb2Stat st;
}

typedef _InitContextNative = Pointer<Void> Function();
typedef _InitContextDart = Pointer<Void> Function();

typedef _SetStrNative = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _SetStrDart = void Function(Pointer<Void>, Pointer<Utf8>);

typedef _SetU16Native = Void Function(Pointer<Void>, Uint16);
typedef _SetU16Dart = void Function(Pointer<Void>, int);

typedef _SetI32Native = Void Function(Pointer<Void>, Int32);
typedef _SetI32Dart = void Function(Pointer<Void>, int);

typedef _ConnectNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ConnectDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _CtxOnlyNative = Int32 Function(Pointer<Void>);
typedef _CtxOnlyDart = int Function(Pointer<Void>);

typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

typedef _GetErrorNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _GetErrorDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _OpenNative = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _OpenDart = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _PreadNative = Int32 Function(
    Pointer<Void>, Pointer<Void>, Pointer<Uint8>, Uint32, Uint64);
typedef _PreadDart = int Function(
    Pointer<Void>, Pointer<Void>, Pointer<Uint8>, int, int);

typedef _FstatNative = Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Smb2Stat>);
typedef _FstatDart = int Function(Pointer<Void>, Pointer<Void>, Pointer<Smb2Stat>);

typedef _CloseNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _CloseDart = int Function(Pointer<Void>, Pointer<Void>);

typedef _OpendirNative = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>);
typedef _OpendirDart = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>);

typedef _ReaddirNative = Pointer<Smb2Dirent> Function(Pointer<Void>, Pointer<Void>);
typedef _ReaddirDart = Pointer<Smb2Dirent> Function(Pointer<Void>, Pointer<Void>);

typedef _ClosedirNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _ClosedirDart = int Function(Pointer<Void>, Pointer<Void>);

const int _smb2SigningEnabled = 0x0001;
const int _oReadOnly = 0;

class LibSmb2 {
  LibSmb2._(DynamicLibrary lib)
      : _init = lib.lookupFunction<_InitContextNative, _InitContextDart>('smb2_init_context'),
        _setUser = lib.lookupFunction<_SetStrNative, _SetStrDart>('smb2_set_user'),
        _setPassword = lib.lookupFunction<_SetStrNative, _SetStrDart>('smb2_set_password'),
        _setDomain = lib.lookupFunction<_SetStrNative, _SetStrDart>('smb2_set_domain'),
        _setSecurityMode =
            lib.lookupFunction<_SetU16Native, _SetU16Dart>('smb2_set_security_mode'),
        _setTimeout = lib.lookupFunction<_SetI32Native, _SetI32Dart>('smb2_set_timeout'),
        _connectShare = lib.lookupFunction<_ConnectNative, _ConnectDart>('smb2_connect_share'),
        _disconnectShare =
            lib.lookupFunction<_CtxOnlyNative, _CtxOnlyDart>('smb2_disconnect_share'),
        _destroyContext = lib.lookupFunction<_DestroyNative, _DestroyDart>('smb2_destroy_context'),
        _getError = lib.lookupFunction<_GetErrorNative, _GetErrorDart>('smb2_get_error'),
        _open = lib.lookupFunction<_OpenNative, _OpenDart>('smb2_open'),
        _pread = lib.lookupFunction<_PreadNative, _PreadDart>('smb2_pread'),
        _fstat = lib.lookupFunction<_FstatNative, _FstatDart>('smb2_fstat'),
        _close = lib.lookupFunction<_CloseNative, _CloseDart>('smb2_close'),
        _opendir = lib.lookupFunction<_OpendirNative, _OpendirDart>('smb2_opendir'),
        _readdir = lib.lookupFunction<_ReaddirNative, _ReaddirDart>('smb2_readdir'),
        _closedir = lib.lookupFunction<_ClosedirNative, _ClosedirDart>('smb2_closedir');

  factory LibSmb2.open() {
    try {
      return LibSmb2._(DynamicLibrary.open('libsmb2.so'));
    } catch (e) {
      throw UnsupportedError('libsmb2.so 未随此 ABI 打包: $e');
    }
  }

  final _InitContextDart _init;
  final _SetStrDart _setUser;
  final _SetStrDart _setPassword;
  final _SetStrDart _setDomain;
  final _SetU16Dart _setSecurityMode;
  final _SetI32Dart _setTimeout;
  final _ConnectDart _connectShare;
  final _CtxOnlyDart _disconnectShare;
  final _DestroyDart _destroyContext;
  final _GetErrorDart _getError;
  final _OpenDart _open;
  final _PreadDart _pread;
  final _FstatDart _fstat;
  final _CloseDart _close;
  final _OpendirDart _opendir;
  final _ReaddirDart _readdir;
  final _ClosedirDart _closedir;

  Pointer<Void> initContext() => _init();

  int connect(Pointer<Void> ctx, String server, String share, String user,
      String password, String domain) {
    final serverP = server.toNativeUtf8();
    final shareP = share.toNativeUtf8();
    final userP = user.toNativeUtf8();
    final passP = password.toNativeUtf8();
    final domainP = domain.toNativeUtf8();
    try {
      _setUser(ctx, userP);
      _setPassword(ctx, passP);
      _setDomain(ctx, domainP);
      _setSecurityMode(ctx, _smb2SigningEnabled);
      _setTimeout(ctx, 30);
      return _connectShare(ctx, serverP, shareP, userP);
    } finally {
      malloc.free(serverP);
      malloc.free(shareP);
      malloc.free(userP);
      malloc.free(passP);
      malloc.free(domainP);
    }
  }

  int disconnect(Pointer<Void> ctx) => _disconnectShare(ctx);
  void destroy(Pointer<Void> ctx) => _destroyContext(ctx);

  String error(Pointer<Void> ctx) {
    final p = _getError(ctx);
    return p == nullptr ? '' : p.toDartString();
  }

  Pointer<Void> open(Pointer<Void> ctx, String path) {
    final p = path.toNativeUtf8();
    try {
      return _open(ctx, p, _oReadOnly);
    } finally {
      malloc.free(p);
    }
  }

  int pread(Pointer<Void> ctx, Pointer<Void> fh, Pointer<Uint8> buf, int count, int offset) =>
      _pread(ctx, fh, buf, count, offset);

  int fstat(Pointer<Void> ctx, Pointer<Void> fh, Pointer<Smb2Stat> st) =>
      _fstat(ctx, fh, st);

  int close(Pointer<Void> ctx, Pointer<Void> fh) => _close(ctx, fh);

  Pointer<Void> opendir(Pointer<Void> ctx, String path) {
    final p = path.toNativeUtf8();
    try {
      return _opendir(ctx, p);
    } finally {
      malloc.free(p);
    }
  }

  Pointer<Smb2Dirent> readdir(Pointer<Void> ctx, Pointer<Void> dir) => _readdir(ctx, dir);
  int closedir(Pointer<Void> ctx, Pointer<Void> dir) => _closedir(ctx, dir);
}