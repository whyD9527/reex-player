# Flutter / media_kit 反射与 JNI 入口
-keep class io.flutter.** { *; }
-keep class com.alexmercerind.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-dontwarn io.flutter.embedding.**
