import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/auth_service.dart';
import '../api/api_client.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import 'login_screen.dart';

/// Post-registration screen shown when the site requires email
/// verification (site_config requireEmailVerification): tells the user to
/// confirm their email and hands them to login once they have.
///
/// Offers a "Resend email" button with a client-side cooldown: it starts
/// DISABLED showing a 60-second countdown and gains 60 more seconds on
/// every attempt (60 → 120 → 180 → …). The resend hits the site's
/// resend_verification page (GET ?email=…), whose session flash reports
/// whether a fresh confirmation link was mailed.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email = '', this.auth});

  static const routeName = '/verify_email';

  /// The address the confirmation link was sent to — what the resend
  /// button targets. Empty (named-route pushes without args) hides the
  /// button entirely.
  final String email;

  /// Test seam — bypasses AppServices when provided.
  final AuthService? auth;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  /// Seconds left before the resend button re-enables. Starts at 60 and
  /// gains 60 more per attempt (user spec).
  int _cooldown = 60;

  /// Completed resend attempts — the cooldown is 60 × (attempts + 1).
  int _attempts = 0;

  Timer? _timer;
  bool _resending = false;

  /// Outcome of the last resend attempt (server flash or transport error).
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _cooldown = 60 * (_attempts + 1);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) t.cancel();
    });
  }

  /// One resend attempt: hit the server, report the outcome, then add
  /// another 60s to the cooldown (each try costs a minute).
  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _status = null;
    });
    try {
      final auth = widget.auth ?? (await AppServices.create()).auth;
      final result = await auth.resendVerificationEmail(widget.email);
      if (!mounted) return;
      setState(() {
        _status = result.message;
        _statusIsError = !result.sent;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = friendlyErrorText(e);
        _statusIsError = true;
      });
    } finally {
      _attempts += 1;
      _startCooldown();
      if (mounted) setState(() => _resending = false);
    }
  }

  String _fmt(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final resendVisible = widget.email.isNotEmpty;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1628), EnclavdColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: EnclavdColors.link.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: FaIcon(FontAwesomeIcons.envelopeCircleCheck,
                              size: 38, color: EnclavdColors.link),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Verify your email',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'We sent a confirmation link to your email address. '
                      'Click it to activate your account, then come back '
                      'here to sign in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: EnclavdColors.textSecondary,
                          fontSize: 14,
                          height: 1.45),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Don\'t forget to check your spam folder.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: EnclavdColors.textSecondary,
                          fontSize: 13,
                          height: 1.45),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 20),
                      _StatusBanner(
                          message: _status!, isError: _statusIsError),
                    ],
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed(LoginScreen.routeName),
                      child: const Text('I have confirmed'),
                    ),
                    if (resendVisible) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed:
                            (_cooldown > 0 || _resending) ? null : _resend,
                        child: _resending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : Text(_cooldown > 0
                                ? 'Resend email (${_fmt(_cooldown)})'
                                : 'Resend email'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed(LoginScreen.routeName),
                      child: const Text('Back to login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

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
      child: Text(message,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 13)),
    );
  }
}
