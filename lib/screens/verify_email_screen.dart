import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import 'login_screen.dart';

/// Post-registration screen shown when the site requires email
/// verification (site_config requireEmailVerification): tells the user to
/// confirm their email and hands them to login once they have.
class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  static const routeName = '/verify_email';

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed(LoginScreen.routeName),
                      child: const Text('I have confirmed'),
                    ),
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
