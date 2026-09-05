import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/personality_service.dart';
import '../api/site_config_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/analytics_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import '../widgets/personality_chip.dart';
import '../widgets/personality_widgets.dart';
import '../widgets/rank_badge.dart';

/* ===view personality screen===
Pushed from a member profile. Opens with a between us card (both
identities with the synergy score and the strengths/challenges reasons),
then the member's type results exactly like the results screen (badge
pill, type card, trait percentages). The score + bar follow the
site config -> synergy_bar feature flag so the site can switch them off
without an app update.
*/
class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({
    super.key,
    required this.userId,
    this.service,
    this.config,
  });

  final int userId;

  final PersonalityService? service;

  /// Config seam for tests
  final SiteConfigService? config;

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  AppServices? _services;

  bool _loading = true;
  String? _error;
  bool _noType = false;
  bool _showBar = true;
  MemberPersonality? _personality;

  PersonalityService get _personalityService =>
      widget.service ?? _services!.personality;

  SiteConfigService? get _configService => widget.config ?? _services?.siteConfig;

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
      final personalityFuture =
          _personalityService.fetchPersonality(widget.userId);
      // Site config runs in parallel. it decides the synergy bar flag.
      // A config failure keeps the bar on so it never hides on a blip.
      final configFuture = _configService == null
          ? Future<SiteConfig?>.value(null)
          : _configService!
              .fetch()
              .then<SiteConfig?>((c) => c)
              .catchError((Object _) => null);
      final p = await personalityFuture;
      final cfg = await configFuture;
      var showBar = true;
      if (cfg != null) {
        var isAdmin = false;
        if (cfg.feature('synergy_bar') == 'debug' && _services != null) {
          try {
            isAdmin = (await _services!.auth.me())?.isAdmin ?? false;
          } catch (_) {
            isAdmin = false;
          }
        }
        showBar = cfg.featureEnabled('synergy_bar', isAdmin: isAdmin);
      }
      if (!mounted) return;
      setState(() {
        _personality = p;
        _showBar = showBar;
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
      personality: _personality!,
      showBar: _showBar,
    );
  }
}

class _PersonalityView extends StatelessWidget {
  const _PersonalityView({
    required this.personality,
    required this.showBar,
  });

  final MemberPersonality personality;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final traits = personality.traits;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (personality.compatibility != null) ...[
          _SynergyCard(
            compat: personality.compatibility!,
            profile: personality.profile,
            viewer: personality.viewer,
            showBar: showBar,
          ),
          const SizedBox(height: 20),
        ],
        // Personality type badge
        Center(
            child:
                PersonalityTypeBadge(type: personality.personalityType)),
        const SizedBox(height: 20),
        // Type card: title + description + strengths areas
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

/*
 * The between-us hero: both members as real identities (avatar, rank,
   username, type chip) with the synergy score + bar between them, then
   the strengths/challenges reasons. Falls back to score-only when an old
   server sends no identities.
   */
class _SynergyCard extends StatelessWidget {
  const _SynergyCard({
    required this.compat,
    required this.profile,
    required this.viewer,
    required this.showBar,
  });

  final PersonalityCompatibility compat;
  final PersonalityIdentity? profile;
  final PersonalityIdentity? viewer;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final myColor = PersonalityColors.forType(compat.myType) ??
        EnclavdColors.textSecondary;
    final theirColor = PersonalityColors.forType(compat.theirType) ??
        EnclavdColors.textSecondary;
    final percentage = showBar ? compat.percentage : null;
    final showColumns = viewer != null && profile != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnclavdColors.border),
        // Each half tinted by its member's type color, meeting mid-card.
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _tint(myColor),
            EnclavdColors.card,
            _tint(theirColor),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: showColumns
                ? [
                    Expanded(
                        child: _IdentityColumn(
                            person: viewer!, type: compat.myType)),
                    if (percentage != null)
                      _PercentColumn(percentage: percentage)
                    else
                      const SizedBox(width: 8),
                    Expanded(
                        child: _IdentityColumn(
                            person: profile!, type: compat.theirType)),
                  ]
                : [
                    Expanded(
                      child: percentage != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: _PercentColumn(percentage: percentage),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
          ),
          if (percentage != null) ...[
            const SizedBox(height: 14),
            _SynergyBar(percentage: percentage),
          ],
          const SizedBox(height: 16),
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

  // Type color blended over the card so the gradient stays readable.
  static Color _tint(Color c) =>
      Color.alphaBlend(c.withValues(alpha: 0.16), EnclavdColors.card);
}

/*
 * One participant: avatar with the type ring, rank-colored username,
   then the rank badge + type chip (wrapped so long ranks never clip).
   */
class _IdentityColumn extends StatelessWidget {
  const _IdentityColumn({required this.person, required this.type});

  final PersonalityIdentity person;
  final String type;

  @override
  Widget build(BuildContext context) {
    final typeColor = PersonalityColors.forType(type);
    final blocked = person.rank == 'Blocked';
    final rankColor = RankColors.forRank(person.rank);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EnclavdAvatar(
          size: 56,
          url: resolveMediaUrl(AppConfig.apiBaseUrl,
              avatarPath: person.profilePictureUrl),
          borderColor: typeColor ?? EnclavdColors.border,
        ),
        const SizedBox(height: 8),
        Text(
          person.username,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: rankColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            decoration: blocked ? TextDecoration.lineThrough : null,
            decorationColor: rankColor,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            RankBadge(rank: person.rank),
            if (type.isNotEmpty) PersonalityChip(type: type),
          ],
        ),
      ],
    );
  }
}

/* The big score between the two avatars. */
class _PercentColumn extends StatelessWidget {
  const _PercentColumn({required this.percentage});

  final int percentage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$percentage%',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _bandColor(percentage),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Synergy',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: EnclavdColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/* Full-width track with the score fill (site color bands). */
class _SynergyBar extends StatelessWidget {
  const _SynergyBar({required this.percentage});

  final int percentage;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF374151)), // gray-700 track
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (percentage / 100).clamp(0.0, 1.0),
              child: ColoredBox(color: _bandColor(percentage)),
            ),
          ],
        ),
      ),
    );
  }
}

// Site bands: >=70 green, >=40 yellow, else red (profile.php).
Color _bandColor(int percentage) {
  if (percentage >= 70) return const Color(0xFF22C55E); // green-500
  if (percentage >= 40) return const Color(0xFFEAB308); // yellow-500
  return const Color(0xFFEF4444); // red-500
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
