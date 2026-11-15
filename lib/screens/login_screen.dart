import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/auth_service.dart';
import '../api/site_config_service.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/daily_quote_service.dart';
import '../services/notification_taps.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/auth/auth_scaffold.dart';
import '../widgets/ui/app_button.dart';
import '../widgets/ui/app_checkbox.dart';
import '../widgets/ui/app_input_field.dart';
import '../widgets/ui/app_link_button.dart';
import '../widgets/ui/app_motion.dart';
import '../widgets/ui/app_surface.dart';
import 'ban_screen.dart';
import 'feed_screen.dart';
import 'maintenance_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.auth, this.siteConfig});

  static const routeName = '/login';

  /// Test seams: bypass AppServices when provided.
  final AuthService? auth;
  final SiteConfigService? siteConfig;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _captchaFocus = FocusNode();
  bool _rememberMe = true;
  bool _busy = false;
  bool _autovalidate = false;
  String? _error;

  RateLimitState? _rl;
  DateTime? _rlUntil; // cooldown or IP-lock end
  Timer? _rlTimer;

  @override
  void initState() {
    super.initState();
    _initRateLimit();
  }

  @override
  void dispose() {
    _rlTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _captcha.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _captchaFocus.dispose();
    super.dispose();
  }

  Future<(AuthService, SiteConfigService)> _services() async {
    final services = (widget.auth == null || widget.siteConfig == null)
        ? await AppServices.create()
        : null;
    return (
      widget.auth ?? services!.auth,
      widget.siteConfig ?? services!.siteConfig,
    );
  }

  Future<void> _initRateLimit() async {
    final (_, config) = await _services();
    // The public config carries the site's seasonal wordmark; without this
    // a cold start straight to login would only ever show the bundled mark.
    unawaited(_loadBranding(config));
    await _loadRateState(config);
  }

  Future<void> _loadBranding(SiteConfigService config) async {
    try {
      await config.fetch();
    } catch (_) {
      // Keep the bundled wordmark when the site can't be reached.
    }
  }

  Future<void> _loadRateState(SiteConfigService config) async {
    try {
      final state = await config.rateState('login');
      if (!mounted) return;
      setState(() {
        _rl = state;
        // Rate-limited states replace the server's static flash with a
        // live countdown; non-rate failures keep their banner.
        if (state.waitSeconds > 0 || state.blocked == true) {
          _error = null;
        }
        _syncCountdown(state);
      });
    } catch (_) {
      // No state -> proceed without the rate-limit UI; the server still
      // enforces cooldowns/captcha on POST.
    }
  }

  void _syncCountdown(RateLimitState state) {
    if (state.waitSeconds > 0) {
      _rlUntil = DateTime.now().add(Duration(seconds: state.waitSeconds));
      _rlTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _rlUntil = null;
      _rlTimer?.cancel();
      _rlTimer = null;
    }
  }

  void _tick() {
    if (!mounted) return;
    final until = _rlUntil;
    if (until == null) return;
    if (!DateTime.now().isAfter(until)) {
      setState(() {}); // refresh the countdown text
      return;
    }
    _rlTimer?.cancel();
    _rlTimer = null;
    setState(() => _rlUntil = null);
    // The lock may still be active server-side; re-check before enabling.
    _initRateLimit();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) {
      if (!_autovalidate) setState(() => _autovalidate = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final (auth, config) = await _services();
      final captchaNeeded = _rl?.captchaRequired ?? false;
      final result = await auth.login(
        email: _email.text,
        password: _password.text,
        rememberMe: _rememberMe,
        captchaAnswer: captchaNeeded ? _captcha.text : null,
      );
      if (!mounted) return;
      if (result.outcome == LoginOutcome.success) {
        // Hand the filled credentials to the platform autofill provider.
        TextInput.finishAutofillContext();
        _postLogin(auth, config);
      } else {
        setState(() {
          _busy = false;
          _error = result.message;
        });
        _captcha.clear();
        // The server recorded the failure; refresh cooldown/captcha.
        _loadRateState(config);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  Future<void> _openRecovery() async {
    try {
      await launchUrl(
        Uri.parse('${AppConfig.apiBaseUrl}/reset-password'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Defensive, like every other launcher call.
    }
  }

  Future<void> _postLogin(AuthService auth, SiteConfigService config) async {
    // Fresh session: catch the daily-quote widget up while it's valid.
    unawaited(DailyQuoteService.refreshWidgetNow());
    try {
      final user = await auth.me();
      if (user != null) {
        switch (await resolveGate(user, config)) {
          case Gate.ban:
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed(BanScreen.routeName);
            return;
          case Gate.maintenance:
            if (!mounted) return;
            Navigator.of(context)
                .pushReplacementNamed(MaintenanceScreen.routeName);
            return;
          case Gate.feed:
            break;
        }
      }
    } catch (_) {
      // Fall through to the feed.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(FeedScreen.routeName);
    // A tap that arrived with no session (or cold-started the app) lands on
    // its screen now that there is one.
    await NotificationTaps.resolvePending();
  }

  String? _rateLimitMessage() {
    final until = _rlUntil;
    if (until == null) return null;
    final secs = until.difference(DateTime.now()).inSeconds + 1;
    if (_rl?.blocked == true) {
      final mins = (secs / 60).ceil();
      return 'Too many failed attempts. Your IP is temporarily blocked. '
          'Please try again in $mins minute(s).';
    }
    return 'Too many failed attempts. Please wait $secs second(s) '
        'before trying again.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final rateMessage = _rateLimitMessage();
    final captchaNeeded = _rl?.captchaRequired ?? false;

    // A rate-limit countdown is the live, authoritative message and replaces
    // the server's frozen flash copy; otherwise the last failure shows.
    final notice = rateMessage ?? _error;
    final noticeTone =
        rateMessage != null ? AuthNoticeTone.warning : AuthNoticeTone.error;
    final canSubmit = !_busy && rateMessage == null;

    return AuthScaffold(
      title: 'Welcome back',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.fast,
                switchInCurve: AppMotion.enter,
                switchOutCurve: AppMotion.exit,
                child: notice == null
                    ? const SizedBox.shrink(key: ValueKey('notice-empty'))
                    : Padding(
                        key: ValueKey(
                          rateMessage != null ? 'notice-rate' : 'notice-error',
                        ),
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AuthNotice(message: notice, tone: noticeTone),
                      ),
              ),
              AppInputField(
                key: const Key('login-email'),
                controller: _email,
                focusNode: _emailFocus,
                enabled: !_busy,
                label: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: FontAwesomeIcons.envelope,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 14),
              AppInputField(
                key: const Key('login-password'),
                controller: _password,
                focusNode: _passwordFocus,
                label: 'Password',
                enabled: !_busy,
                prefixIcon: FontAwesomeIcons.lock,
                obscureText: true,
                showObscureToggle: true,
                autofillHints: const [AutofillHints.password],
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter your password' : null,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (captchaNeeded) ...[
                const SizedBox(height: 16),
                AppSurface(
                  padding: const EdgeInsets.all(12),
                  color: palette.warning.withValues(alpha: 0.07),
                  borderColor: palette.warning.withValues(alpha: 0.28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: FaIcon(
                              FontAwesomeIcons.shieldHalved,
                              size: 13,
                              color: palette.warning,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _rl?.captchaQuestion ?? 'Security question',
                              style: TextStyle(
                                color: palette.warning,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppInputField(
                        key: const Key('login-captcha'),
                        controller: _captcha,
                        focusNode: _captchaFocus,
                        enabled: !_busy,
                        label: 'Answer',
                        prefixIcon: FontAwesomeIcons.key,
                        textInputAction: TextInputAction.done,
                        validator: (_) =>
                            captchaNeeded && _captcha.text.trim().isEmpty
                                ? 'Answer the question above'
                                : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // Wrap, not Row: at large text scales the two controls stack
              // instead of overflowing.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  AppCheckbox(
                    value: _rememberMe,
                    onChanged:
                        _busy ? null : (v) => setState(() => _rememberMe = v),
                    label: 'Remember me',
                  ),
                  AppLinkButton(
                    key: const Key('login-forgot'),
                    onPressed: _busy ? null : _openRecovery,
                    label: 'Forgot password?',
                    fontSize: 12.5,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppButton(
                key: const Key('login-submit'),
                label: 'Sign in',
                icon: FontAwesomeIcons.arrowRightToBracket,
                expand: true,
                loading: _busy,
                onPressed: canSubmit ? _submit : null,
              ),
              const SizedBox(height: 18),
              const AppDivider(),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'New to Enclavd?',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  AppLinkButton(
                    key: const Key('login-register'),
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.of(context)
                                .pushReplacementNamed(RegisterScreen.routeName);
                          },
                    label: 'Create an account',
                    fontSize: 13,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
