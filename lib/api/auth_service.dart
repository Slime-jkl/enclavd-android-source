import 'api_client.dart';
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
  });

  final int id;
  final String username;
  final String profilePictureUrl;
  final String rank;
  final String? personalityType;
  final int prestige;
  final bool isAdmin;
  final String dateCreated;

  /// Absolute URL for the avatar (server sends a root-relative path).
  String avatarUrl(String base) =>
      profilePictureUrl.startsWith('/') ? '$base$profilePictureUrl' : profilePictureUrl;

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ?? '/assets/default-avatar.png',
        rank: json['rank'] as String? ?? 'Member',
        personalityType: json['personality_type'] as String?,
        prestige: (json['prestige'] as num?)?.toInt() ?? 0,
        isAdmin: json['is_admin'] as bool? ?? false,
        dateCreated: json['date_created'] as String? ?? '',
      );
}

/// Result of the legacy login POST: which way the server redirected.
enum LoginOutcome { success, failure, blocked }

class LoginResult {
  const LoginResult(this.outcome, this.message);

  final LoginOutcome outcome;
  final String message; // server flash message on failure, empty on success
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
  /// Outcome detection: the server 302s to /feed on success, back to /login
  /// on failure (session flash error rendered on that page). We keep the 302
  /// (postForm does not follow), so `location` IS the verdict.
  Future<LoginResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
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
    });

    final location = resp.location;
    if (location != null && location.contains('/feed')) {
      // Session cookies (enclavd_sid + sid) were captured from this 302.
      return const LoginResult(LoginOutcome.success, '');
    }
    // Failure — the flash message renders on the redirect target page
    // (usually /login). Fetch it with the same jar and parse the banner.
    final message = await _flashFromRedirect(resp);
    return LoginResult(LoginOutcome.failure, message);
  }

  /// Registers a new account. Returns the server's flash message
  /// (success: "check your email", or the validation error text).
  ///
  /// The server 302s to /login on success (email verification is on), back
  /// to /register on failure with the validation errors in a flash banner.
  Future<String> register({
    required String username,
    required String email,
    required String password,
    String? invitation,
    bool acceptPrivacy = false,
    bool acceptTerms = false,
  }) async {
    final resp = await _api.postForm('/process_register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      'password_confirm': password,
      if (invitation != null && invitation.isNotEmpty) 'invitation': invitation.trim(),
      if (acceptPrivacy) 'privacy_policy': 'on',
      if (acceptTerms) 'terms': 'on',
    });

    final location = resp.location;
    if (location != null && location.contains('/login')) {
      return 'Registration submitted. Check your email to verify your account, then log in.';
    }
    return _flashFromRedirect(resp);
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

  /// On a failed login/register the server 302s back to the form page with a
  /// session flash message. Fetch that target (same cookie jar — the PHP
  /// session holds the flash) and parse the banner text.
  Future<String> _flashFromRedirect(RawResponse resp) async {
    final location = resp.location;
    if (location != null && location.startsWith('/')) {
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
