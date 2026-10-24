import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 媒体库条目（来自 MediaStore）。
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.path,
    required this.duration,
    required this.size,
    required this.width,
    required this.height,
    required this.dateAdded,
  });

  final int id;
  final String name;
  final String path;
  final Duration duration;
  final int size;
  final int width;
  final int height;
  final int dateAdded;

  factory MediaItem.fromMap(Map<dynamic, dynamic> m) {
    return MediaItem(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: (m['name'] as String?) ?? '',
      path: (m['path'] as String?) ?? '',
      duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
      size: (m['size'] as num?)?.toInt() ?? 0,
      width: (m['width'] as num?)?.toInt() ?? 0,
      height: (m['height'] as num?)?.toInt() ?? 0,
      dateAdded: (m['dateAdded'] as num?)?.toInt() ?? 0,
    );
  }

  String get resolution => width > 0 && height > 0 ? '${width}×$height' : '';

  String get sizeText {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '${mb.toStringAsFixed(0)} MB';
  }
}

class MediaLibrary {
  static const _channel = MethodChannel('reex_player/media');

  /// 申请读取视频权限（Android 13+ READ_MEDIA_VIDEO）。
  static Future<bool> ensurePermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 取媒体库缩略图（JPEG 字节）。
  static Future<Uint8List?> thumbnail(int id) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', id);
    } catch (_) {
      return null;
    }
  }

  /// 扫描 MediaStore 中的视频。
  static Future<List<MediaItem>> scan() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanVideos');
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(MediaItem.fromMap)
          .where((e) => e.path.isNotEmpty)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}