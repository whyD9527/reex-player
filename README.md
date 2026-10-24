# Reex Player（clean-room rewrite）

Reex 1.8.9 的开源重写版：一个可长期维护的 Flutter + libmpv 播放器。

> 逆向分析与安全审计见 [whyD9527/reex](https://github.com/whyD9527/reex)；
> 本项目只复用**结论**（协议、数据结构、mpv 用法），不包含任何反编译代码。

![播放截图](docs/screenshot-player.png)

## 当前状态

- [x] Flutter 工程骨架（Riverpod + Material 3 + 深色/浅色）
- [x] libmpv 播放（media_kit 封装）——**debug 与 release 均已在真机验证**：640×360 / 30fps H.264 正常解码播放
- [x] 系统播放器入口（VIEW/SEND intent → 自动打开播放页）
- [x] SAF 选片（MainActivity 自实现，复制到 cache 后播放）
- [x] 最近打开记录（SharedPreferences）
- [x] 媒体库（MediaStore 扫描；缩略图待做）
- [x] **SMB**（libsmb2 FFI + 本地 HTTP Range 代理，支持浏览/播放/拖动）
- [x] **WebDAV**（PROPFIND 列目录 + Basic Auth 直链播放）
- [ ] FTP
- [x] 播放列表 / 播放历史 / 收藏（本地 JSON，后续可迁 drift）
- [ ] 导入复刻 Reex 的 `reex.sqlite`
- [x] 音轨/字幕切换、倍速、±10s、进度记忆
- [x] 手势：左右滑进度、左侧滑亮度、右侧滑音量、双击播放/暂停、长按 2x
- [x] 媒体信息面板（分辨率/像素格式/音频参数/轨数）
- [x] **后台播放 + 媒体通知 + 锁屏/蓝牙控制**（前台服务 + MediaSession）
- [ ] 画中画

## 架构

```
lib/
├── main.dart                     MediaKit 初始化 + ProviderScope
├── app.dart                      MaterialApp / 主题
├── data/recent_store.dart        最近记录（后续换 drift）
├── platform/intent_channel.dart  reex_player/intent 通道（选片 / 外部 URI）
└── features/
    ├── library/home_page.dart    首页
    ├── player/player_page.dart   libmpv + 控制条
    └── settings/settings_page.dart
android/app/src/main/kotlin/.../MainActivity.kt
    方法通道：getInitialUri / pickVideo / onNewUri
```

## 构建

> ⚠️ **工程路径必须是 ASCII**：AGP 会拒绝 `D:\代码\...` 这类含中文的路径。

```bash
flutter pub get
flutter build apk --debug      # 或 --release
```

本机验证过的工具链：Flutter 3.47.8 / Dart 3.x、AGP 9.1.0、Gradle 9.3.1、
Android SDK 36、JDK 21、NDK r28c。

### 已知的构建坑（已在仓库里处理）

1. **Gradle 发行包**：`android/gradle/wrapper/gradle-wrapper.properties` 默认指向
   services.gradle.org，国内可能被重定向卡住；可改为本地 `file:///` 或镜像。
2. **media_kit 的 libmpv jar 来自 GitHub Releases**：无法访问 GitHub 时，
   把 4 个 `default-*.jar` 预置到
   `build/media_kit_libs_android_video/v1.1.7/`（插件会校验 MD5 后跳过下载）。
3. **AGP 9 的内置 Kotlin 与插件自带的 KGP 冲突**：
   `file_picker` / `package_info_plus` / `wakelock_plus` 在本环境下无法编译，
   已改为：SAF 自实现选片 + `third_party/` 里两个纯 Dart stub。

## 自动修正

- **全角字符**：中文输入法常把 `! : @` 打成全角（U+FF01…），SMB/WebDAV 认证会失败。
  首次失败后会用半角凭据重试一次，成功则写回账号。
- **https→http**：WebDAV 地址误写成 https 而服务器只支持 http 时，自动降级重试并写回地址。
- **诊断**：`reexplayer://selftest` 会用已保存账号跑一遍连接，日志写到
  `/sdcard/Android/data/io.github.whyd9527.reex_player/files/diagnostics.log`。

## WebDAV

- `PROPFIND` + `DAV:` XML 解析（`xml` 包），支持自定义端口与 Basic Auth；
- 播放直接把 `http://user:pass@host/path` 交给 mpv（ffmpeg 原生支持 basic auth）；
- 入口：网络页右上角 WebDAV 按钮 / `reexplayer://webdav-browse?` 诊断意图。

## SMB 实现要点

- 复用 Reex 内置的 `libsmb2.so`（3.1.1，arm64，已放入 `android/app/src/main/jniLibs/`）；
- 所有 libsmb2 调用在**独立 worker isolate** 里（同步 API，不阻塞 UI）；
- 播放不写自定义 mpv 流协议：起一个 **127.0.0.1 的 HTTP Range 代理**，让 mpv 当普通 http 源播放；
- 支持 `smb://user:pass@host/share/path` 与 Reex 的 `smb2://{json}` 两种入口。

诊断入口（便于自动化验证）：

```bash
adb shell am start -a android.intent.action.VIEW \
  -d 'reexplayer://smb-list?server=HOST&share=SHARE&user=U&pass=P&path=/' \
  -n io.github.whyd9527.reex_player/.MainActivity
# 结果在 logcat：adb logcat -s flutter | grep '\[smb\]'
```

## 体积

| 包 | 体积 |
| --- | --- |
| arm64-v8a release（split） | **30.6 MB**（含 libsmb2.so） |
| armeabi-v7a release（split） | 25.9 MB |
| universal release | 86.2 MB |
| 参考：原版 Reex 1.8.9 | 22.1 MB |

体积主要来自 `libmpv.so` + FFmpeg（media_kit 的预编译包）与 Flutter 引擎。
进一步压缩的思路：换更小的 libmpv 构建（去掉不需要的解码器）、
`--obfuscate`、以及只保留 arm64。

## 产物

- `flutter build apk --release` → 86 MB（全 ABI）；`--split-per-abi` 可缩到 arm64 单包约 30 MB
- release 目前用 debug 签名（Flutter 模板默认），正式发布请换自己的 keystore

## License

MIT（本仓库自写代码）。第三方依赖遵循各自许可证。