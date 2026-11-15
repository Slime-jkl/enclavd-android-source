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
import '../widgets/auth/auth_scaffold.dart';
import '../widgets/field_icon.dart';
import '../widgets/ui/app_button.dart';
import '../widgets/ui/app_checkbox.dart';
import '../widgets/ui/app_date_picker.dart';
import '../widgets/ui/app_input_field.dart';
import '../widgets/ui/app_link_button.dart';
import '../widgets/ui/app_option_sheet.dart';
import '../widgets/ui/app_picker_field.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/app_surface.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.auth, this.siteConfig});

  static const routeName = '/register';

  /// Test seams: bypass AppServices when provided.
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
  const _GeoCity({required this.id, required this.name, required this.regionId});

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

  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _passwordConfirmFocus = FocusNode();
  final _invitationFocus = FocusNode();
  final _captchaFocus = FocusNode();

  bool _acceptPrivacy = false;
  bool _acceptTerms = false;
  bool _busy = false;
  String? _error;

  Map<String, String> _fieldErrors = {};

  String? _checkboxError;

  RateLimitState? _rl;
  final _captcha = TextEditingController();

  final _privacyTap = TapGestureRecognizer();
  final _termsTap = TapGestureRecognizer();

  bool _invitationRequired = false;

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
      final config =
          await (widget.siteConfig ?? (await AppServices.create()).siteConfig)
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

  Future<void> _loadRateState() async {
    try {
      final (_, config) = await _services();
      final state = await config.rateState('register');
      if (!mounted) return;
      setState(() => _rl = state);
    } catch (_) {
      // No state -> proceed without the rate-limit UI.
    }
  }

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
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _passwordConfirmFocus.dispose();
    _invitationFocus.dispose();
    _captchaFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // The checkboxes sit outside the Form's validators; gate them here.
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
        // Accepted: email verification decides the next step; the email
        // rides along so the verify screen can resend the link.
        if (result.requiresEmailVerification || _requireEmailVerification) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => VerifyEmailScreen(email: _email.text.trim()),
            ),
          );
        } else {
          Navigator.of(context).pushReplacementNamed(LoginScreen.routeName);
        }
        return;
      }

      // Rejection: split server errors into per-field + general.
      final fields = Map.of(result.fieldErrors);
      setState(() {
        _busy = false;
        _fieldErrors = fields;
        _checkboxError = fields['privacy_policy'] ?? fields['terms'];
        _error = fields.isEmpty ? result.message : null;
      });
      _captcha.clear();
      // The server recorded the failure; refresh cooldown/captcha.
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
    final initial = _birthdate != null ? DateTime.tryParse(_birthdate!) : null;
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      title: 'Date of birth',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthdate = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
    _clearFieldError('birthdate');
  }

  String get _birthdateDisplay {
    final raw = _birthdate;
    if (raw == null) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  String get _genderDisplay {
    switch (_gender) {
      case 'MALE':
        return 'Male';
      case 'FEMALE':
        return 'Female';
      default:
        return 'Prefer not to say';
    }
  }

  Future<void> _pickGender() async {
    final picked = await showAppOptionSheet<String>(
      context: context,
      title: 'Gender',
      selected: _gender,
      options: const [
        AppOption(value: 'NONE', label: 'Prefer not to say'),
        AppOption(value: 'MALE', label: 'Male'),
        AppOption(value: 'FEMALE', label: 'Female'),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _gender = picked);
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
      // Cosmetic: ids still save fine; the sheet shows empty.
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
      // Cosmetic: the ids still save fine.
    }
  }

  Future<void> _pickCountry() async {
    await _loadCountries();
    if (!mounted) return;
    final picked = await showAppSheet<_GeoCountry>(
      context: context,
      title: 'Country',
      subtitle: 'Where are you based?',
      heightFactor: 0.72,
      builder: (_) => _GeoPickerSheet(countries: _countries),
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
    _clearFieldError('country');
    // Load the city list for the chosen country (lazy, like the site).
    await _loadCities(picked.id);
  }

  Future<void> _pickCity() async {
    final countryId = _countryId;
    if (countryId == null) return;
    if (_cities.isEmpty) await _loadCities(countryId);
    if (!mounted) return;
    final picked = await showAppSheet<_GeoCity>(
      context: context,
      title: 'City',
      subtitle: 'Cities in $_countryName',
      heightFactor: 0.7,
      builder: (_) => _CityPickerSheet(cities: _cities),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _cityId = picked.id;
      _regionId = picked.regionId;
      _cityName = picked.name;
    });
    _clearFieldError('city');
  }

  Widget _agreementLabel(
    String prefix,
    String linkText,
    TapGestureRecognizer recognizer,
  ) {
    final palette = context.enclavd;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 13, height: 1.35, color: palette.textPrimary),
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: linkText,
            style: TextStyle(
              color: palette.link,
              decoration: TextDecoration.underline,
              decorationColor: palette.link,
            ),
            recognizer: recognizer,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Join the Enclavd network',
      leading: AppIconButton(
        key: const Key('register-back'),
        icon: FontAwesomeIcons.chevronLeft,
        tooltip: 'Back to sign in',
        onPressed: () =>
            Navigator.of(context).pushReplacementNamed(LoginScreen.routeName),
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                AuthNotice(message: _error!),
                const SizedBox(height: 16),
              ],
              AppInputField(
                key: const Key('register-username'),
                controller: _username,
                focusNode: _usernameFocus,
                label: 'Username',
                hintText: 'Choose a username',
                prefixIcon: FontAwesomeIcons.user,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                errorText: _fieldErrors['username'],
                onChanged: (_) => _clearFieldError('username'),
                onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Username is required';
                  if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(s)) {
                    return '3-20 characters, letters, numbers, underscores only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AppInputField(
                key: const Key('register-email'),
                controller: _email,
                focusNode: _emailFocus,
                label: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: FontAwesomeIcons.envelope,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                errorText: _fieldErrors['email'],
                onChanged: (_) => _clearFieldError('email'),
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Email is required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AppInputField(
                key: const Key('register-password'),
                controller: _password,
                focusNode: _passwordFocus,
                label: 'Password',
                helperText: 'At least 6 characters',
                prefixIcon: FontAwesomeIcons.lock,
                obscureText: true,
                showObscureToggle: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                errorText: _fieldErrors['password'],
                onChanged: (_) => _clearFieldError('password'),
                onFieldSubmitted: (_) => _passwordConfirmFocus.requestFocus(),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AppInputField(
                key: const Key('register-password-confirm'),
                controller: _passwordConfirm,
                focusNode: _passwordConfirmFocus,
                label: 'Confirm password',
                prefixIcon: FontAwesomeIcons.lock,
                obscureText: true,
                showObscureToggle: true,
                textInputAction: _invitationRequired
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                errorText: _fieldErrors['password_confirm'],
                onChanged: (_) => _clearFieldError('password_confirm'),
                onFieldSubmitted: (_) {
                  if (_invitationRequired) {
                    _invitationFocus.requestFocus();
                  } else {
                    _submit();
                  }
                },
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
              if (_invitationRequired) ...[
                const SizedBox(height: 14),
                AppInputField(
                  key: const Key('register-invitation'),
                  controller: _invitation,
                  focusNode: _invitationFocus,
                  label: 'Invitation code',
                  hintText: 'Enter your invitation code',
                  prefixIcon: FontAwesomeIcons.ticket,
                  textInputAction: TextInputAction.next,
                  errorText: _fieldErrors['invitation'],
                  onChanged: (_) => _clearFieldError('invitation'),
                  onFieldSubmitted: (_) => _captchaFocus.requestFocus(),
                  validator: (_) => _invitation.text.trim().isEmpty
                      ? 'An invitation code is required to join'
                      : null,
                ),
              ],
              const SizedBox(height: 16),
              AppPickerField(
                key: const Key('register-dob'),
                label: 'Date of birth',
                value: _birthdateDisplay,
                hintText: 'Select your date of birth',
                prefixIcon: FontAwesomeIcons.cakeCandles,
                onTap: _pickBirthdate,
              ),
              const SizedBox(height: 14),
              AppPickerField(
                key: const Key('register-gender'),
                label: 'Gender',
                value: _genderDisplay,
                prefixIcon: FontAwesomeIcons.venusMars,
                onTap: _pickGender,
              ),
              const SizedBox(height: 14),
              AppPickerField(
                key: const Key('register-country'),
                label: 'Country',
                value: _countryName,
                hintText: 'Select your country',
                prefixIcon: FontAwesomeIcons.globe,
                onTap: _pickCountry,
              ),
              if (_countryId != null) ...[
                const SizedBox(height: 14),
                AppPickerField(
                  key: const Key('register-city'),
                  label: 'City',
                  value: _cityName,
                  hintText: 'Select your city',
                  prefixIcon: FontAwesomeIcons.city,
                  onTap: _pickCity,
                ),
              ],
              const SizedBox(height: 16),
              const AppDivider(),
              const SizedBox(height: 10),
              AppCheckbox(
                key: const Key('register-privacy'),
                value: _acceptPrivacy,
                semanticLabel: 'I accept the Privacy Policy',
                labelWidget: _agreementLabel(
                  'I accept the ',
                  'Privacy Policy',
                  _privacyTap,
                ),
                onChanged: (v) => setState(() {
                  _acceptPrivacy = v;
                  _checkboxError = null;
                }),
              ),
              const SizedBox(height: 2),
              AppCheckbox(
                key: const Key('register-terms'),
                value: _acceptTerms,
                semanticLabel: 'I accept the Terms of Service',
                labelWidget: _agreementLabel(
                  'I accept the ',
                  'Terms of Service',
                  _termsTap,
                ),
                onChanged: (v) => setState(() {
                  _acceptTerms = v;
                  _checkboxError = null;
                }),
              ),
              if (_checkboxError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    _checkboxError!,
                    style: TextStyle(
                      color: palette.error,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (_rl?.captchaRequired ?? false) ...[
                AppSurface(
                  padding: const EdgeInsets.all(12),
                  color: palette.warning.withValues(alpha: 0.07),
                  borderColor: palette.warning.withValues(alpha: 0.28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FaIcon(FontAwesomeIcons.shieldHalved,
                              size: 13, color: palette.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _rl?.captchaQuestion ?? 'Security question',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: palette.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppInputField(
                        key: const Key('register-captcha'),
                        controller: _captcha,
                        focusNode: _captchaFocus,
                        label: 'Answer',
                        prefixIcon: FontAwesomeIcons.key,
                        textInputAction: TextInputAction.done,
                        errorText: _fieldErrors['captcha'],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (_) =>
                            (_rl?.captchaRequired ?? false) &&
                                    _captcha.text.trim().isEmpty
                                ? 'Answer the question above'
                                : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              AppButton(
                key: const Key('register-submit'),
                label: 'Register',
                icon: FontAwesomeIcons.userPlus,
                expand: true,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 16),
              const AppDivider(),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  AppLinkButton(
                    key: const Key('register-signin'),
                    label: 'Sign in',
                    fontSize: 12.5,
                    onPressed: () => Navigator.of(context)
                        .pushReplacementNamed(LoginScreen.routeName),
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
    final palette = context.enclavd;
    final filtered = widget.countries
        .where((c) =>
            _query.isEmpty ||
            c.name.toLowerCase().contains(_query.toLowerCase()) ||
            c.code.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Column(
      children: [
        TextField(
          autofocus: true,
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search country',
            hintStyle: TextStyle(color: palette.textSecondary),
            prefixIcon: FieldIcon(FontAwesomeIcons.magnifyingGlass,
                size: 14, color: palette.textSecondary),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('No matches found',
                      style: TextStyle(color: palette.textSecondary)))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name, style: const TextStyle(fontSize: 14)),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

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
    final palette = context.enclavd;
    final filtered = widget.cities
        .where((c) =>
            _query.isEmpty || c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Column(
      children: [
        TextField(
          autofocus: true,
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search city',
            hintStyle: TextStyle(color: palette.textSecondary),
            prefixIcon: FieldIcon(FontAwesomeIcons.magnifyingGlass,
                size: 14, color: palette.textSecondary),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('No matches found',
                      style: TextStyle(color: palette.textSecondary)))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name, style: const TextStyle(fontSize: 14)),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
