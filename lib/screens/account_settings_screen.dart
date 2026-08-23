import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/profile_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../utils/user_facing_errors.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/field_icon.dart';

/// The native Account settings screen — a modern port of the site's
/// profile-edit.php GENERAL INFO tab (the Connected Devices tab is
/// intentionally not included): avatar, email (read-only), full name,
/// bio, date of birth, gender, country/city and the password change.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen(
      {super.key, this.profile, this.api, this.avatarPicker});

  /// Injected for tests (real screen resolves AppServices.current).
  final ProfileService? profile;

  /// Used for the public geo lookups (countries/cities); defaults to the
  /// current container's client.
  final ApiClient? api;

  /// Test seam: how an avatar file is picked. Defaults to the system
  /// gallery via image_picker.
  final Future<XFile?> Function()? avatarPicker;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _GeoCountry {
  const _GeoCountry({required this.id, required this.name, this.code = ''});

  final int id;
  final String name;
  final String code;
}

class _GeoCity {
  const _GeoCity({required this.id, required this.name});

  final int id;
  final String name;
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  AppServices? _services;

  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  final _scroll = ScrollController();

  AccountSettings? _account;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _gender = 'NONE';
  String? _birthdate; // 'Y-m-d'
  int? _countryId;
  int? _regionId;
  int? _cityId;
  String _countryName = '';
  String _cityName = '';

  Uint8List? _pendingAvatar; // picked but not yet uploaded
  String _avatarDataUrl = ''; // the upload payload (data URL)

  List<_GeoCountry> _countries = const [];
  List<_GeoCity> _cities = const [];

  ProfileService get _profile => widget.profile ?? _services!.profile;
  ApiClient get _api => widget.api ?? _services!.apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.profile == null || widget.api == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await _profile.fetchSelf();
      if (!mounted) return;
      _emailController.text = account.email;
      _fullNameController.text = account.fullName;
      _bioController.text = account.bio;
      _gender = account.gender.isEmpty ? 'NONE' : account.gender;
      _birthdate = account.birthdate;
      _countryId = account.geoCountry;
      _regionId = account.geoRegion;
      _cityId = account.geoCity;
      setState(() {
        _account = account;
        _loading = false;
      });
      // Best-effort geo name resolution (the site resolves names
      // client-side too). Failures just leave the ids.
      _resolveGeoNames(account);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(e, fallback: 'Failed to load account settings.');
        _loading = false;
      });
    }
  }

  Future<void> _resolveGeoNames(AccountSettings account) async {
    try {
      final json = await _api.getJson('/handlers/geo/get_countries.php');
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
        if (!mounted) return;
        setState(() => _countries = countries);
        final country = account.geoCountry;
        if (country != null) {
          final match =
              countries.where((c) => c.id == country).toList();
          if (match.isNotEmpty && mounted) {
            setState(() => _countryName = match.first.name);
          }
          if (account.geoCity != null) {
            await _loadCities(country, keepCity: account.geoCity);
          }
        }
      }
    } catch (_) {
      // Names are cosmetic — ids still save fine.
    }
  }

  Future<void> _loadCities(int countryId, {int? keepCity}) async {
    try {
      final json = await _api.getJson(
          '/handlers/geo/get_cities.php', query: {'country_id': '$countryId'});
      final data = json['data'];
      if (data is! List) return;
      final cities = data
          .whereType<Map<String, dynamic>>()
          .map((m) => _GeoCity(
                id: (m['id'] as num?)?.toInt() ?? 0,
                name: m['name'] as String? ?? '',
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _cities = cities;
        if (keepCity != null) {
          final match = cities.where((c) => c.id == keepCity).toList();
          if (match.isNotEmpty) _cityName = match.first.name;
        }
      });
    } catch (_) {
      // Cosmetic — the ids still save fine.
    }
  }

  /// Picks + compresses an avatar (the site accepts ≤800px; the picker
  /// compresses to the same ballpark the site's GD resize produces).
  Future<void> _pickAvatar() async {
    try {
      final file = await (widget.avatarPicker ??
          () => ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 800,
                maxHeight: 800,
                imageQuality: 85,
              ))();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingAvatar = bytes;
        _avatarDataUrl =
            'data:image/jpeg;base64,${base64Encode(bytes)}';
      });
    } catch (_) {
      // A picker failure (permission denied, unreadable file) must not be
      // silent — the user tapped Change and nothing visibly happened.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Could not open your photos. Please check the app\'s photo '
            'permission and try again.'),
        duration: Duration(seconds: 3),
      ));
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

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<_GeoCountry>(
      context: context,
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _GeoPickerSheet(
        title: 'Country',
        countries: _countries,
      ),
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
      _cityName = picked.name;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    // Fields first (the site's single submit), then the avatar if one was
    // picked. Each step is reported separately so the user knows exactly
    // what failed — a picture failure must not read as "your whole profile
    // didn't save" (the fields above it did save).
    try {
      await _profile.updateProfile(
        fullName: _fullNameController.text.trim(),
        bio: _bioController.text.trim(),
        birthdate: _birthdate,
        gender: _gender,
        geoCountry: _countryId,
        geoRegion: _regionId,
        geoCity: _cityId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userFacingError(
            e, fallback: 'Could not save your changes. Please try again.');
      });
      _revealError();
      return;
    }
    if (_avatarDataUrl.isNotEmpty) {
      try {
        await _profile.uploadAvatar(_avatarDataUrl);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = userFacingError(
              e,
              fallback:
                  'Your new profile picture could not be saved. Please try again.');
        });
        _revealError();
        return; // keep the picked preview so the user can retry
      }
    }
    if (!mounted) return;
    setState(() {
      _pendingAvatar = null;
      _avatarDataUrl = '';
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Profile updated successfully!'),
      duration: Duration(seconds: 3),
    ));
    await _load(); // refresh the prefilled values
  }

  /// The error banner sits at the top of the list but Save lives at the
  /// bottom — scroll the banner into view so a failure is never invisible.
  void _revealError() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    var showCurrent = false;
    var showNext = false;
    var showConfirm = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: EnclavdColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: EnclavdColors.border),
          ),
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: EnclavdColors.likeActive.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(error!,
                        style: const TextStyle(
                            fontSize: 12.5, color: EnclavdColors.likeActive)),
                  ),
                  const SizedBox(height: 10),
                ],
                _PasswordField(
                  controller: current,
                  label: 'Current Password',
                  obscure: !showCurrent,
                  onToggle: () =>
                      setDialogState(() => showCurrent = !showCurrent),
                ),
                const SizedBox(height: 10),
                _PasswordField(
                  controller: next,
                  label: 'New Password',
                  obscure: !showNext,
                  onToggle: () => setDialogState(() => showNext = !showNext),
                ),
                const SizedBox(height: 10),
                _PasswordField(
                  controller: confirm,
                  label: 'Confirm New Password',
                  obscure: !showConfirm,
                  onToggle: () =>
                      setDialogState(() => showConfirm = !showConfirm),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: EnclavdColors.primaryButton),
              onPressed: () async {
                final currentText = current.text;
                final nextText = next.text;
                final confirmText = confirm.text;
                if (currentText.isEmpty ||
                    nextText.isEmpty ||
                    confirmText.isEmpty) {
                  setDialogState(() =>
                      error = 'All password fields are required');
                  return;
                }
                try {
                  await _profile.changePassword(
                    currentPassword: currentText,
                    newPassword: nextText,
                    confirmPassword: confirmText,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (e) {
                  setDialogState(() => error =
                      userFacingError(e, fallback: 'Failed to change the password.'));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password changed successfully!'),
        duration: Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account settings')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null && _account == null) {
return ErrorView(message: _error!, onRetry: _load);
    }
    final account = _account!;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          _ErrorBanner(text: _error!),
          const SizedBox(height: 12),
        ],
        // ── Profile picture (the site's avatar row) ──
        Row(
          children: [
            if (_pendingAvatar != null)
              ClipOval(
                child: Image.memory(
                  _pendingAvatar!,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                ),
              )
            else
              EnclavdAvatar(
                size: 84,
                url: account.profilePictureUrl.startsWith('/')
                    ? '${AppConfig.apiBaseUrl}${account.profilePictureUrl}'
                    : account.profilePictureUrl,
                borderColor: EnclavdColors.border,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Profile Picture',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                    'JPEG, PNG, GIF or WebP. Images are resized to '
                    '800x800.',
                    style: TextStyle(
                        fontSize: 12, color: EnclavdColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickAvatar,
                    icon: const FaIcon(FontAwesomeIcons.image,
                        size: 13, color: EnclavdColors.link),
                    label: Text(_pendingAvatar != null
                        ? 'Replace'
                        : 'Change'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EnclavdColors.link,
                      side: const BorderSide(color: EnclavdColors.border),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // ── Email (read-only, cannot be changed here) ──
        _Field(
          label: 'Email',
          child: TextField(
            controller: _emailController,
            enabled: false,
            style: const TextStyle(color: EnclavdColors.textSecondary),
            decoration: _inputDecoration(),
          ),
        ),
        const SizedBox(height: 14),
        // ── Full name ──
        _Field(
          label: 'Full Name',
          child: TextField(
            controller: _fullNameController,
            style: const TextStyle(color: EnclavdColors.textPrimary),
            decoration: _inputDecoration(),
          ),
        ),
        const SizedBox(height: 14),
        // ── Bio ──
        _Field(
          label: 'Bio',
          child: TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 1000,
            style: const TextStyle(color: EnclavdColors.textPrimary),
            decoration: _inputDecoration(),
          ),
        ),
        const SizedBox(height: 6),
        // ── Date of birth ──
        _Field(
          label: 'Date of Birth',
          child: InkWell(
            onTap: _pickBirthdate,
            child: InputDecorator(
              decoration: _inputDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _birthdate ?? 'Select your date of birth',
                      style: TextStyle(
                        color: _birthdate == null
                            ? EnclavdColors.textSecondary
                            : EnclavdColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_birthdate != null)
                    InkWell(
                      onTap: () => setState(() => _birthdate = null),
                      child: const FaIcon(FontAwesomeIcons.xmark,
                          size: 14, color: EnclavdColors.textSecondary),
                    )
                  else
                    const FaIcon(FontAwesomeIcons.calendar,
                        size: 14, color: EnclavdColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // ── Gender ──
        _Field(
          label: 'Gender',
          child: DropdownButtonFormField<String>(
            initialValue: _gender,
            dropdownColor: EnclavdColors.cardSecondary,
            style: const TextStyle(color: EnclavdColors.textPrimary),
            decoration: _inputDecoration(),
            items: const [
              DropdownMenuItem(value: 'NONE', child: Text('Prefer not to say')),
              DropdownMenuItem(value: 'MALE', child: Text('Male')),
              DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _gender = v);
            },
          ),
        ),
        const SizedBox(height: 14),
        // ── Location: country / city (the site's search dropdowns) ──
        _Field(
          label: 'Country',
          child: InkWell(
            onTap: _pickCountry,
            child: InputDecorator(
              decoration: _inputDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _countryName.isEmpty
                          ? (_countryId != null
                              ? 'Country #$_countryId'
                              : 'Select your country')
                          : _countryName,
                      style: TextStyle(
                        color: _countryName.isEmpty
                            ? EnclavdColors.textSecondary
                            : EnclavdColors.textPrimary,
                      ),
                    ),
                  ),
                  const FaIcon(FontAwesomeIcons.chevronDown,
                      size: 12, color: EnclavdColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
        if (_countryId != null) ...[
          const SizedBox(height: 14),
          _Field(
            label: 'City',
            child: InkWell(
              onTap: _pickCity,
              child: InputDecorator(
                decoration: _inputDecoration(),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _cityName.isEmpty
                            ? (_cityId != null
                                ? 'City #$_cityId'
                                : 'Select your city')
                            : _cityName,
                        style: TextStyle(
                          color: _cityName.isEmpty
                              ? EnclavdColors.textSecondary
                              : EnclavdColors.textPrimary,
                        ),
                      ),
                    ),
                    const FaIcon(FontAwesomeIcons.chevronDown,
                        size: 12, color: EnclavdColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        // ── Save ──
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
          label: const Text('Save Changes'),
          style: FilledButton.styleFrom(
            backgroundColor: EnclavdColors.primaryButton,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 24),
        // ── Password (the site's secondary card) ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EnclavdColors.cardSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EnclavdColors.border),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Password',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(
                      'Use the button to securely change your password.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: EnclavdColors.textSecondary),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _changePassword,
                icon: const FaIcon(FontAwesomeIcons.key, size: 13),
                label: const Text('Change Password'),
                style: FilledButton.styleFrom(
                  backgroundColor: EnclavdColors.primaryButton,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration() => InputDecoration(
        filled: true,
        fillColor: EnclavdColors.cardSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: EnclavdColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: EnclavdColors.border),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

/// Label above a form field (the site's `block text-sm font-medium`).
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        child,
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: EnclavdColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: EnclavdColors.cardSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: EnclavdColors.border),
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: FaIcon(obscure ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
              size: 14, color: EnclavdColors.textSecondary),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EnclavdColors.likeActive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: EnclavdColors.likeActive.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.triangleExclamation,
              size: 14, color: EnclavdColors.likeActive),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: EnclavdColors.likeActive)),
          ),
        ],
      ),
    );
  }
}

/// Searchable country picker (the site's country dropdown).
class _GeoPickerSheet extends StatefulWidget {
  const _GeoPickerSheet({required this.title, required this.countries});

  final String title;
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
                style:
                    const TextStyle(color: EnclavdColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search ${widget.title.toLowerCase()}',
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
        .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query.toLowerCase()))
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
