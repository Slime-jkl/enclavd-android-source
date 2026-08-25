/// Enclavd native app — build-time configuration.
///
/// Everything here is resolved at COMPILE TIME via --dart-define, so each
/// release flavor gets exactly the config it needs and nothing else ships.
/// The GitHub workflow passes the right defines per flavor (playstore vs
/// f-droid vs dev) — see .github/workflows/build.yml.
///
/// Adding a new feature toggle is one line here + one --dart-define in the
/// workflow matrix. Defaults are the Play Store (full-featured) values, so a
/// bare `flutter build` always produces a sane build.
class AppConfig {
  AppConfig._();

  /// ---- Flavor ----------------------------------------------------------
  /// 'play'   — Google Play release: full features, real API, notifications.
  /// 'fdroid' — F-Droid build: no Play-services-bound features, own branding.
  /// 'dev'    — local/CI verification build: insecure TLS allowed, dev URL.
  static const String flavor = String.fromEnvironment(
    'ENCLAVD_FLAVOR',
    defaultValue: 'play',
  );

  static bool get isFdroid => flavor == 'fdroid';
  static bool get isDev => flavor == 'dev';

  /// ---- API --------------------------------------------------------------
  /// Production API root. Override for dev via:
  /// --dart-define=ENCLAVD_API_BASE_URL=https://localhost
  static const String apiBaseUrl = String.fromEnvironment(
    'ENCLAVD_API_BASE_URL',
    defaultValue: 'https://enclavd.com',
  );

  /// The User-Agent this app sends on EVERY request. The server agent-binds
  /// each login session to the exact UA string sent at login — a mismatch on
  /// any later request invalidates the session server-side.
  ///
  /// This string is therefore part of the session contract: NEVER change it
  /// between app versions, or every installed client gets logged out. One
  /// string for all platforms on purpose (an Android and an iOS client must
  /// authenticate identically against the same account).
  static const String userAgent = String.fromEnvironment(
    'ENCLAVD_USER_AGENT',
    defaultValue: 'EnclavdNative/1.0',
  );

  /// Allow self-signed TLS (dev stack runs https on a self-signed cert).
  /// NEVER enabled in play/fdroid flavors — the workflow only passes this
  /// for the dev matrix.
  static const bool allowInsecureTls = bool.fromEnvironment(
    'ENCLAVD_ALLOW_INSECURE_TLS',
    defaultValue: false,
  );

  /// ---- Feature toggles ---------------------------------------------------
  /// Global switches so a flavor can drop whole feature areas without code
  /// changes. Notifications are GMS-free (live SSE/WS + WorkManager polling
  /// + Unified Push), so every flavor gets them; only FCM is Play-bound.
  static const bool enableNotifications = bool.fromEnvironment(
    'ENCLAVD_FEATURE_NOTIFICATIONS',
    defaultValue: true,
  );

  /// Whether this build MAY use FCM (Google Play Services). The F-Droid
  /// build must never touch GMS, so it skips FCM entirely and uses
  /// Unified Push (when a distributor is installed) or the 15-minute
  /// polling fallback. Play/dev builds try FCM first, then Unified Push,
  /// then the fallback — see PushManager in lib/services/push/.
  static const bool enableFcm = flavor != 'fdroid';

  static const bool enableChat = bool.fromEnvironment(
    'ENCLAVD_FEATURE_CHAT',
    defaultValue: true,
  );

  static const bool enableSearch = bool.fromEnvironment(
    'ENCLAVD_FEATURE_SEARCH',
    defaultValue: true,
  );

  /// ---- Network ------------------------------------------------------------
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const int httpClientRetries = 2; // transient network failures

  /// ---- Analytics -----------------------------------------------------------
  /// The app's own self-hosted Plausible (the website's analytics, proxied
  /// by the web server on :2000). The app POSTs pageviews to the SAME
  /// endpoint the site's header script.js uses, so app screens land in the
  /// same dashboard as web pages.
  static const String analyticsEndpoint =
      'https://enclavd.com:2000/api/event';

  /// The Plausible site the events belong to (the site's data-domain).
  static const String analyticsDomain = 'enclavd.com';

  /// User-Agent sent on analytics requests. Plausible silently drops
  /// events whose UA is not browser-like, so the app's own UA
  /// (EnclavdNative/1.0) would be discarded. This is the PINNED Chrome/124
  /// string the old WebView wrapper always sent — it passes the bot filter
  /// AND keeps the same visitor identity for the same phone across app
  /// versions (Plausible identifies visitors by IP + UA hash).
  static const String analyticsUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// ---- Feed ---------------------------------------------------------------
  static const int feedPageSize = 10; // matches api/v1 default limit range
  static const int feedFetchBeyond = 2; // pages fetched ahead of the fold

  /// ---- Auth ----------------------------------------------------------------
  /// The login page's hidden token field name (server contract, auth.php).
  static const String loginTokenField = 'login_token';

  /// HTTP header names used by the API layer.
  static const String hdrCsrf = 'X-CSRF-Token';
  static const String hdrCookie = 'Cookie';
  static const String hdrUserAgent = 'User-Agent';

  /// Redirect limit for the login/register POST flows (server 302s to
  /// /feed or back to /login|/register with a session flash message).
  static const int maxRedirects = 5;
}
