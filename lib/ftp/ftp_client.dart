import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path_provider/path_provider.dart';

import '../data/ftp_accounts.dart';

class FtpEntry {
  const FtpEntry({required this.name, required this.isDir, required this.size});
  final String name;
  final bool isDir;
  final int size;

  String get sizeText {
    if (isDir) return '';
    final mb = (size / (1024 * 1024)).toStringAsFixed(1);
    return '$mb MB';
  }
}

class FtpException implements Exception {
  FtpException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// FTP：浏览 + 下载到缓存后播放（FTP 不支持随机读，先落盘）。
class FtpSession {
  FtpSession(this.account);

  final FtpAccount account;
  FTPConnect? _ftp;

  Future<FTPConnect> _connect() async {
    if (_ftp != null) return _ftp!;
    final ftp = FTPConnect(
      account.host,
      port: account.port,
      user: account.user,
      pass: account.pass,
      timeout: 20,
    );
    try {
      final ok = await ftp.connect();
      if (!ok) throw FtpException('连接失败（检查地址/端口/账号）');
    } catch (e) {
      throw FtpException('连接失败: $e');
    }
    _ftp = ftp;
    return ftp;
  }

  Future<List<FtpEntry>> list(String path) async {
    final ftp = await _connect();
    try {
      final items = await ftp.listDirectoryContent(path);
      return items
          .map((e) => FtpEntry(
                name: e.name,
                isDir: e.type == FTPEntryType.dir,
                size: e.size ?? 0,
              ))
          .where((e) => e.name != '.' && e.name != '..')
          .toList(growable: false);
    } catch (e) {
      throw FtpException('列目录失败: $e');
    }
  }

  Future<String> download(String remotePath, String name, void Function(double)? progress) async {
    final ftp = await _connect();
    final dir = await getTemporaryDirectory();
    final out = File(dir.path + '/ftp_' + name);
    if (await out.exists()) await out.delete();
    try {
      await ftp.downloadFile(remotePath, out,
          onProgress: (pct, transferred, total) => progress?.call(pct));
    } catch (e) {
      throw FtpException('下载失败: $e');
    }
    return out.path;
  }

  Future<void> close() async {
    try {
      await _ftp?.disconnect();
    } catch (_) {}
    _ftp = null;
  }
}