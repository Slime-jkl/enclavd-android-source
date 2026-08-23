import 'package:flutter/gestures.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/auth_service.dart';
import '../api/site_config_service.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/auth_password_field.dart';
import '../widgets/field_icon.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// Register screen — "Request Network Entry" (register.php), redesigned
/// as a modern app screen with the SAME fields as the website:
/// username, email, password + confirm (with visibility toggles),
/// invitation code (only when the site config demands it), date of
/// birth, gender, country/city (searchable pickers), and the
/// privacy/terms checkboxes.
///
/// Field contract with process_register.php:
///   username  3–20 chars, [a-zA-Z0-9_]
///   email     valid format, unique
///   password  ≥ 6 chars, must match password_confirm
///   invitation  required only when the site config demands it
///   birthdate   optional Y-m-d
///   gender      NONE | MALE | FEMALE (default NONE)
///   geo_country / geo_region / geo_city   optional ints
///   privacy_policy + terms  checkboxes (required)
///
/// On success: when the site config's requireEmailVerification is on the
/// user is sent to the verify-email screen ("I have confirmed" → login);
/// otherwise straight to login. Server validation errors surface in the
/// error banner (username taken, email registered, bad invitation…).
///
/// No autofillHints (Android autofill detaches the IME after the first
/// keystroke — same keyboard bug as login).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.auth, this.siteConfig});

  static const routeName = '/register';

  /// Test seams — bypass AppServices when provided.
  final AuthService? auth;
  final SiteConfigService? siteConfig;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _GeoCountry {
  const _GeoCountry({required this.id, required this.name, this.code = ''});

  final int id;
  final String name;
  final String code;
}

class _GeoCity {
  const _GeoCity(
      {required this.id, required this.name, required this.regionId});

  final int id;
  final String name;
  final int regionId;
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

  /// Server-side per-field errors (api/v1/register's `fields` map):
  /// keyed by username/email/password/password_confirm/invitation.
  /// Shown as errorText under the matching input, cleared on edit.
  Map<String, String> _fieldErrors = {};

  /// Server-side (or client-side) agreement error, shown under the
  /// privacy/terms checkboxes.
  String? _checkboxError;

  /// Live rate-limit state for the register context (cooldown + captcha),
  /// refreshed after every failed attempt — same pattern as login.
  RateLimitState? _rl;
  final _captcha = TextEditingController();
  final _captchaFocus = FocusNode();

  /// "Privacy Policy" / "Terms of Service" tap targets in the agreement
  /// rows — open the website's page in the browser (target=_blank parity).
  final _privacyTap = TapGestureRecognizer();
  final _termsTap = TapGestureRecognizer();

  /// True when the site requires an invitation code to sign up. Loaded from
  /// the public site config; until then (and on fetch failure) the field
  /// stays hidden — process_register.php enforces the requirement anyway.
  bool _invitationRequired = false;

  /// Email verification is on → successful signup shows the verify-email
  /// screen instead of jumping to login.
  bool _requireEmailVerification = false;

  // Optional profile fields (mirror register.php's optional section).
  String? _birthdate; // 'Y-m-d'
  String _gender = 'NONE';
  int? _countryId;
  int? _regionId;
  int? _cityId;
  String _countryName = '';
  String _cityName = '';
  List<_GeoCountry> _countries = const [];
  List<_GeoCity> _cities = const [];

  @override
  void initState() {
    super.initState();
    _privacyTap.onTap = () => _openLegal('/privacy_policy');
    _termsTap.onTap = () => _openLegal('/terms_of_service');
    _loadConfig();
  }

  /// Opens a website page in the system browser (the site's target=_blank).
  Future<void> _openLegal(String path) async {
    try {
      await launchUrl(
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Defensive, like every other launcher call.
    }
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

  Future<void> _loadConfig() async {
    try {
      final config = await (widget.siteConfig ??
              (await AppServices.create()).siteConfig)
          .fetch();
      if (!mounted) return;
      setState(() {
        _invitationRequired = config.isInvitationRequired;
        _requireEmailVerification = config.requireEmailVerification;
      });
    } catch (_) {
      // Keep the field hidden; the server validates on submit regardless.
    }
    await _loadRateState();
  }

  /// Live cooldown/captcha state for the register context. Refreshed on
  /// init and after every failed attempt (the server records the failure,
  /// which may bump the cooldown or demand a captcha). Failures here are
  /// ignored — the server still enforces on POST.
  Future<void> _loadRateState() async {
    try {
      final (_, config) = await _services();
      final state = await config.rateState('register');
      if (!mounted) return;
      setState(() => _rl = state);
    } catch (_) {
      // No state → proceed without the rate-limit UI.
    }
  }

  /// Clears a server-side field error once the user starts editing that
  /// field (a rebuild only when the error was actually present).
  void _clearFieldError(String key) {
    if (!_fieldErrors.containsKey(key)) return;
    setState(() => _fieldErrors = Map.of(_fieldErrors)..remove(key));
  }

  @override
  void dispose() {
    _privacyTap.dispose();
    _termsTap.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _invitation.dispose();
    _captcha.dispose();
    _captchaFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // The checkboxes are outside the Form's validators — gate them here
    // (same messages the server would bounce back with).
    final missingAgreement = !_acceptPrivacy
        ? 'You must accept the Privacy Policy'
        : (!_acceptTerms ? 'You must accept the Terms of Service' : null);
    if (missingAgreement != null) {
      setState(() => _checkboxError = missingAgreement);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
      _checkboxError = null;
    });

    try {
      final (auth, _) = await _services();
      final captchaNeeded = _rl?.captchaRequired ?? false;
      final result = await auth.register(
        username: _username.text,
        email: _email.text,
        password: _password.text,
        invitation: _invitation.text,
        acceptPrivacy: _acceptPrivacy,
        acceptTerms: _acceptTerms,
        birthdate: _birthdate,
        gender: _gender,
        geoCountry: _countryId,
        geoRegion: _regionId,
        geoCity: _cityId,
        captchaAnswer: captchaNeeded ? _captcha.text : null,
      );
      if (!mounted) return;
      if (result.submitted) {
        // Registration accepted — email verification decides the next step
        // (the api/v1 response is authoritative; the config is the fallback).
        // The email rides along so the verify screen can resend the
        // confirmation link.
        if (result.requiresEmailVerification || _requireEmailVerification) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => VerifyEmailScreen(email: _email.text.trim()),
            ),
          );
        } else {
          Navigator.of(context)
              .pushReplacementNamed(LoginScreen.routeName);
        }
        return;
      }

      // Rejection — split server errors into per-field + general. The
      // agreement errors render under the checkboxes; the rest attach to
      // their inputs; only general errors (rate limit, network, unknown)
      // show as the banner.
      final fields = Map.of(result.fieldErrors);
      setState(() {
        _busy = false;
        _fieldErrors = fields;
        _checkboxError = fields['privacy_policy'] ?? fields['terms'];
        _error = fields.isEmpty ? result.message : null;
      });
      _captcha.clear();
      // The server recorded the failure — refresh cooldown/captcha.
      _loadRateState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  Future<void> _pickBirthdate() async {
    final initial = _birthdate != null
        ? DateTime.tryParse(_birthdate!)
        : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: const DatePickerThemeData(
            backgroundColor: EnclavdColors.card,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthdate =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _loadCountries() async {
    if (_countries.isNotEmpty) return;
    try {
      final api = (await _services()).$1.api;
      final json = await api.getJson('/handlers/geo/get_countries.php');
      final data = json['data'];
      if (data is List) {
        final countries = data
            .whereType<Map<String, dynamic>>()
            .map((m) => _GeoCountry(
                  id: (m['id'] as num?)?.toInt() ?? 0,
                  name: m['name'] as String? ?? '',
                  code: m['code'] as String? ?? '',
                ))
            .toList();
        if (mounted) setState(() => _countries = countries);
      }
    } catch (_) {
      // Cosmetic — ids still save fine; the sheet shows empty.
    }
  }

  Future<void> _loadCities(int countryId) async {
    try {
      final api = (await _services()).$1.api;
      final json = await api.getJson('/handlers/geo/get_cities.php',
          query: {'country_id': '$countryId'});
      final data = json['data'];
      if (data is! List) return;
      final cities = data
          .whereType<Map<String, dynamic>>()
          .map((m) => _GeoCity(
                id: (m['id'] as num?)?.toInt() ?? 0,
                name: m['name'] as String? ?? '',
                regionId: (m['region_id'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      if (mounted) setState(() => _cities = cities);
    } catch (_) {
      // Cosmetic — the ids still save fine.
    }
  }

  Future<void> _pickCountry() async {
    await _loadCountries();
    if (!mounted) return;
    final picked = await showModalBottomSheet<_GeoCountry>(
      context: context,
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _GeoPickerSheet(countries: _countries),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _countryId = picked.id;
      _countryName = picked.name;
      _regionId = null;
      _cityId = null;
      _cityName = '';
      _cities = const [];
    });
    // Load the city list for the chosen country (lazy, like the site).
    await _loadCities(picked.id);
  }

  Future<void> _pickCity() async {
    final countryId = _countryId;
    if (countryId == null) return;
    if (_cities.isEmpty) await _loadCities(countryId);
    if (!mounted) return;
    final picked = await showModalBottomSheet<_GeoCity>(
      context: context,
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CityPickerSheet(cities: _cities),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _cityId = picked.id;
      _regionId = picked.regionId;
      _cityName = picked.name;
    });
  }

  /// Agreement-row label: "I accept the Privacy Policy" where the policy
  /// name is a link to the website's page (register.php parity — its
  /// checkboxes carry <a href="/privacy_policy" target="_blank">).
  Widget _agreementTitle(
    String prefix,
    String linkText,
    TapGestureRecognizer recognizer,
  ) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
            fontSize: 14, color: EnclavdColors.textPrimary),
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: linkText,
            style: const TextStyle(
              color: EnclavdColors.link,
              decoration: TextDecoration.underline,
              decorationColor: EnclavdColors.link,
            ),
            recognizer: recognizer,
          ),
        ],
      ),
    );
  }

  Widget _pickerField({
    required String label,
    required String value,
    required FaIconData icon,
    required VoidCallback onTap,
    String? hint,
  }) {
    final empty = value.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: FieldIcon(icon),
          suffixIcon: const FieldIcon(FontAwesomeIcons.chevronDown,
              size: 14, color: EnclavdColors.textSecondary),
        ),
        child: Text(
          empty ? (hint ?? 'Select') : value,
          style: TextStyle(
            color: empty
                ? EnclavdColors.textSecondary
                : EnclavdColors.textPrimary,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

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
          child: LayoutBuilder(
            builder: (context, viewport) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: viewport.maxHeight - 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: () => Navigator.of(context)
                                    .pushReplacementNamed(
                                        LoginScreen.routeName),
                                tooltip: 'Back to login',
                                icon: const FaIcon(
                                    FontAwesomeIcons.arrowLeft, size: 20),
                              ),
                            ),
                            Center(
                              child: Image.asset(
                                'assets/images/enclavd-logo-white.png',
                                height: 42,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox(height: 42),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Create your account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Join the Enclavd network',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: EnclavdColors.textSecondary,
                                  fontSize: 14),
                            ),
                            const SizedBox(height: 28),
                            if (_error != null) ...[
                              _Banner(message: _error!, isError: true),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: _username,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Username *',
                                hintText: 'Choose a username',
                                errorText: _fieldErrors['username'],
                                prefixIcon: const FieldIcon(
                                    FontAwesomeIcons.user),
                              ),
                              onChanged: (_) => _clearFieldError('username'),
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
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Email address *',
                                hintText: 'you@example.com',
                                errorText: _fieldErrors['email'],
                                prefixIcon: const FieldIcon(
                                    FontAwesomeIcons.envelope),
                              ),
                              onChanged: (_) => _clearFieldError('email'),
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
                            AuthPasswordField(
                              controller: _password,
                              label: 'Password *',
                              errorText: _fieldErrors['password'],
                              onChanged: (_) => _clearFieldError('password'),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Password is required';
                                }
                                if (v.length < 6) {
                                  return 'At least 6 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            AuthPasswordField(
                              controller: _passwordConfirm,
                              label: 'Confirm Password *',
                              errorText: _fieldErrors['password_confirm'],
                              onChanged: (_) =>
                                  _clearFieldError('password_confirm'),
                              validator: (v) => v != _password.text
                                  ? 'Passwords do not match'
                                  : null,
                            ),
                            if (_invitationRequired) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _invitation,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Invitation Code *',
                                  hintText: 'Enter your invitation code',
                                  errorText: _fieldErrors['invitation'],
                                  prefixIcon: const FieldIcon(
                                      FontAwesomeIcons.ticket),
                                ),
                                onChanged: (_) =>
                                    _clearFieldError('invitation'),
                                validator: (_) =>
                                    _invitation.text.trim().isEmpty
                                        ? 'An invitation code is required to join'
                                        : null,
                              ),
                            ],
                            const SizedBox(height: 16),
                            _pickerField(
                              label: 'Date of Birth',
                              value: _birthdate ?? '',
                              icon: FontAwesomeIcons.cakeCandles,
                              hint: 'Select your date of birth',
                              onTap: _pickBirthdate,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _gender,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                                prefixIcon: FieldIcon(
                                    FontAwesomeIcons.venusMars),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'NONE',
                                    child: Text('Prefer not to say')),
                                DropdownMenuItem(
                                    value: 'MALE', child: Text('Male')),
                                DropdownMenuItem(
                                    value: 'FEMALE', child: Text('Female')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _gender = v ?? 'NONE'),
                            ),
                            const SizedBox(height: 16),
                            _pickerField(
                              label: 'Country',
                              value: _countryName,
                              icon: FontAwesomeIcons.globe,
                              hint: 'Select your country',
                              onTap: _pickCountry,
                            ),
                            if (_countryId != null) ...[
                              const SizedBox(height: 16),
                              _pickerField(
                                label: 'City',
                                value: _cityName,
                                icon: FontAwesomeIcons.city,
                                hint: 'Select your city',
                                onTap: _pickCity,
                              ),
                            ],
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              value: _acceptPrivacy,
                              onChanged: (v) => setState(() {
                                _acceptPrivacy = v ?? false;
                                _checkboxError = null;
                              }),
                              title: _agreementTitle(
                                'I accept the ',
                                'Privacy Policy',
                                _privacyTap,
                              ),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                            CheckboxListTile(
                              value: _acceptTerms,
                              onChanged: (v) => setState(() {
                                _acceptTerms = v ?? false;
                                _checkboxError = null;
                              }),
                              title: _agreementTitle(
                                'I accept the ',
                                'Terms of Service',
                                _termsTap,
                              ),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (_checkboxError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _checkboxError!,
                                  style: const TextStyle(
                                      color: Color(0xFFF87171), fontSize: 13),
                                ),
                              ),
                            const SizedBox(height: 24),
                            if (_rl?.captchaRequired ?? false) ...[
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
                                        style:
                                            const TextStyle(fontSize: 13),
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
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: 'Answer',
                                  prefixIcon:
                                      FieldIcon(FontAwesomeIcons.key),
                                ),
                                validator: (_) =>
                                    (_rl?.captchaRequired ?? false) &&
                                            _captcha.text.trim().isEmpty
                                        ? 'Answer the question above'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                            ],
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
                                    .pushReplacementNamed(
                                        LoginScreen.routeName);
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

/// Searchable country picker (the site's country dropdown).
class _GeoPickerSheet extends StatefulWidget {
  const _GeoPickerSheet({required this.countries});

  final List<_GeoCountry> countries;

  @override
  State<_GeoPickerSheet> createState() => _GeoPickerSheetState();
}

class _GeoPickerSheetState extends State<_GeoPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.countries
        .where((c) =>
            _query.isEmpty ||
            c.name.toLowerCase().contains(_query.toLowerCase()) ||
            c.code.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: EnclavdColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search country',
                  hintStyle:
                      const TextStyle(color: EnclavdColors.textSecondary),
                  prefixIcon: const FieldIcon(
                      FontAwesomeIcons.magnifyingGlass,
                      size: 14,
                      color: EnclavdColors.textSecondary),
                  filled: true,
                  fillColor: EnclavdColors.cardSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: EnclavdColors.border),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No matches found',
                          style: TextStyle(
                              color: EnclavdColors.textSecondary)))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(c.name,
                              style: const TextStyle(fontSize: 14)),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable city picker (the site's city dropdown).
class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.cities});

  final List<_GeoCity> cities;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.cities
        .where((c) =>
            _query.isEmpty || c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: EnclavdColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search city',
                  hintStyle:
                      const TextStyle(color: EnclavdColors.textSecondary),
                  prefixIcon: const FieldIcon(
                      FontAwesomeIcons.magnifyingGlass,
                      size: 14,
                      color: EnclavdColors.textSecondary),
                  filled: true,
                  fillColor: EnclavdColors.cardSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: EnclavdColors.border),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No matches found',
                          style: TextStyle(
                              color: EnclavdColors.textSecondary)))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(c.name,
                              style: const TextStyle(fontSize: 14)),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
