import 'package:flutter/foundation.dart';

/// 本应用只需要 [PackageInfo.appName]（wakelock_plus 在 Linux 上使用）。
/// 为避免 package_info_plus 自带的 Android 插件（AGP 9 下 Kotlin 编译为空）
/// 拖垮构建，这里提供一个纯 Dart 的本地实现。
@immutable
class PackageInfo {
  const PackageInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
    this.buildSignature = '',
    this.installerStore,
  });

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
  final String buildSignature;
  final String? installerStore;

  static Future<PackageInfo> fromPlatform() async {
    return const PackageInfo(
      appName: 'Reex Player',
      packageName: 'io.github.whyd9527.reex_player',
      version: '0.1.0',
      buildNumber: '1',
    );
  }
}
