import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/site_config_service.dart';
import '../main.dart';
import 'ban_screen.dart';
import 'feed_screen.dart';
import 'maintenance_screen.dart';
import 'register_screen.dart';

/// Login screen — mirrors the website's login.php card:
/// email + password + remember-me, on the dark primaryCard surface.
/// Server errors (flash messages from the redirect loop) surface verbatim.
///
/// Rate limiting (site_config rate_limit): on load and after every failed
/// attempt the screen reads GET /api/v1/auth?action=rate_state&context=login
/// and reflects it — a cooldown/IP-lock countdown banner with the submit
/// button disabled, and the captcha question + answer field when the
/// limiter demands it (the answer rides the login POST as captcha_answer).
/// The server still enforces everything; the UI is proactive, not a bypass.
///
/// Keyboard notes: NO autofillHints here — on Android the autofill service
/// detaches the IME after the first keystroke ("keyboard closes after the
/// first character, then works"), a known Flutter/autofill bug. Fields use
/// explicit FocusNodes + textInputAction instead. The scroll view uses the
/// LayoutBuilder min-height pattern so the card stays centered when short
/// and scrolls without jumping when the IME shrinks the viewport.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.auth, this.siteConfig});

  static const routeName = '/login';

  /// Test seams — bypass AppServices when provided.
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
  String? _error;
  String? _success;

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
    await _loadRateState(config);
  }

  Future<void> _loadRateState(SiteConfigService config) async {
    try {
      final state = await config.rateState('login');
      if (!mounted) return;
      setState(() {
        _rl = state;
        _syncCountdown(state);
      });
    } catch (_) {
      // No state → proceed without the rate-limit UI; the server still
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
    // The lock may still be active server-side — re-check before enabling.
    _initRateLimit();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
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
        _postLogin(auth, config);
      } else {
        setState(() {
          _busy = false;
          _error = result.message;
        });
        _captcha.clear();
        // The server recorded the failure — refresh cooldown/captcha.
        _loadRateState(config);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('ApiException', 'Error');
      });
    }
  }

  /// Post-login gate: banned → ban screen, maintenance without a allowed
  /// rank → maintenance screen, otherwise the feed. A transient me()/config
  /// failure falls through to the feed (the server gates its own pages).
  Future<void> _postLogin(AuthService auth, SiteConfigService config) async {
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
    final rateMessage = _rateLimitMessage();
    final captchaNeeded = _rl?.captchaRequired ?? false;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight - 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Login',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 24),
                              if (_error != null) ...[
                                _Banner(message: _error!, isError: true),
                                const SizedBox(height: 16),
                              ],
                              if (_success != null) ...[
                                _Banner(message: _success!, isError: false),
                                const SizedBox(height: 16),
                              ],
                              if (rateMessage != null) ...[
                                _Banner(message: rateMessage, isError: true),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _email,
                                focusNode: _emailFocus,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  hintText: 'you@example.com',
                                  prefixIcon: FaIcon(
                                      FontAwesomeIcons.envelope,
                                      size: 18),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Enter your email'
                                        : null,
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon:
                                      FaIcon(FontAwesomeIcons.lock, size: 18),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Enter your password'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              if (captchaNeeded) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFCD34D)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFFCD34D)
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const FaIcon(
                                          FontAwesomeIcons.shieldHalved,
                                          size: 16,
                                          color: Color(0xFFFCD34D)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _rl?.captchaQuestion ??
                                              'Security question',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _captcha,
                                  focusNode: _captchaFocus,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Answer',
                                    prefixIcon: FaIcon(
                                        FontAwesomeIcons.key, size: 18),
                                  ),
                                  validator: (_) => captchaNeeded &&
                                          _captcha.text.trim().isEmpty
                                      ? 'Answer the question above'
                                      : null,
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(
                                        () => _rememberMe = v ?? false),
                                  ),
                                  const Text('Remember me'),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed:
                                    (_busy || rateMessage != null) ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FaIcon(
                                              FontAwesomeIcons
                                                  .arrowRightToBracket,
                                              size: 15,
                                              color: Colors.white),
                                          SizedBox(width: 8),
                                          Text('Login'),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pushReplacementNamed(
                                      RegisterScreen.routeName);
                                },
                                child: const Text(
                                    "Don't have an account? Create one"),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFF87171) : const Color(0xFF4ADE80);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}
