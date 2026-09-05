import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api/api_client.dart';
import 'api/articles_service.dart';
import 'api/auth_service.dart';
import 'api/diary_service.dart';
import 'api/domains_service.dart';
import 'api/feed_service.dart';
import 'api/invitations_service.dart';
import 'api/messages_service.dart';
import 'api/notifications_service.dart';
import 'api/personality_test_service.dart';
import 'api/personality_service.dart';
import 'api/posts_service.dart';
import 'api/profile_service.dart';
import 'api/reports_service.dart';
import 'api/results_service.dart';
import 'api/search_service.dart';
import 'api/site_config_service.dart';
import 'api/social_service.dart';
import 'api/votes_service.dart';
import 'config/app_config.dart';
import 'screens/ban_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/login_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/quote_settings_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/analytics_service.dart';
import 'services/daily_quote_service.dart';
import 'services/message_notification_source.dart';
import 'services/message_notifications.dart';
import 'services/notification_worker.dart';
import 'services/push/push_registration_service.dart';
import 'services/push/push_transport.dart';
import 'services/push/unified_push_transport.dart';
import 'services/realtime_service.dart';
import 'services/social_notification_source.dart';
import 'services/social_notifications.dart';
import 'theme/enclavd_theme.dart';
import 'widgets/microdot_overlay.dart';

/// Enclavd native app (Flutter). Only the Android APK is built by CI for
/// now. [args] carries the UnifiedPush background flag: with
/// `--unifiedpush-bg`, main() binds the push callbacks and does NOT build
/// the UI.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--unifiedpush-bg')) {
    UnifiedPushTransport.runBackground();
    return;
  }
  // FCM's killed-process callback must be bound before the engine starts.
  PushManager.bindBackgroundHandlers();
  // Background notification polling (WorkManager): the fallback channel
  // for when the live sockets cannot run. Push transports add instant
  // delivery on top; the poller stays as the safety net regardless.
  if (AppConfig.enableNotifications) {
    Workmanager().initialize(notificationDispatcher);
    unawaited(registerBackgroundNotifications());
    // Daily quote: arm the random-time one-shot and refresh the widget
    // if stale; both fire-and-forget.
    unawaited(DailyQuoteService.scheduleNextRun());
    unawaited(DailyQuoteService.refreshWidgetIfStale());
    // Widget rate taps: register the headless callback that records the
    // rating; it wakes its own isolate even when the app is killed.
    unawaited(HomeWidget.registerInteractivityCallback(
        quoteWidgetRateCallback));
    // Widget data can go stale in the background (Doze may delay the
    // daily slot for hours); every foreground return is a cheap,
    // date-gated catch-up.
    WidgetsBinding.instance.addObserver(_QuoteResumeRefresh());
  }
  runApp(const EnclavdApp());
}

/// The app's ONE navigator key; deep links (quote notification tap) push
/// through it even with no screen context handy.
final navigatorKey = GlobalKey<NavigatorState>();

/// Deep link into the Quote of the day settings. Parks the request on a
/// cold start (the navigator doesn't exist yet); SplashScreen consumes it
/// after the session gate.
class QuoteDeepLink {
  QuoteDeepLink._();

  static bool pending = false;

  static void requestOpen() {
    pending = true;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      pending = false;
      nav.push(MaterialPageRoute<void>(
          builder: (_) => const QuoteSettingsScreen()));
    }
  }

  /// Clears the parked request (called after a cold-start resolution).
  static void consume() => pending = false;
}

/// Refreshes the quote widget on every foreground return.
class _QuoteResumeRefresh with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DailyQuoteService.refreshWidgetIfStale());
    }
  }
}

/// Simple service container - no DI framework, constructor injection only.
class AppServices {
  AppServices._(
      this.apiClient, this.auth, this.feed, this.social, this.profile,
      this.posts, this.messages, this.notifications, this.search,
      this.realtime, this.messageAlerts, this.articles, this.domains,
      this.results, this.invitations, this.reports, this.personalityTest,
      this.personality, this.siteConfig, this.votes, this.diary);

  final ApiClient apiClient;
  final AuthService auth;
  final FeedService feed;
  final SocialService social;
  final ProfileService profile;
  final PostsService posts;
  final MessagesService messages;
  final NotificationsService notifications;
  final SearchService search;
  final RealtimeService realtime;
  final MessageNotifications messageAlerts;
  final ArticlesService articles;
  final DomainsService domains;
  final ResultsService results;
  final InvitationsService invitations;
  final ReportsService reports;
  final PersonalityTestService personalityTest;
  final PersonalityService personality;
  final SiteConfigService siteConfig;
  final VotesService votes;
  final DiaryService diary;

  /// The most recently created container - the one the app is actively
  /// using. Singletons must resolve against THIS: on a cold start the
  /// first container predates login and its jar is empty, so a singleton
  /// bound to it would 401 every unread fetch.
  static AppServices? current;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    // Fresh process: clear the worker's quiet-window flags, or flags
    // lingering from a killed process would leave it silent.
    unawaited(MessageNotificationSource.setChatOpenPrefs(prefs, false));
    unawaited(SocialNotificationSource.setDrawerOpenPrefs(prefs, false));
    final store = PrefsSessionStore(prefs);
    final api = ApiClient(store: store);
    await api.restoreSession();
    final auth = AuthService(api, apiBaseUrl: AppConfig.apiBaseUrl);
    // One plugin-backed notifier shared by Message and Social
    // notifications, so the plugin initializes exactly once.
    final notifier = FlutterLocalNotifier(
      onResponse: (r) {
        // Daily-quote notification tap deep-links into Quote of the day
        // settings (the widget tap uses the same target).
        if (r.payload == 'quote') {
          QuoteDeepLink.requestOpen();
          return;
        }
        MessageNotifications.instance?.handleResponse(r);
      },
    );
    // First create wins; later ones reuse the singleton so the plugin
    // initializes once and the messages-open count stays consistent.
    var notifications = MessageNotifications.instance;
    if (notifications == null) {
      notifications = MessageNotifications(
        notifier: notifier,
        // Late-bound: resolve the CURRENT container at ping time, or a
        // closure capturing `api` would freeze the first (pre-login,
        // empty jar) client and 401 every live-path fetch.
        messagesFactory: () async => MessagesService(
          current?.apiClient ?? api,
        ),
      );
      MessageNotifications.instance = notifications;
      unawaited(notifications.init());
    }
    // Same singleton pattern for the social path.
    var social = SocialNotifications.instance;
    if (social == null) {
      social = SocialNotifications(
        notifier: notifier,
        notificationsFactory: () async => NotificationsService(
          current?.apiClient ?? api,
        ),
      );
      SocialNotifications.instance = social;
      unawaited(social.init());
    }
    final services = AppServices._(
        api,
        auth,
        FeedService(api),
        SocialService(api),
        ProfileService(api),
        PostsService(api),
        MessagesService(api),
        NotificationsService(api),
        SearchService(api),
        RealtimeService(api),
        notifications,
        ArticlesService(api),
        DomainsService(api),
        ResultsService(api),
        InvitationsService(api),
        ReportsService(api),
        PersonalityTestService(api),
        PersonalityService(api),
        SiteConfigService(api),
        VotesService(api),
        DiaryService(api));
    current = services;
    // Background push: resolve the best transport for this build/device
    // (FCM -> Unified Push -> 15-minute polling) and register the token,
    // late-bound to the CURRENT container.
    unawaited(PushManager.ensureResolved(
      PushRegistrationService(() async => current?.apiClient ?? api),
    ));
    // Refresh the quote widget once per day when the session is live;
    // own client from prefs, as the container's may predate the login.
    unawaited(DailyQuoteService.refreshWidgetIfStale());
    // Self-hosted Plausible analytics: ONLY release builds of the
    // play/fdroid flavors report; debug/dev must never pollute the
    // production dashboard.
    AnalyticsService.instance = (kDebugMode || AppConfig.isDev)
        ? null
        : AnalyticsService(
            endpoint: AppConfig.analyticsEndpoint,
            domain: AppConfig.analyticsDomain,
            userAgent: AppConfig.analyticsUserAgent,
          );
    return services;
  }
}

class EnclavdApp extends StatelessWidget {
  const EnclavdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enclavd',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [AnalyticsRouteObserver()],
      theme: buildEnclavdTheme(),
      // The site's microdot.php port: a faint user-id watermark tiled
      // over EVERY screen while logged in, above the Navigator.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const MicrodotOverlay(),
        ],
      ),
      home: const SplashScreen(),
      routes: {
        LoginScreen.routeName: (_) => const LoginScreen(),
        RegisterScreen.routeName: (_) => const RegisterScreen(),
        FeedScreen.routeName: (_) => const FeedScreen(),
        BanScreen.routeName: (_) => const BanScreen(),
        MaintenanceScreen.routeName: (_) => const MaintenanceScreen(),
        VerifyEmailScreen.routeName: (_) => const VerifyEmailScreen(),
      },
    );
  }
}
