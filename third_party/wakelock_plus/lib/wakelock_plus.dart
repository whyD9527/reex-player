/// 纯 Dart 的空实现：媒体播放期间保持常亮属于平台行为，
/// 这里先不引入插件（避免 AGP 9 下 KGP 与内置 Kotlin 的冲突）。
class WakelockPlus {
  static Future<void> enable() async {}

  static Future<void> disable() async {}

  static Future<bool> get enabled async => false;

  static Future<void> toggle({required bool enable}) async {}
}
