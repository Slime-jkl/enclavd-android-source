import 'api_client.dart';

/// Site-wide config from GET /api/v1/site_config (public, no auth).
class SiteConfig {
  const SiteConfig({
    required this.isInvitationRequired,
    required this.maintenance,
    required this.rateLimit,
  });

  final bool isInvitationRequired;
  final MaintenanceConfig maintenance;
  final RateLimitConfig rateLimit;

  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
        isInvitationRequired: json['isInvitationRequired'] as bool? ?? false,
        maintenance: MaintenanceConfig.fromJson(
            (json['maintenance'] as Map?)?.cast<String, dynamic>() ??
                const {}),
        rateLimit: RateLimitConfig.fromJson(
            (json['rate_limit'] as Map?)?.cast<String, dynamic>() ??
                const {}),
      );
}

/// Maintenance-mode settings (site_config.php 'maintenance').
class MaintenanceConfig {
  const MaintenanceConfig({
    required this.enabled,
    required this.allowedRanks,
    required this.reason,
    required this.estTime,
  });

  final bool enabled;

  /// accounts.rank values that may use the app during maintenance.
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

/// Rate-limiting settings (site_config.php 'rate_limit').
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

  /// Seconds to wait, keyed by the failed-attempt number (1-indexed).
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

/// Live rate-limit state for one context (login|register), from
/// GET /api/v1/auth?action=rate_state&context=…
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

  /// Seconds remaining in the current cooldown (0 = none).
  final int cooldown;
  final bool needsCaptcha;

  /// Captcha already solved in this cooldown window.
  final bool captchaOk;

  /// Seconds until an IP hard-lock expires (0 = not locked).
  final int lockRemaining;
  final String? captchaQuestion;

  /// The user must answer the captcha on the next submit.
  bool get captchaRequired => needsCaptcha && !captchaOk;

  /// How long to wait before the next attempt (cooldown or lock).
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

/// SiteConfigService: public site config + live rate-limit state.
class SiteConfigService {
  SiteConfigService(this._api);

  final ApiClient _api;

  /// Public site config (invitation requirement, maintenance, rate limits).
  Future<SiteConfig> fetch() async {
    final json = await _api.getJson('/api/v1/site_config');
    final config = json['config'];
    if (config is! Map<String, dynamic>) {
      throw const ApiException('Invalid config from server');
    }
    return SiteConfig.fromJson(config);
  }

  /// Current rate-limit state for a context ('login' or 'register').
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
