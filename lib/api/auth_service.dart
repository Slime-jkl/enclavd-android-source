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

  /// is_active === false: the account is banned and the app shows the ban
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
        // Server sends a real bool; missing/old payloads default to
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
/// accepted the account; [fieldErrors] maps each failing input to its own
/// message (api/v1/register's `fields` map).
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

/// Post-login gate verdict - what to show instead of the feed.
enum Gate { feed, ban, maintenance }

/// Outcome of a resend-verification-email attempt: [sent] is true when
/// the server reports a fresh confirmation link was mailed.
class ResendResult {
  const ResendResult({required this.sent, required this.message});

  final bool sent;
  final String message;
}

/// Decides where a just-authenticated (or session-restored) user goes:
/// banned -> ban screen; maintenance on + rank not allowed -> maintenance
/// screen; otherwise the feed. A transient config-fetch failure lets the
/// user through - the web server still enforces both gates itself.
Future<Gate> resolveGate(CurrentUser user, SiteConfigService config) async {
  if (user.banned) return Gate.ban;
  try {
    final cfg = await config.fetch();
    if (cfg.maintenance.enabled &&
        !cfg.maintenance.allowedRanks.contains(user.rank)) {
      return Gate.maintenance;
    }
  } catch (_) {
    // Ignore: fall through to the feed.
  }
  return Gate.feed;
}

/// Login / register / me / logout against the SAME endpoints the website
/// uses (api/v1 has no login/register - only logout). Login: GET /login
/// for the login_token, POST /auth; success 302s to /feed, failure back
/// to /login with a session flash.
class AuthService {
  AuthService(this._api, {required this.apiBaseUrl});

  final ApiClient _api;
  final String apiBaseUrl;

  /// Underlying client, for public GET endpoints with no dedicated
  /// service (e.g. the geo country/city pickers).
  ApiClient get api => _api;

  /// Fetches /login and extracts the login_token; null when the field is
  /// missing (page shape changed).
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

  /// Logs in with email + password (remember_me = 30-day session, server
  /// contract). captchaAnswer must be supplied when the rate-limiter says
  /// so. The 302 Location IS the verdict: /feed = success.
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
    // Failure: the flash message renders on the redirect target (usually
    // /login); fetch it with the same jar and parse the banner.
    final message = await _flashFromRedirect(resp);
    return LoginResult(LoginOutcome.failure, message);
  }

  /// Registers a new account. Primary: POST /api/v1/register (JSON + CSRF;
  /// 200 {success, requires_email_verification} or 422 {error, fields}).
  /// Fallback: the legacy form flow (POST /process_register -> 302) while
  /// the api/v1 endpoint is not deployed yet (deploy skew).
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

    // Not deployed yet: the legacy 302 flow (deploy skew protection).
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

  /// Legacy registration path: POST /process_register; success is a
  /// redirect to /login, failure back to /register with a flash banner.
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

  /// GET /resend_verification?email=... - the site's resend page. It 302s
  /// to /login with a session flash; the banner class is the verdict
  /// (info-green = a fresh confirmation link was mailed).
  Future<ResendResult> resendVerificationEmail(String email) async {
    final resp = await _api
        .getPage('/resend_verification', query: {'email': email.trim()});
    final (cls, message) = _flashFromPage(resp.body);
    return ResendResult(sent: cls == 'info-green', message: message);
  }

  /// GET /api/v1/me; null when the session is dead (401). The "am I still
  /// logged in" probe used at app start.
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

  /// POST /api/v1/auth {action:'logout'}; JSON body + X-CSRF-Token header
  /// (a form body 400s).
  Future<void> logout() async {
    try {
      await _api.postJson('/api/v1/auth', {'action': 'logout'});
    } on ApiException {
      // Logout must never hard-fail the UI: clear locally regardless.
    }
    // Clear BOTH the jar and the store, or a failed server-side logout
    // would leave the app "logged in" until restart.
    await _api.clearSession();
  }

  /// The legacy endpoints redirect with both absolute (/feed) and RELATIVE
  /// Location headers ("login" - no leading slash); normalize both shapes.
  String? _normalizeLocation(String? location) {
    if (location == null || location.isEmpty) return null;
    return location.startsWith('/') ? location : '/$location';
  }

  /// Failed login/register 302s back to the form page with a session
  /// flash; fetch that target (same cookie jar) and parse the banner.
  Future<String> _flashFromRedirect(RawResponse resp) async {
    final location = _normalizeLocation(resp.location);
    if (location != null) {
      try {
        final page = await _api.getPage(location);
        if (page.status == 200) {
          final (_, flash) = _flashFromPage(page.body);
          if (flash.isNotEmpty) return flash;
        }
      } on ApiException {
        // Fall through to the generic message below.
      }
    }
    return 'Request failed. Please try again.';
  }

  /// Parses the session-flash banner (class + text) from a rendered page.
  /// The class lets callers (e.g. resend-verification) tell success apart
  /// from refusal without guessing from the wording.
  (String, String) _flashFromPage(String html) {
    if (html.isEmpty) return ('', 'Request failed. Please try again.');

    // info-red = error banner, info-green = success (login.php /
    // register.php markup).
    for (final cls in ['info-red', 'info-green']) {
      final re = RegExp(
        r'<div[^>]*class="[^"]*' + cls + r'[^"]*"[^>]*>\s*<p[^>]*>(.*?)</p>',
        dotAll: true,
      );
      final m = re.firstMatch(html);
      if (m != null) {
        return (cls, _stripTags(_decodeEntities(m.group(1)!)).trim());
      }
      // Some banners nest the message without a <p> (rate-limit banner).
      final m2 = RegExp(
        r'<div[^>]*class="[^"]*' + cls + r'[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(html);
      if (m2 != null) {
        final text = _stripTags(_decodeEntities(m2.group(1)!)).trim();
        if (text.isNotEmpty) return (cls, text);
      }
    }
    return ('', 'Request failed. Please try again.');
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

/// Resolves feed image URLs per the api/v1 contract: root-relative avatar
/// paths get the base prefix; bare post image filenames go to
/// /public/gallery/.
String resolveMediaUrl(String base, {String? avatarPath, String? galleryName}) {
  if (avatarPath != null && avatarPath.isNotEmpty) {
    return avatarPath.startsWith('/') ? '$base$avatarPath' : avatarPath;
  }
  if (galleryName != null && galleryName.isNotEmpty) {
    return '$base/public/gallery/$galleryName';
  }
  return '$base/assets/default-avatar.png';
}
