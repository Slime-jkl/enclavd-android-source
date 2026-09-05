import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/api_client.dart';
import '../api/personality_service.dart';
import '../main.dart';
import '../services/analytics_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/personality_chip.dart';
import '../widgets/personality_widgets.dart';

/* ===view personality screen===
Pushed from a member profile.
Shows the member's type results exactly like the results screen
(badge pill, type card, trait percentages), plus the between-us strengths / challenges reasons
*/
class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({
    super.key,
    required this.userId,
    required this.username,
    this.service,
  });

  final int userId;
  final String username;

  final PersonalityService? service;

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  AppServices? _services;

  bool _loading = true;
  String? _error;
  bool _noType = false;
  MemberPersonality? _personality;

  PersonalityService get _personalityService =>
      widget.service ?? _services!.personality;

  @override
  void initState() {
    super.initState();
    trackScreen('/personality');
    _load();
  }

  Future<void> _load() async {
    if (widget.service == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _noType = false;
    });
    try {
      final p = await _personalityService.fetchPersonality(widget.userId);
      if (!mounted) return;
      setState(() {
        _personality = p;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 404) {
          _noType = true;
        } else {
          _error = e.message;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load personality.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personality')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_noType) return const _NoTypeView();
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    return _PersonalityView(
      username: widget.username,
      personality: _personality!,
    );
  }
}

class _PersonalityView extends StatelessWidget {
  const _PersonalityView({required this.username, required this.personality});

  final String username;
  final MemberPersonality personality;

  @override
  Widget build(BuildContext context) {
    final traits = personality.traits;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (personality.compatibility != null) ...[
          _SynergyCard(compat: personality.compatibility!, username: username),
          const SizedBox(height: 20),
        ],
        // Personality type badge.
        Center(
            child:
                PersonalityTypeBadge(type: personality.personalityType)),
        const SizedBox(height: 20),
        // Type card: title + description + strengths areas.
        PersonalityInfoCard(
          title: personality.info.title,
          description: personality.info.description,
          strengths: personality.info.strengths,
          weaknesses: personality.info.weaknesses,
        ),
        if (traits != null) ...[
          const SizedBox(height: 14),
          TraitBar(
            label: 'Introversion - Extraversion',
            first: 'Introversion',
            firstPercent: traits.iePercentage,
            firstColor: const Color(0xFF3B82F6), // blue-500
            second: 'Extraversion',
            secondColor: const Color(0xFFEF4444), // red-500
          ),
          const SizedBox(height: 10),
          TraitBar(
            label: 'Sensing - Intuition',
            first: 'Sensing',
            firstPercent: traits.snPercentage,
            firstColor: const Color(0xFF22C55E), // green-500
            second: 'Intuition',
            secondColor: const Color(0xFFA855F7), // purple-500
          ),
          const SizedBox(height: 10),
          TraitBar(
            label: 'Thinking - Feeling',
            first: 'Thinking',
            firstPercent: traits.tfPercentage,
            firstColor: const Color(0xFFEAB308), // yellow-500
            second: 'Feeling',
            secondColor: const Color(0xFFEC4899), // pink-500
          ),
          const SizedBox(height: 10),
          TraitBar(
            label: 'Judging - Perceiving',
            first: 'Judging',
            firstPercent: traits.jpPercentage,
            firstColor: const Color(0xFFF97316), // orange-500
            second: 'Perceiving',
            secondColor: const Color(0xFF6366F1), // indigo-500
          ),
        ],
      ],
    );
  }
}

class _SynergyCard extends StatelessWidget {
  const _SynergyCard({required this.compat, required this.username});

  final PersonalityCompatibility compat;
  final String username;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PersonalityChip(type: compat.myType),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('x',
                    style: TextStyle(color: EnclavdColors.textSecondary)),
              ),
              PersonalityChip(type: compat.theirType),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You and $username',
            style: const TextStyle(
                color: EnclavdColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _ReasonBlock(
            background: const Color(0xFF14532D), // green-900
            border: const Color(0xFF166534), // green-800
            icon: FontAwesomeIcons.circlePlus,
            iconColor: const Color(0xFF4ADE80), // green-400
            heading: 'Strengths',
            body: compat.proReason,
          ),
          const SizedBox(height: 10),
          _ReasonBlock(
            background: const Color(0xFF7F1D1D), // red-900
            border: const Color(0xFF991B1B), // red-800
            icon: FontAwesomeIcons.circleExclamation,
            iconColor: const Color(0xFFF87171), // red-400
            heading: 'Challenges',
            body: compat.consReason,
          ),
        ],
      ),
    );
  }
}

class _ReasonBlock extends StatelessWidget {
  const _ReasonBlock({
    required this.background,
    required this.border,
    required this.icon,
    required this.iconColor,
    required this.heading,
    required this.body,
  });

  final Color background;
  final Color border;
  final FaIconData icon;
  final Color iconColor;
  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 13, color: iconColor),
              const SizedBox(width: 8),
              Text(heading,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }
}

class _NoTypeView extends StatelessWidget {
  const _NoTypeView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.brain,
                size: 40, color: EnclavdColors.textSecondary),
            SizedBox(height: 14),
            Text('No personality type yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text(
              'This member has not taken the personality test.',
              textAlign: TextAlign.center,
              style: TextStyle(color: EnclavdColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
