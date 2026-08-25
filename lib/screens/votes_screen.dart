import 'dart:math' as math;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/messages_service.dart'; // formatMessageTime (DB UTC → local)
import '../api/votes_service.dart';
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../utils/domain_icons.dart'; // domainColorFromHex (site hex → Color)
import '../utils/user_facing_errors.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import '../widgets/rank_badge.dart';
import '../widgets/shimmer.dart';
import 'profile_screen.dart';

/// The native Votes tab — the site's /vote (vote.php) as a modern app:
/// active community polls (vote / change vote in place) then the completed
/// ones, read-only with final results. Site parity:
///  - counts are WEIGHTED (rank voting power), the site's card math;
///  - one vote per poll, changeable until the period ends;
///  - "Your current vote" highlight on the chosen option, purple accent;
///  - doughnut chart per poll (the site's Chart.js canvas, native painter),
///    "No votes yet" when nobody has voted;
///  - creator row (avatar + username → profile, rank badge);
///  - "How Voting Works" info card with the expandable rank-powers table.
/// Modern-app look: rounded card rows with gaps, shimmer on first load,
/// pull-to-refresh.
///
/// This widget is the FEED SHELL's Votes tab body (no Scaffold/AppBar of
/// its own — the shell supplies the shared header and bottom nav); it is
/// built lazily on first tab visit.
class VotesScreen extends StatefulWidget {
  const VotesScreen({super.key, required this.votes});

  final VotesService votes;

  @override
  State<VotesScreen> createState() => _VotesScreenState();
}

class _VotesScreenState extends State<VotesScreen> {
  VotesData? _data;
  bool _loading = true;
  String? _error;

  /// Pending per-poll selection (feature_id → option index) before submit.
  final Map<int, int> _selection = {};
  int? _submittingId;
  bool _ranksOpen = false;

  /// The purple accent shared by every selected/my-vote affordance
  /// (site purple-500).
  static const _accent = Color(0xFFA855F7);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.votes.fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(e,
            fallback: 'Something went wrong loading the votes. '
                'Please try again.');
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _vote(Vote vote) async {
    final option = _selection[vote.id];
    if (option == null) {
      _toast('Please select an option first');
      return;
    }
    setState(() => _submittingId = vote.id);
    try {
      final result = await widget.votes.vote(vote.id, option);
      if (!mounted) return;
      setState(() {
        _applyVote(vote.copyWith(
          counts: result.counts,
          myOption: result.myVote,
        ));
        _selection.remove(vote.id);
        _submittingId = null;
      });
      _toast('Your vote has been recorded');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingId = null);
      _toast(userFacingError(e, fallback: 'Error submitting your vote'));
    }
  }

  /// Replaces the updated poll in whichever section it lives in.
  void _applyVote(Vote updated) {
    final data = _data;
    if (data == null) return;
    final inActive = data.active.indexWhere((v) => v.id == updated.id);
    if (inActive >= 0) {
      final next = [...data.active];
      next[inActive] = updated;
      _data = VotesData(
        active: next,
        completed: data.completed,
        votingPower: data.votingPower,
        isAdmin: data.isAdmin,
        rankPowers: data.rankPowers,
      );
      return;
    }
    final inCompleted = data.completed.indexWhere((v) => v.id == updated.id);
    if (inCompleted >= 0) {
      final next = [...data.completed];
      next[inCompleted] = updated;
      _data = VotesData(
        active: data.active,
        completed: next,
        votingPower: data.votingPower,
        isAdmin: data.isAdmin,
        rankPowers: data.rankPowers,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading && data == null) return _skeleton();
    if (_error != null && data == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: EnclavdColors.link,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _HowVotingWorks(
            votingPower: data!.votingPower,
            rankPowers: data.rankPowers,
            open: _ranksOpen,
            onToggle: () => setState(() => _ranksOpen = !_ranksOpen),
          ),
          const _SectionHeader(
              icon: FontAwesomeIcons.checkToSlot, title: 'Active Votes'),
          if (data.active.isEmpty)
            const _EmptyState(
              icon: FontAwesomeIcons.checkToSlot,
              text: 'No active votes at the moment.',
            )
          else
            for (final vote in data.active) _card(vote),
          const _SectionHeader(
              icon: FontAwesomeIcons.chartPie, title: 'Completed Votes'),
          if (data.completed.isEmpty)
            const _EmptyState(
              icon: FontAwesomeIcons.chartPie,
              text: 'No completed votes yet.',
            )
          else
            for (final vote in data.completed) _card(vote),
        ],
      ),
    );
  }

  Widget _card(Vote vote) => _VoteCard(
        vote: vote,
        selected: _selection[vote.id],
        submitting: _submittingId == vote.id,
        onSelect: vote.completed
            ? null
            : (option) => setState(() => _selection[vote.id] = option),
        onSubmit: () => _vote(vote),
        onCreatorTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(userId: vote.creatorId),
        )),
      );

  Widget _skeleton() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const ShimmerBox(width: double.infinity, height: 96),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            const ShimmerBox(width: double.infinity, height: 220),
            const SizedBox(height: 12),
          ],
        ],
      );
}

/// "How Voting Works" info card (vote.php section) with the expandable
/// rank-voting-power table.
class _HowVotingWorks extends StatelessWidget {
  const _HowVotingWorks({
    required this.votingPower,
    required this.rankPowers,
    required this.open,
    required this.onToggle,
  });

  final int votingPower;
  final List<RankPower> rankPowers;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              FaIcon(FontAwesomeIcons.circleInfo,
                  size: 14, color: EnclavdColors.warning),
              SizedBox(width: 8),
              Text(
                'How Voting Works',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Vote on upcoming features. One vote per feature, changeable '
            'until the voting period ends.',
            style: TextStyle(
                fontSize: 12.5,
                color: EnclavdColors.textSecondary,
                height: 1.45),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Your vote counts ',
                  style: TextStyle(
                      fontSize: 12.5, color: EnclavdColors.textSecondary),
                ),
                TextSpan(
                  text: '×$votingPower',
                  style:
                      const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    'View Rank Voting Powers',
                    style: TextStyle(
                        fontSize: 12.5, color: EnclavdColors.link),
                  ),
                  Spacer(),
                  FaIcon(FontAwesomeIcons.chevronDown,
                      size: 12,
                      color: EnclavdColors.textSecondary,
                      // ignore: deprecated_member_use
                      semanticLabel: 'toggle'),
                ],
              ),
            ),
          ),
          if (open) ...[
            const SizedBox(height: 4),
            for (final power in rankPowers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Text(
                      power.name,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: RankColors.forRank(power.rank)),
                    ),
                    const Spacer(),
                    Text(
                      '×${power.votingPower}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final FaIconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          FaIcon(icon, size: 15, color: EnclavdColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final FaIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          FaIcon(icon, size: 30, color: EnclavdColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One poll card. Active: radio-style options + Submit/Change Vote.
/// Completed: read-only options with final percentages.
class _VoteCard extends StatelessWidget {
  const _VoteCard({
    required this.vote,
    required this.selected,
    required this.submitting,
    required this.onSelect,
    required this.onSubmit,
    required this.onCreatorTap,
  });

  final Vote vote;
  final int? selected;
  final bool submitting;
  final ValueChanged<int>? onSelect;
  final VoidCallback onSubmit;
  final VoidCallback onCreatorTap;

  @override
  Widget build(BuildContext context) {
    final myVote = vote.myOption;
    const accent = _VotesScreenState._accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vote.title,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              _EndsPill(vote: vote),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            vote.description,
            style: const TextStyle(
                fontSize: 12.5,
                color: EnclavdColors.textSecondary,
                height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < vote.options.length; i++)
                      _optionRow(i, myVote, accent),
                    if (!vote.completed) ...[
                      const SizedBox(height: 10),
                      _voteButton(myVote, accent),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _Donut(vote: vote),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Created by',
                  style: TextStyle(
                      fontSize: 11.5, color: EnclavdColors.textSecondary)),
              const SizedBox(width: 6),
              InkWell(
                onTap: onCreatorTap,
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    EnclavdAvatar(
                      size: 20,
                      url: vote.creatorAvatar.startsWith('/')
                          ? '${AppConfig.apiBaseUrl}${vote.creatorAvatar}'
                          : vote.creatorAvatar,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      vote.creatorUsername,
                      style: const TextStyle(
                          fontSize: 12.5, color: EnclavdColors.link),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RankBadge(rank: vote.creatorRank),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionRow(int i, int? myVote, Color accent) {
    final isSelected = selected == i; // pending selection
    final isMine = myVote == i; // current vote
    final highlighted = isSelected || isMine;
    final tappable = onSelect != null && !submitting;
    return InkWell(
      key: ValueKey('vote-${vote.id}-option-$i'),
      onTap: tappable ? () => onSelect!(i) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: highlighted ? accent.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(10),
          border: highlighted
              ? Border.all(color: accent.withValues(alpha: 0.30))
              : null,
        ),
        child: Row(
          children: [
            // Radio-style indicator (site's form-radio, purple accent).
            Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 2,
                  color: highlighted
                      ? accent
                      : EnclavdColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
              child: highlighted
                  ? Center(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vote.options[i],
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  if (isMine) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.circleCheck,
                            size: 11, color: _VotesScreenState._accent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _myVoteLabel(),
                            style: const TextStyle(
                                fontSize: 11,
                                color: _VotesScreenState._accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${vote.pct(i).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${vote.counts[i]} votes',
                  style: const TextStyle(
                      fontSize: 10.5, color: EnclavdColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 'Your current vote' + the last-change time when the server had one
  /// (the web card's purple line; fresh votes show no time until reload).
  String _myVoteLabel() {
    final changed = vote.myVoteChangedAt;
    final time = formatMessageTime(changed ?? '');
    return time.isEmpty ? 'Your current vote' : 'Your current vote - $time';
  }

  Widget _voteButton(int? myVote, Color accent) {
    return FilledButton.icon(
      onPressed: submitting ? null : onSubmit,
      style: FilledButton.styleFrom(
        backgroundColor: EnclavdColors.primaryButton,
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      icon: submitting
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : FaIcon(
              myVote != null ? FontAwesomeIcons.rotate : FontAwesomeIcons.circleCheck,
              size: 13,
              color: accent,
            ),
      label: Text(submitting
          ? 'Submitting…'
          : (myVote != null ? 'Change Vote' : 'Submit Vote')),
    );
  }
}

/// Ends/status pill (the card's clock chip): active polls show the end
/// time, completed ones the status ('Completed' green / 'Cancelled' red).
class _EndsPill extends StatelessWidget {
  const _EndsPill({required this.vote});

  final Vote vote;

  @override
  Widget build(BuildContext context) {
    if (vote.completed) {
      final isCompleted = vote.status == 'completed';
      final color =
          isCompleted ? const Color(0xFF22C55E) : const Color(0xFFF87171);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          vote.status.isEmpty
              ? 'Ended'
              : vote.status[0].toUpperCase() + vote.status.substring(1),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.clock,
              size: 10, color: EnclavdColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            'Ends: ${formatMessageTime(vote.endDate)}',
            style: const TextStyle(
                fontSize: 10.5, color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Native doughnut — the site's Chart.js canvas for one poll. Weighted
/// counts per option, option colors, small gaps between segments (the
/// site's spacing:3); the center shows the total vote count.
class _Donut extends StatelessWidget {
  const _Donut({required this.vote});

  final Vote vote;

  @override
  Widget build(BuildContext context) {
    if (vote.totalVotes <= 0) {
      return const SizedBox(
        width: 76,
        height: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(FontAwesomeIcons.chartPie,
                size: 24, color: EnclavdColors.textSecondary),
            SizedBox(height: 6),
            Text('No votes yet',
                style: TextStyle(
                    fontSize: 9.5, color: EnclavdColors.textSecondary)),
          ],
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: CustomPaint(
            painter: _DonutPainter(vote.counts, vote.colors),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${vote.totalVotes}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const Text('votes',
                      style: TextStyle(
                          fontSize: 9.5,
                          color: EnclavdColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.counts, this.colors);

  final List<int> counts;
  final List<String> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return;
    const stroke = 11.0;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(
        center: center, radius: (size.shortestSide - stroke) / 2);
    // Small segment gap (the site's spacing: 3).
    const gap = 0.035;
    var start = -math.pi / 2;
    for (var i = 0; i < counts.length; i++) {
      final sweep = (counts[i] / total) * 2 * math.pi;
      if (counts[i] > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = domainColorFromHex(colors[i]);
        canvas.drawArc(rect, start + gap, sweep - gap * 2, false, paint);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.counts != counts || oldDelegate.colors != colors;
}
