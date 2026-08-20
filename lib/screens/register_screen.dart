import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'login_screen.dart';

/// Register screen — "Request Network Entry" (register.php).
///
/// Field contract with process_register.php:
///   username  3–20 chars, [a-zA-Z0-9_]
///   email     valid format, unique
///   password  ≥ 6 chars, must match password_confirm
///   invitation  required only when the site config demands it
///   privacy_policy + terms  checkboxes (required)
/// On success the server 302s to /login (email verification is on), and the
/// flash message tells the user to check their inbox.
///
/// No autofillHints (Android autofill detaches the IME after the first
/// keystroke — same keyboard bug as login).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _invitation = TextEditingController();

  bool _acceptPrivacy = false;
  bool _acceptTerms = false;
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    try {
      final services = await AppServices.create();
      final message = await services.auth.register(
        username: _username.text,
        email: _email.text,
        password: _password.text,
        invitation: _invitation.text,
        acceptPrivacy: _acceptPrivacy,
        acceptTerms: _acceptTerms,
      );
      if (!mounted) return;
      final success = message.contains('Check your email');
      setState(() {
        _busy = false;
        if (success) {
          _success = message;
        } else {
          _error = message;
        }
      });
      if (success) {
        // Registration done — go to login so the user can sign in after
        // verifying their email.
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(LoginScreen.routeName);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('ApiException', 'Error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Network Entry')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight - 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            _Banner(message: _error!, isError: true),
                            const SizedBox(height: 16),
                          ],
                          if (_success != null) ...[
                            _Banner(message: _success!, isError: false),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _username,
                            decoration: const InputDecoration(
                              labelText: 'Username *',
                              hintText: 'Choose a username',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.user, size: 18),
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return 'Username is required';
                              if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$')
                                  .hasMatch(s)) {
                                return '3–20 characters, letters, numbers, underscores only';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email address *',
                              hintText: 'you@example.com',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.envelope, size: 18),
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return 'Email is required';
                              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(s)) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password *',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.lock, size: 18),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Password is required';
                              }
                              if (v.length < 6) return 'At least 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordConfirm,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirm Password *',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.lock, size: 18),
                            ),
                            validator: (v) => v != _password.text
                                ? 'Passwords do not match'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: _acceptPrivacy,
                            onChanged: (v) =>
                                setState(() => _acceptPrivacy = v ?? false),
                            title: const Text('I accept the Privacy Policy'),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _acceptTerms,
                            onChanged: (v) =>
                                setState(() => _acceptTerms = v ?? false),
                            title: const Text('I accept the Terms of Service'),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Register'),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context)
                                  .pushReplacementNamed(LoginScreen.routeName);
                            },
                            child: const Text('Sign in instead'),
                          ),
                        ],
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
