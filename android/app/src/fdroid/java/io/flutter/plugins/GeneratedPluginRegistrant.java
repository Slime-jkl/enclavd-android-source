package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;

import io.flutter.embedding.engine.FlutterEngine;

/**
 * F-Droid variant registrant — the generated registrant (src/main/java)
 * minus firebase_core and firebase_messaging.
 *
 * The fdroid flavor excludes the firebase plugins from its dependency
 * graph (build.gradle.kts), so the GENERATED registrant would not compile
 * there. This copy registers every other plugin and deliberately skips
 * the two firebase ones (FCM is Play-bound; AppConfig.enableFcm is
 * compile-time false on fdroid, so nothing ever calls them).
 *
 * KEEP IN SYNC with the generated registrant (run `flutter pub get` and
 * diff) when plugins are added or removed.
 */
@Keep
public final class GeneratedPluginRegistrant {
  private static final String TAG = "GeneratedPluginRegistrant";
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    try {
      flutterEngine.getPlugins().add(new xyz.luan.audioplayers.AudioplayersPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin audioplayers_android, xyz.luan.audioplayers.AudioplayersPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_local_notifications, com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_plugin_android_lifecycle, io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new studio.midoridesign.gal.GalPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin gal, studio.midoridesign.gal.GalPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.imagepicker.ImagePickerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin image_picker_android, io.flutter.plugins.imagepicker.ImagePickerPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.github.dart_lang.jni.JniPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin jni, com.github.dart_lang.jni.JniPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.github.dart_lang.jni_flutter.JniFlutterPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin jni_flutter, com.github.dart_lang.jni_flutter.JniFlutterPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin shared_preferences_android, io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new org.unifiedpush.flutter.connector.Plugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin unifiedpush_android, org.unifiedpush.flutter.connector.Plugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.urllauncher.UrlLauncherPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin url_launcher_android, io.flutter.plugins.urllauncher.UrlLauncherPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.example.webcrypto.WebcryptoPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin webcrypto, com.example.webcrypto.WebcryptoPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.webviewflutter.WebViewFlutterPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin webview_flutter_android, io.flutter.plugins.webviewflutter.WebViewFlutterPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new dev.fluttercommunity.workmanager.WorkmanagerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin workmanager_android, dev.fluttercommunity.workmanager.WorkmanagerPlugin", e);
    }
  }
}
