import 'package:flutter/services.dart';

/// 接收系统 VIEW/SEND 意图带来的媒体 URI（对应 Reex 的 NewPlaylistItemChannel）。
class IntentChannel {
  static const _channel = MethodChannel('reex_player/intent');

  static Future<String?> initialUri() async {
    try {
      return await _channel.invokeMethod<String>('getInitialUri');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 打开系统文件选择器（SAF），返回缓存的本地路径。
  static Future<String?> pickVideo() async {
    try {
      return await _channel.invokeMethod<String>('pickVideo');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 应用运行中再次被唤起时，Kotlin 侧会通过此通道推送新 URI。
  static void setHandler(void Function(String uri) onUri) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewUri') {
        final uri = call.arguments as String?;
        if (uri != null) onUri(uri);
      }
      return null;
    });
  }
}