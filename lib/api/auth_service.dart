import 'api_client.dart';
import 'site_config_service.dart';
import '../config/app_config.dart';

/// Account info from GET /api/v1/me (canonical user object).
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.username,
    required this.profilePictureUrl,
    required this.rank,
    required this.personalityType,
    required this.prestige,
    required this.isAdmin,
    required this.dateCreated,
    required this.banned,
    required this.blockReason,
  });

  final int id;
  final String username;
  final String profilePictureUrl;
  final String rank;
  final String? personalityType;
  final int prestige;
  final bool isAdmin;
  final String dateCreated;

  /// is_active === false → the account is banned; the app shows the ban
  /// screen instead of the feed.
  final bool banned;
  final String blockReason;

  /// Absolute URL for the avatar (server sends a root-relative path).
  String avatarUrl(String base) => profilePictureUrl.startsWith('/')
      ? '$base$profilePictureUrl'
      : profilePictureUrl;

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        rank: json['rank'] as String? ?? 'Member',
        personalityType: json['personality_type'] as String?,
        prestige: (json['prestige'] as num?)?.toInt() ?? 0,
        isAdmin: json['is_admin'] as bool? ?? false,
        dateCreated: json['date_created'] as String? ?? '',
        // The server sends a real bool; missing/old payloads default to
        // not-banned so the gate never false-positives on an old deploy.
        banned: json['is_active'] == false,
        blockReason: json['block_reason'] as String? ?? '',
      );
}

/// Result of the legacy login POST: which way the server redirected.
enum LoginOutcome { success, failure, blocked }

class LoginResult {
  const LoginResult(this.outcome, this.message);

  final LoginOutcome outcome;
  final String message; // server flash message on failure, empty on success
}

/// Outcome of a registration POST: [submitted] is true when the server
/// accepted the account, false when it bounced back with [message]
/// holding the general error and [fieldErrors] mapping each failing
/// input to its own message (api/v1/register's `fields` map; empty for
/// legacy-flash errors that carry no per-field structure).
class RegisterResult {
  const RegisterResult({
    required this.submitted,
    required this.message,
    this.fieldErrors = const {},
    this.requiresEmailVerification = false,
  });

  final bool submitted;
  final String message;
  final Map<String, String> fieldErrors;

  /// Server's word on whether email verification is required (the
  /// api/v1 response carries it; the config value is the fallback).
  final bool requiresEmailVerification;
}

/// Post-login gate verdict — what to show instead of the feed.
enum Gate { feed, ban, maintenance }

/// Decides where a just-authenticated (or session-restored) user goes:
///   - banned (is_active === false)      → ban screen, the app is denied;
///   - maintenance on + rank not allowed → maintenance screen;
///   - otherwise                         → the feed.
///
/// A transient config-fetch failure lets the user through — the web server
/// still enforces both gates on its own pages, so the app never becomes
/// stricter than the source of truth.
Future<Gate> resolveGate(CurrentUser user, SiteConfigService config) async {
  if (user.banned) return Gate.ban;
  try {
    final cfg = await config.fetch();
    if (cfg.maintenance.enabled &&
        !cfg.maintenance.allowedRanks.contains(user.rank)) {
      return Gate.maintenance;
    }
  } catch (_) {
    // Ignore — fall through to the feed.
  }
  return Gate.feed;
}

/// AuthService: login / register / me / logout against the SAME endpoints
/// the website uses (api/v1 has no login/register — only logout).
///
/// Login flow (verified end-to-end on the dev stack, Aug 2026):
///  1. GET /login            → parse `login_token` hidden field (the PHP
///                             session stores it; the form echoes it).
///  2. POST /auth (form)     → email, password, login_token, remember_me.
///     Success: 302 → /feed  + Set-Cookie enclavd_sid (DB session) + sid.
///     Failure: 302 → /login + session flash error rendered on the page.
///
/// Register flow:
///  1. POST /process_register (form) → username, email, password,
///     password_confirm, privacy_policy, terms (+ invitation if required).
///     Success: 302 → /login (then email verification, require_email_verification=true).
///     Failure: 302 → /register + session flash error rendered on the page.
class AuthService {
  AuthService(this._api, {required this.apiBaseUrl});

  final ApiClient _api;
  final String apiBaseUrl;

  /// The underlying client — used for public GET endpoints that have no
  /// dedicated service (e.g. the geo country/city pickers).
  ApiClient get api => _api;

  /// Fetches /login and extracts the login_token. Returns null when the
  /// token field is missing (page shape changed — fail with a clear error).
  Future<String?> fetchLoginToken() async {
    final resp = await _api.getPage('/login');
    if (resp.status != 200) {
      throw ApiException('Login page unavailable (${resp.status})');
    }
    final match = RegExp(
      r'name="login_token"\s+value="([^"]+)"',
    ).firstMatch(resp.body);
    return match?.group(1);
  }

  /// Logs in with email + password. remember_me grants a 30-day session
  /// instead of the default 7 (server contract, auth.php).
  ///
  /// captchaAnswer must be supplied when the rate-limiter state says the
  /// captcha is required (auth.php verifies it before the credentials).
  ///
  /// Outcome detection: the server 302s to /feed on success, back to /login
  /// on failure (session flash error rendered on that page). We keep the 302
  /// (postForm does not follow), so `location` IS the verdict.
  Future<LoginResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
    String? captchaAnswer,
  }) async {
    final token = await fetchLoginToken();
    if (token == null) {
      return const LoginResult(LoginOutcome.failure,
          'Could not start a login session. Please try again.');
    }

    final resp = await _api.postForm('/auth', {
      'email': email.trim(),
      'password': password,
      AppConfig.loginTokenField: token,
      if (rememberMe) 'remember_me': 'on',
      if (captchaAnswer != null && captchaAnswer.trim().isNotEmpty)
        'captcha_answer': captchaAnswer.trim(),
    });

    final location = _normalizeLocation(resp.location);
    if (location != null && location.contains('/feed')) {
      // Session cookies (enclavd_sid + sid) were captured from this 302.
      return const LoginResult(LoginOutcome.success, '');
    }
    // Failure — the flash message renders on the redirect target page
    // (usually /login). Fetch it with the same jar and parse the banner.
    final message = await _flashFromRedirect(resp);
    return LoginResult(LoginOutcome.failure, message);
  }

  /// Registers a new account. Returns whether the server accepted the
  /// submission and — on rejection — the per-field errors.
  ///
  /// Primary path: POST /api/v1/register (JSON + CSRF) — the structured
  /// endpoint added for the apps: 200 {success:true,
  /// requires_email_verification} or 422 {error, fields:{username:…}}.
  /// Fallback: the legacy form flow (POST /process_register → 302), used
  /// only while the api/v1 endpoint is not deployed yet (deploy skew);
  /// its flash banner is parsed the same way login's is.
  Future<RegisterResult> register({
    required String username,
    required String email,
    required String password,
    String? invitation,
    bool acceptPrivacy = false,
    bool acceptTerms = false,
    String? birthdate,
    String? gender,
    int? geoCountry,
    int? geoRegion,
    int? geoCity,
    String? captchaAnswer,
  }) async {
    final json = await _api.postJsonRelaxed('/api/v1/register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      'password_confirm': password,
      'invitation': invitation?.trim() ?? '',
      if (birthdate != null && birthdate.isNotEmpty) 'birthdate': birthdate,
      'gender': gender ?? 'NONE',
      if (geoCountry != null) 'geo_country': geoCountry,
      if (geoRegion != null) 'geo_region': geoRegion,
      if (geoCity != null) 'geo_city': geoCity,
      'privacy_policy': acceptPrivacy,
      'terms': acceptTerms,
      if (captchaAnswer != null && captchaAnswer.trim().isNotEmpty)
        'captcha_answer': captchaAnswer.trim(),
    });

    if (json['success'] == true) {
      return RegisterResult(
        submitted: true,
        message: 'Registration submitted.',
        requiresEmailVerification: json['requires_email_verification'] == true,
      );
    }

    // Not deployed yet → the legacy 302 flow (deploy skew protection).
    if (json['error'] == 'Request failed (404)') {
      return _registerLegacy(
        username: username,
        email: email,
        password: password,
        invitation: invitation,
        acceptPrivacy: acceptPrivacy,
        acceptTerms: acceptTerms,
        birthdate: birthdate,
        gender: gender,
        geoCountry: geoCountry,
        geoRegion: geoRegion,
        geoCity: geoCity,
      );
    }

    final fields = <String, String>{};
    final rawFields = json['fields'];
    if (rawFields is Map) {
      rawFields.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) fields[k] = v;
      });
    }
    return RegisterResult(
      submitted: false,
      message: json['error'] as String? ?? 'Request failed. Please try again.',
      fieldErrors: fields,
    );
  }

  /// Legacy registration path (POST /process_register → 302). Success is
  /// a redirect to /login, failure a redirect back to /register with a
  /// session flash banner on that page.
  Future<RegisterResult> _registerLegacy({
    required String username,
    required String email,
    required String password,
    String? invitation,
    required bool acceptPrivacy,
    required bool acceptTerms,
    String? birthdate,
    String? gender,
    int? geoCountry,
    int? geoRegion,
    int? geoCity,
  }) async {
    final resp = await _api.postForm('/process_register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      'password_confirm': password,
      if (invitation != null && invitation.isNotEmpty)
        'invitation': invitation.trim(),
      if (birthdate != null && birthdate.isNotEmpty) 'birthdate': birthdate,
      'gender': gender ?? 'NONE',
      if (geoCountry != null) 'geo_country': '$geoCountry',
      if (geoRegion != null) 'geo_region': '$geoRegion',
      if (geoCity != null) 'geo_city': '$geoCity',
      if (acceptPrivacy) 'privacy_policy': 'on',
      if (acceptTerms) 'terms': 'on',
    });

    final location = _normalizeLocation(resp.location);
    if (location != null && location.contains('/login')) {
      return const RegisterResult(
        submitted: true,
        message: 'Registration submitted.',
      );
    }
    return RegisterResult(
        submitted: false, message: await _flashFromRedirect(resp));
  }

  /// GET /api/v1/me → the logged-in user, or null when the session is dead
  /// (401). This is the "am I still logged in" probe used at app start.
  Future<CurrentUser?> me() async {
    try {
      final json = await _api.getJson('/api/v1/me');
      final user = json['user'];
      if (user is! Map<String, dynamic>) return null;
      return CurrentUser.fromJson(user);
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      rethrow;
    }
  }

  /// POST /api/v1/auth {action:'logout'} — the api/v1 session endpoint.
  /// JSON body + X-CSRF-Token header (api/v1 endpoints read JSON via
  /// api_input() and gate on api_csrf_guard(); a form body 400s).
  Future<void> logout() async {
    try {
      await _api.postJson('/api/v1/auth', {'action': 'logout'});
    } on ApiException {
      // Logout must never hard-fail the UI — clear locally regardless.
    }
    // Clear BOTH the in-memory jar and the persisted store, or a failed
    // server-side logout would leave the app "logged in" until restart.
    await _api.clearSession();
  }

  /// The legacy auth endpoints redirect with BOTH absolute (/feed) and
  /// RELATIVE Location headers ("login", "register" — no leading slash,
  /// per the PHP header('Location: login') calls). Normalize so outcome
  /// detection and the flash-page fetch work for both shapes.
  String? _normalizeLocation(String? location) {
    if (location == null || location.isEmpty) return null;
    return location.startsWith('/') ? location : '/$location';
  }

  /// On a failed login/register the server 302s back to the form page with a
  /// session flash message. Fetch that target (same cookie jar — the PHP
  /// session holds the flash) and parse the banner text.
  Future<String> _flashFromRedirect(RawResponse resp) async {
    final location = _normalizeLocation(resp.location);
    if (location != null) {
      try {
        final page = await _api.getPage(location);
        if (page.status == 200) {
          final flash = _flashFromPage(page.body);
          if (flash.isNotEmpty) return flash;
        }
      } on ApiException {
        // Fall through to the generic message below.
      }
    }
    return 'Request failed. Please try again.';
  }

  /// Extracts the session-flash error/success paragraph from a rendered
  /// page (the legacy flows communicate via flash + redirect only).
  String _flashFromPage(String html) {
    if (html.isEmpty) return 'Request failed. Please try again.';

    // info-red is the error banner, info-green the success one (login.php /
    // register.php markup).
    for (final cls in ['info-red', 'info-green']) {
      final re = RegExp(
        r'<div[^>]*class="[^"]*' + cls + r'[^"]*"[^>]*>\s*<p[^>]*>(.*?)</p>',
        dotAll: true,
      );
      final m = re.firstMatch(html);
      if (m != null) {
        return _stripTags(_decodeEntities(m.group(1)!)).trim();
      }
      // Some banners nest the message without a <p> (rate-limit banner).
      final m2 = RegExp(
        r'<div[^>]*class="[^"]*' + cls + r'[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(html);
      if (m2 != null) {
        final text = _stripTags(_decodeEntities(m2.group(1)!)).trim();
        if (text.isNotEmpty) return text;
      }
    }
    return 'Request failed. Please try again.';
  }

  String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), ' ');

  String _decodeEntities(String s) {
    final m = <String, String>{
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#039;': "'",
      '&nbsp;': ' ',
    };
    var out = s;
    m.forEach((k, v) => out = out.replaceAll(k, v));
    // Generic numeric entities.
    out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!)),
    );
    return out;
  }
}

/// Resolves feed image URLs per the api/v1 contract:
///  - profile_picture_url: root-relative ("/public/avatars/...") → prefix base.
///  - post image: BARE filename ("abc.jpg") → /public/gallery/<name>.
String resolveMediaUrl(String base, {String? avatarPath, String? galleryName}) {
  if (avatarPath != null && avatarPath.isNotEmpty) {
    return avatarPath.startsWith('/') ? '$base$avatarPath' : avatarPath;
  }
  if (galleryName != null && galleryName.isNotEmpty) {
    return '$base/public/gallery/$galleryName';
  }
  return '$base/assets/default-avatar.png';
}
