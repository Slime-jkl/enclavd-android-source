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

/// Enclavd — native app (Flutter).
///
/// Cross-platform from day one (android/ + ios/ runners committed), but only
/// the Android APK is built by CI for now. All networking goes through the
/// api/v1 JSON endpoints + the legacy auth flows, exactly like the website.
///
/// [args] carries the UnifiedPush background flag: when the app was killed
/// and a distributor wakes it for an incoming message, the engine starts
/// with `--unifiedpush-bg` and main() must NOT build the UI — it binds the
/// push callbacks and lets the plugin keep the headless isolate alive.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--unifiedpush-bg')) {
    UnifiedPushTransport.runBackground();
    return;
  }
  // FCM's killed-process callback must be bound before the engine starts.
  PushManager.bindBackgroundHandlers();
  // Background notification polling (WorkManager, 15-min minimum): the
  // fallback channel for when the live sockets cannot run (app swiped
  // away / process killed). Idempotent to call on every start; gated on
  // the feature toggle. Push transports (FCM / Unified Push) add instant
  // delivery on top — the poller stays as the safety net regardless.
  if (AppConfig.enableNotifications) {
    Workmanager().initialize(notificationDispatcher);
    unawaited(registerBackgroundNotifications());
    // Daily quote: arm the random-time one-shot (keeps an already-armed
    // slot) and refresh the home-screen widget if today's quote isn't in
    // it yet. Both are fire-and-forget — nothing here blocks startup.
    unawaited(DailyQuoteService.scheduleNextRun());
    unawaited(DailyQuoteService.refreshWidgetIfStale());
    // Widget 👍/👎 taps: register the headless Dart callback that records
    // the rating in the API. The handle is saved at startup; the tap itself
    // wakes its own isolate even when the app is killed.
    unawaited(HomeWidget.registerInteractivityCallback(
        quoteWidgetRateCallback));
    // The widget's data can go stale while the process sits in the
    // background (the daily slot is a single random moment and Doze may
    // delay it for hours) — every return to the foreground is a cheap,
    // date-gated chance to catch up.
    WidgetsBinding.instance.addObserver(_QuoteResumeRefresh());
  }
  runApp(const EnclavdApp());
}

/// The app's ONE navigator key — deep links (the daily-quote notification
/// tap) push through it even when no screen context is handy.
final navigatorKey = GlobalKey<NavigatorState>();

/// Deep link into the Quote of the day settings (widget tap / quote
/// notification tap). When the app is already up the push happens
/// immediately; on a cold start the navigator doesn't exist yet, so the
/// request is parked here and SplashScreen consumes it AFTER the session
/// gate (no active session → the gate sends the user to login instead,
/// the requested quote screen never opens).
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

/// Foreground refresher for the daily-quote widget: the widget only ever
/// renders data pushed to it (the daily background slot + app opens), so
/// every time the app comes back to the foreground is a free, date-gated
/// chance to catch up if the OS delayed or dropped the background run.
class _QuoteResumeRefresh with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DailyQuoteService.refreshWidgetIfStale());
    }
  }
}

/// Simple service container — no DI framework, constructor injection only.
/// Everything the screens need is created here once and passed down.
class AppServices {
  AppServices._(
      this.apiClient, this.auth, this.feed, this.social, this.profile,
      this.posts, this.messages, this.notifications, this.search,
      this.realtime, this.messageAlerts, this.articles, this.domains,
      this.results, this.invitations, this.reports, this.personalityTest,
      this.siteConfig, this.votes, this.diary);

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
  final SiteConfigService siteConfig;
  final VotesService votes;
  final DiaryService diary;

  /// The most recently created container — the one the app is actively
  /// using. The notification singleton's fetch closure must resolve
  /// against THIS, not the api of whichever create() happened to run
  /// first: on a cold start the first container predates login and its
  /// cookie jar is empty, so a singleton bound to it would 401 every
  /// unread fetch (silently killing live notifications) while the feed
  /// and the worker — which use the current session — work fine.
  static AppServices? current;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    // Boot: a fresh process has no messages screen and no notification
    // drawer open. The background worker's quiet-window flags must not
    // linger true from a process that was killed while a screen was open —
    // that would leave the worker silent for messages/notifications until
    // the next visit.
    unawaited(MessageNotificationSource.setChatOpenPrefs(prefs, false));
    unawaited(SocialNotificationSource.setDrawerOpenPrefs(prefs, false));
    final store = PrefsSessionStore(prefs);
    final api = ApiClient(store: store);
    await api.restoreSession();
    final auth = AuthService(api, apiBaseUrl: AppConfig.apiBaseUrl);
    // One plugin-backed notifier for the whole app: MessageNotifications
    // and SocialNotifications SHARE it, so the plugin initializes exactly
    // once and both paths show through the same channel definitions.
    final notifier = FlutterLocalNotifier(
      onResponse: (r) {
        // The daily-quote notification tap deep-links into the Quote of
        // the day settings (the widget tap uses the same target).
        if (r.payload == 'quote') {
          QuoteDeepLink.requestOpen();
          return;
        }
        MessageNotifications.instance?.handleResponse(r);
      },
    );
    // One MessageNotifications for the app's lifetime: first create wins,
    // later ones reuse it so the plugin initializes once and the
    // messages-open count stays consistent across screen instances.
    var notifications = MessageNotifications.instance;
    if (notifications == null) {
      notifications = MessageNotifications(
        notifier: notifier,
        // Late-bound: resolve the CURRENT container at ping time. A
        // closure capturing `api` here would freeze the FIRST container's
        // client — the pre-login one with an empty jar on cold starts —
        // and every live-path unread fetch would 401 while the feed,
        // the badge (SSE) and the worker all work. The worker builds its
        // own client from prefs; this path must track the live session.
        messagesFactory: () async => MessagesService(
          current?.apiClient ?? api,
        ),
      );
      MessageNotifications.instance = notifications;
      unawaited(notifications.init());
    }
    // Same singleton pattern for the social path (likes/comments/mentions
    // device alerts): first create wins, shared notifier, late-bound
    // factory resolving the current container.
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
        SiteConfigService(api),
        VotesService(api),
        DiaryService(api));
    current = services;
    // Background push: resolve the best transport for this build/device
    // (FCM → Unified Push → 15-minute polling) and register this
    // device's token. Late-bound to the CURRENT container, so a
    // post-login re-create re-pushes the token with the live session.
    unawaited(PushManager.ensureResolved(
      PushRegistrationService(() async => current?.apiClient ?? api),
    ));
    // Daily-quote home-screen widget: refresh once per day when the session
    // is live (post-login create). Own client from prefs on purpose — the
    // container's client may predate the login cookies on a cold start.
    unawaited(DailyQuoteService.refreshWidgetIfStale());
    // Analytics: the app's own self-hosted Plausible (the site's :2000
    // endpoint). ONLY release builds of the play/fdroid flavors report —
    // debug runs and the dev flavor (kDebugMode / isDev) must never
    // pollute the production dashboard.
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
      // The site's microdot.php port: a faint user-id watermark tiled over
      // EVERY screen while logged in (pointer-events none). Lives above
      // the Navigator here, like the site's fixed z-999999 layer, so it
      // covers every route and dialog.
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
