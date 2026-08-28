/// Enclavd native app - build-time configuration.
///
/// Everything here is resolved at compile time via --dart-define, so each
/// release flavor gets exactly the config it needs (playstore vs f-droid
/// vs dev; see .github/workflows/build.yml). Defaults are the Play Store
/// values, so a bare build always produces a sane build.
class AppConfig {
  AppConfig._();

  /// 'play' = Google Play release; 'fdroid' = no Play-bound features;
  /// 'dev' = insecure TLS allowed, dev URL.
  static const String flavor = String.fromEnvironment(
    'ENCLAVD_FLAVOR',
    defaultValue: 'play',
  );

  static bool get isFdroid => flavor == 'fdroid';
  static bool get isDev => flavor == 'dev';

  /// Production API root; override for dev via
  /// --dart-define=ENCLAVD_API_BASE_URL=https://localhost
  static const String apiBaseUrl = String.fromEnvironment(
    'ENCLAVD_API_BASE_URL',
    defaultValue: 'https://enclavd.com',
  );

  /// Sent on EVERY request. The server agent-binds each login session to
  /// this exact UA string; a mismatch on any later request invalidates the
  /// session. NEVER change it between app versions, or every installed
  /// client gets logged out. One string for all platforms on purpose.
  static const String userAgent = String.fromEnvironment(
    'ENCLAVD_USER_AGENT',
    defaultValue: 'EnclavdNative/1.0',
  );

  /// Allow self-signed TLS (dev stack runs https on a self-signed cert);
  /// never passed for the play/fdroid flavors.
  static const bool allowInsecureTls = bool.fromEnvironment(
    'ENCLAVD_ALLOW_INSECURE_TLS',
    defaultValue: false,
  );

  /// Global switches so a flavor can drop whole feature areas without code
  /// changes. Notifications are GMS-free (live SSE/WS + WorkManager
  /// polling + Unified Push); only FCM is Play-bound.
  static const bool enableNotifications = bool.fromEnvironment(
    'ENCLAVD_FEATURE_NOTIFICATIONS',
    defaultValue: true,
  );

  /// Whether this build MAY use FCM. F-Droid never touches GMS: it skips
  /// FCM entirely and uses Unified Push (when a distributor is installed)
  /// or the 15-minute polling fallback; play/dev try FCM first.
  static const bool enableFcm = flavor != 'fdroid';

  static const bool enableChat = bool.fromEnvironment(
    'ENCLAVD_FEATURE_CHAT',
    defaultValue: true,
  );

  static const bool enableSearch = bool.fromEnvironment(
    'ENCLAVD_FEATURE_SEARCH',
    defaultValue: true,
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const int httpClientRetries = 2; // transient network failures

  /// The app's own self-hosted Plausible (the website's analytics, proxied
  /// by the web server on :2000); app screens land in the same dashboard
  /// as web pages.
  static const String analyticsEndpoint =
      'https://enclavd.com:2000/api/event';

  /// The Plausible site the events belong to (the site's data-domain).
  static const String analyticsDomain = 'enclavd.com';

  /// Plausible silently drops events whose UA is not browser-like. This
  /// PINNED Chrome/124 string (what the old WebView wrapper always sent)
  /// passes the bot filter and keeps the same visitor identity for the
  /// same phone across app versions (IP + UA hash).
  static const String analyticsUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static const int feedPageSize = 10; // matches api/v1 default limit range
  static const int feedFetchBeyond = 2; // pages fetched ahead of the fold

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
