import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api/api_client.dart';
import 'api/auth_service.dart';
import 'api/feed_service.dart';
import 'api/messages_service.dart';
import 'api/posts_service.dart';
import 'api/profile_service.dart';
import 'api/social_service.dart';
import 'config/app_config.dart';
import 'screens/feed_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'services/message_notification_source.dart';
import 'services/message_notifications.dart';
import 'services/notification_worker.dart';
import 'services/realtime_service.dart';
import 'theme/enclavd_theme.dart';

/// Enclavd — native app (Flutter).
///
/// Cross-platform from day one (android/ + ios/ runners committed), but only
/// the Android APK is built by CI for now. All networking goes through the
/// api/v1 JSON endpoints + the legacy auth flows, exactly like the website.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Background notification polling (WorkManager, 15-min minimum): the
  // fallback channel for when the live sockets cannot run (app swiped
  // away / process killed). Idempotent to call on every start; gated on
  // the flavor so F-Droid (notifications off) never registers it.
  if (AppConfig.enableNotifications) {
    Workmanager().initialize(notificationDispatcher);
    unawaited(registerBackgroundNotifications());
  }
  runApp(const EnclavdApp());
}

/// Simple service container — no DI framework, constructor injection only.
/// Everything the screens need is created here once and passed down.
class AppServices {
  AppServices._(
      this.apiClient, this.auth, this.feed, this.social, this.profile,
      this.posts, this.messages, this.realtime, this.notifications);

  final ApiClient apiClient;
  final AuthService auth;
  final FeedService feed;
  final SocialService social;
  final ProfileService profile;
  final PostsService posts;
  final MessagesService messages;
  final RealtimeService realtime;
  final MessageNotifications notifications;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    // Boot: a fresh process has no messages screen open. The background
    // worker's quiet-window flag must not linger true from a process
    // that was killed while the thread was on screen — that would leave
    // the worker silent for messages until the next chat visit.
    unawaited(MessageNotificationSource.setChatOpenPrefs(prefs, false));
    final store = PrefsSessionStore(prefs);
    final api = ApiClient(store: store);
    await api.restoreSession();
    final auth = AuthService(api, apiBaseUrl: AppConfig.apiBaseUrl);
    // One MessageNotifications for the app's lifetime: first create wins,
    // later ones reuse it so the plugin initializes once and the
    // messages-open count stays consistent across screen instances.
    var notifications = MessageNotifications.instance;
    if (notifications == null) {
      notifications = MessageNotifications(
        notifier: FlutterLocalNotifier(
          onResponse: (r) => MessageNotifications.instance?.handleResponse(r),
        ),
        messagesFactory: () async => MessagesService(api),
      );
      MessageNotifications.instance = notifications;
      unawaited(notifications.init());
    }
    return AppServices._(
        api,
        auth,
        FeedService(api),
        SocialService(api),
        ProfileService(api),
        PostsService(api),
        MessagesService(api),
        RealtimeService(api),
        notifications);
  }
}

class EnclavdApp extends StatelessWidget {
  const EnclavdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enclavd',
      debugShowCheckedModeBanner: false,
      theme: buildEnclavdTheme(),
      home: const SplashScreen(),
      routes: {
        LoginScreen.routeName: (_) => const LoginScreen(),
        RegisterScreen.routeName: (_) => const RegisterScreen(),
        FeedScreen.routeName: (_) => const FeedScreen(),
      },
    );
  }
}
