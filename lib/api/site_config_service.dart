import 'api_client.dart';

// site-wide config from GET /api/v1/site_config (public, no auth)
class SiteConfig {
  const SiteConfig({
    required this.isInvitationRequired,
    this.requireEmailVerification = false,
    required this.maintenance,
    required this.rateLimit,
    this.nav = const [],
    this.features = const {},
  });

  final bool isInvitationRequired;
  final bool requireEmailVerification;
  final MaintenanceConfig maintenance;
  final RateLimitConfig rateLimit;

  /*
  The site's global nav rules (site config & nav_links), in order:
  which pages exist, their labels and the public-visibility flag. The
  app renders its menu from this list.
  */
  final List<NavLink> nav;

  final Map<String, String> features;

  String feature(String key) => features[key] ?? 'on';

  // Whether the feature renders for this user: 'on' for everyone,
  // 'off' for nobody, 'debug' for admins only.
  bool featureEnabled(String key, {required bool isAdmin}) {
    final state = feature(key);
    if (state == 'off') return false;
    if (state == 'debug') return isAdmin;
    return true;
  }

  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
        isInvitationRequired: json['isInvitationRequired'] as bool? ?? false,
        requireEmailVerification:
            json['requireEmailVerification'] as bool? ?? false,
        maintenance: MaintenanceConfig.fromJson(
            (json['maintenance'] as Map?)?.cast<String, dynamic>() ??
                const {}),
        rateLimit: RateLimitConfig.fromJson(
            (json['rate_limit'] as Map?)?.cast<String, dynamic>() ??
                const {}),
        nav: (json['nav'] as List?)
            ?.map((e) => NavLink.fromJson(
                (e as Map?)?.cast<String, dynamic>() ?? const {}))
            .toList() ??
            const [],
        features: (json['features'] as Map?)
            ?.map<String, String>((k, v) => MapEntry('$k', '$v')) ??
            const {},
      );
}

class NavLink {
  const NavLink({
    required this.url,
    required this.text,
    required this.public,
  });
/*
 * clean URL key of the page ('', 'articles', 'domain', ..etc). The app
 * maps each known url to its native screen; unknown urls are skipped
*/
  final String url;
  final String text;
  final bool public;

  factory NavLink.fromJson(Map<String, dynamic> json) => NavLink(
        url: json['url'] as String? ?? '',
        text: json['text'] as String? ?? '',
        public: json['public'] as bool? ?? false,
      );
}

/// Maintenance-mode settings on/off remotely in site config.
class MaintenanceConfig {
  const MaintenanceConfig({
    required this.enabled,
    required this.allowedRanks,
    required this.reason,
    required this.estTime,
  });

  final bool enabled;

  // user rank values that may use the app during maintenance.
  final List<String> allowedRanks;
  final String reason;
  final String estTime;

  factory MaintenanceConfig.fromJson(Map<String, dynamic> json) =>
      MaintenanceConfig(
        enabled: json['enabled'] as bool? ?? false,
        allowedRanks:
            (json['allowed_ranks'] as List?)?.cast<String>() ?? const [],
        reason: json['reason'] as String? ?? '',
        estTime: json['estTime'] as String? ?? '',
      );
}

// eate-limiting settings (site config 'rate_limit').
class RateLimitConfig {
  const RateLimitConfig({
    required this.enabled,
    required this.cooldowns,
    required this.captchaAt,
    required this.lockAt,
    required this.lockDuration,
    required this.appliesTo,
  });

  final bool enabled;

  // Seconds to wait, keyed by the failed-attempt number
  final Map<int, int> cooldowns;
  final int captchaAt;
  final int lockAt;
  final int lockDuration;
  final List<String> appliesTo;

  factory RateLimitConfig.fromJson(Map<String, dynamic> json) {
    final cooldowns = <int, int>{};
    (json['cooldowns'] as Map?)?.forEach((k, v) {
      final attempt = int.tryParse('$k');
      final seconds = v is num ? v.toInt() : int.tryParse('$v');
      if (attempt != null && seconds != null) cooldowns[attempt] = seconds;
    });
    return RateLimitConfig(
      enabled: json['enabled'] as bool? ?? true,
      cooldowns: cooldowns,
      captchaAt: (json['captcha_at'] as num?)?.toInt() ?? 4,
      lockAt: (json['lock_at'] as num?)?.toInt() ?? 0,
      lockDuration: (json['lock_duration'] as num?)?.toInt() ?? 900,
      appliesTo: (json['applies_to'] as List?)?.cast<String>() ??
          const ['login', 'register'],
    );
  }
}

// Live rate-limit state for one context login/register, from
// GET /api/v1/auth?action=rate_state&context=...
class RateLimitState {
  const RateLimitState({
    required this.blocked,
    required this.cooldown,
    required this.needsCaptcha,
    required this.captchaOk,
    required this.lockRemaining,
    this.captchaQuestion,
  });

  final bool blocked;

  // Seconds remaining in the current cooldown
  final int cooldown;
  final bool needsCaptcha;

  // Captcha already solved in this cooldown window
  final bool captchaOk;

  // Seconds until an IP hard-lock expires
  final int lockRemaining;
  final String? captchaQuestion;

  // The user must answer the captcha on the next submit
  bool get captchaRequired => needsCaptcha && !captchaOk;

  // How long to wait before the next attempt (cooldown or lock).
  int get waitSeconds => blocked ? lockRemaining : cooldown;

  factory RateLimitState.fromJson(Map<String, dynamic> json) =>
      RateLimitState(
        blocked: json['blocked'] as bool? ?? false,
        cooldown: (json['cooldown'] as num?)?.toInt() ?? 0,
        needsCaptcha: json['needs_captcha'] as bool? ?? false,
        captchaOk: json['captcha_ok'] as bool? ?? false,
        lockRemaining: (json['lock_remaining'] as num?)?.toInt() ?? 0,
        captchaQuestion: (json['captcha'] as Map?)
            ?.cast<String, dynamic>()['question'] as String?,
      );
}

// SiteConfigService: public site config + live rate-limit state.
class SiteConfigService {
  SiteConfigService(this._api);

  final ApiClient _api;

  // Public site config [ invitation requirement, maintenance, rate limits ]
  Future<SiteConfig> fetch() async {
    final json = await _api.getJson('/api/v1/site_config');
    final config = json['config'];
    if (config is! Map<String, dynamic>) {
      throw const ApiException('Invalid config from server');
    }
    return SiteConfig.fromJson(config);
  }

  // Current rate-limit state for a context login/register
  Future<RateLimitState> rateState(String context) async {
    final json = await _api.getJson(
      '/api/v1/auth',
      query: {'action': 'rate_state', 'context': context},
    );
    final state = json['state'];
    if (state is! Map<String, dynamic>) {
      throw const ApiException('Invalid rate state from server');
    }
    return RateLimitState.fromJson(state);
  }
}
