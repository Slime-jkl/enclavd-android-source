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
/// Modern-app look (user rule: native UI, not a website copy): cards stack
/// VERTICALLY — the doughnut sits centered as the poll's summary, options
/// run full-width with their own progress bars, generous paddings, rounded
/// corners, pull-to-refresh, shimmer first load.
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const ShimmerBox(width: double.infinity, height: 110),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            const ShimmerBox(width: double.infinity, height: 280),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              FaIcon(FontAwesomeIcons.circleInfo,
                  size: 14, color: EnclavdColors.warning),
              SizedBox(width: 9),
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
                fontSize: 13, color: EnclavdColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          // Highlight row: the viewer's own weight (the site's "Voting
          // Power: N×" line), modern stat-chip style.
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _VotesScreenState._accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _VotesScreenState._accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.weightHanging,
                    size: 13, color: _VotesScreenState._accent),
                const SizedBox(width: 9),
                const Text(
                  'Your voting power',
                  style: TextStyle(
                      fontSize: 13, color: EnclavdColors.textSecondary),
                ),
                const Spacer(),
                Text(
                  '×$votingPower',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _VotesScreenState._accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Text(
                    'View Rank Voting Powers',
                    style: TextStyle(
                        fontSize: 13, color: EnclavdColors.link),
                  ),
                  const Spacer(),
                  FaIcon(
                    open
                        ? FontAwesomeIcons.chevronUp
                        : FontAwesomeIcons.chevronDown,
                    size: 12,
                    color: EnclavdColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            for (final power in rankPowers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      power.name,
                      style: TextStyle(
                          fontSize: 13, color: RankColors.forRank(power.rank)),
                    ),
                    const Spacer(),
                    Text(
                      '×${power.votingPower}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Row(
        children: [
          // Icon chip — the modern-section-header look.
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: EnclavdColors.primaryButton.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: FaIcon(icon, size: 13, color: EnclavdColors.link),
          ),
          const SizedBox(width: 10),
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
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: EnclavdColors.cardSecondary.withValues(alpha: 0.6),
            ),
            child: FaIcon(icon, size: 22, color: EnclavdColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One poll card — stacked vertically for mobile: title + status, the
/// doughnut as the poll's summary (total votes in the center), the end
/// chip, description, full-width option rows with progress bars, the vote
/// action, then the creator footer.
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title row + status pill (completed only — active polls carry
          // their end chip under the doughnut).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vote.title,
                  style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3),
                ),
              ),
              if (vote.completed) ...[
                const SizedBox(width: 10),
                _StatusPill(vote: vote),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Poll summary: the doughnut (or "No votes yet" placeholder).
          Center(child: _Donut(vote: vote)),
          const SizedBox(height: 10),
          // End/ended chip — the card's clock line.
          Center(child: _EndChip(vote: vote)),
          const SizedBox(height: 14),
          if (vote.description.isNotEmpty) ...[
            Text(
              vote.description,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: EnclavdColors.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < vote.options.length; i++)
            _optionRow(i, myVote),
          if (!vote.completed) ...[
            const SizedBox(height: 14),
            _voteButton(myVote),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: EnclavdColors.divider),
          const SizedBox(height: 12),
          _creatorRow(),
        ],
      ),
    );
  }

  Widget _creatorRow() {
    return Row(
      children: [
        const Text('Created by',
            style:
                TextStyle(fontSize: 11.5, color: EnclavdColors.textSecondary)),
        const SizedBox(width: 8),
        InkWell(
          onTap: onCreatorTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              EnclavdAvatar(
                size: 22,
                url: vote.creatorAvatar.startsWith('/')
                    ? '${AppConfig.apiBaseUrl}${vote.creatorAvatar}'
                    : vote.creatorAvatar,
              ),
              const SizedBox(width: 7),
              Text(
                vote.creatorUsername,
                style:
                    const TextStyle(fontSize: 13, color: EnclavdColors.link),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        RankBadge(rank: vote.creatorRank),
      ],
    );
  }

  /// One full-width option: radio/check, text, percentage + weighted count,
  /// and the option-colored progress bar under them (modern poll pattern —
  /// the site's cramped %-text rows scaled to a phone).
  Widget _optionRow(int i, int? myVote) {
    const accent = _VotesScreenState._accent;
    final isSelected = selected == i; // pending selection
    final isMine = myVote == i; // current vote
    final highlighted = isSelected || isMine;
    final tappable = onSelect != null && !submitting;
    final color = domainColorFromHex(
        i < vote.colors.length ? vote.colors[i] : '#a855f7');
    final pct = vote.pct(i);
    return InkWell(
      key: ValueKey('vote-${vote.id}-option-$i'),
      onTap: tappable ? () => onSelect!(i) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: highlighted
              ? accent.withValues(alpha: 0.10)
              : EnclavdColors.cardSecondary.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: highlighted
              ? Border.all(color: accent.withValues(alpha: 0.35))
              : Border.all(color: Colors.transparent),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Radio-style indicator (site's form-radio) → check once
                // this is the viewer's current vote.
                if (isMine)
                  const FaIcon(FontAwesomeIcons.circleCheck,
                      size: 16, color: _VotesScreenState._accent)
                else
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: isSelected
                            ? accent
                            : EnclavdColors.textSecondary
                                .withValues(alpha: 0.55),
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent,
                              ),
                            ),
                          )
                        : null,
                  ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    vote.options[i],
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
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
            const SizedBox(height: 8),
            // Progress bar — the option's weighted share, filled with the
            // option's own color.
            ClipRRect(
              borderRadius: BorderRadius.circular(2.5),
              child: SizedBox(
                height: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.07)),
                    FractionallySizedBox(
                      widthFactor: pct.clamp(0.0, 100.0) / 100,
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
            if (isMine) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.circleCheck,
                      size: 11, color: _VotesScreenState._accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _myVoteLabel(),
                      style: const TextStyle(
                          fontSize: 11, color: _VotesScreenState._accent),
                    ),
                  ),
                ],
              ),
            ],
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

  Widget _voteButton(int? myVote) {
    return FilledButton.icon(
      onPressed: submitting ? null : onSubmit,
      style: FilledButton.styleFrom(
        backgroundColor: EnclavdColors.primaryButton,
        minimumSize: const Size.fromHeight(46),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      icon: submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : FaIcon(
              myVote != null
                  ? FontAwesomeIcons.rotate
                  : FontAwesomeIcons.circleCheck,
              size: 14,
              color: _VotesScreenState._accent,
            ),
      label: Text(submitting
          ? 'Submitting…'
          : (myVote != null ? 'Change Vote' : 'Submit Vote')),
    );
  }
}

/// Status pill for completed polls ('Completed' green / 'Cancelled' red).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.vote});

  final Vote vote;

  @override
  Widget build(BuildContext context) {
    final isCompleted = vote.status == 'completed';
    final color =
        isCompleted ? const Color(0xFF22C55E) : const Color(0xFFF87171);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        vote.status.isEmpty
            ? 'Ended'
            : vote.status[0].toUpperCase() + vote.status.substring(1),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// The card's clock line: "Ends: …" for active polls, "Ended: …" for
/// completed ones (site's end-label chip, centered under the doughnut).
class _EndChip extends StatelessWidget {
  const _EndChip({required this.vote});

  final Vote vote;

  @override
  Widget build(BuildContext context) {
    final label = vote.completed ? 'Ended' : 'Ends';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.clock,
              size: 10.5, color: EnclavdColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$label ${formatMessageTime(vote.endDate)}',
            style: const TextStyle(
                fontSize: 11.5, color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Native doughnut — the site's Chart.js canvas for one poll, here the
/// card's centered summary. Weighted counts per option, option colors,
/// small gaps between segments (the site's spacing:3); the center shows
/// the total vote count.
class _Donut extends StatelessWidget {
  const _Donut({required this.vote});

  final Vote vote;

  @override
  Widget build(BuildContext context) {
    if (vote.totalVotes <= 0) {
      return const SizedBox(
        width: 120,
        height: 110,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(FontAwesomeIcons.chartPie,
                size: 26, color: EnclavdColors.textSecondary),
            SizedBox(height: 8),
            Text('No votes yet',
                style: TextStyle(
                    fontSize: 12, color: EnclavdColors.textSecondary)),
          ],
        ),
      );
    }
    return SizedBox(
      width: 120,
      height: 110,
      child: CustomPaint(
        painter: _DonutPainter(vote.counts, vote.colors),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${vote.totalVotes}',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const Text('votes',
                  style: TextStyle(
                      fontSize: 11, color: EnclavdColors.textSecondary)),
            ],
          ),
        ),
      ),
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
    const stroke = 14.0;
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
