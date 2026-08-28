import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/diary_service.dart';
import '../main.dart';
import '../services/analytics_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/user_facing_errors.dart';
import '../widgets/error_view.dart';
import '../widgets/shimmer.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, this.diary});

  /// Injected for tests (the real screen resolves AppServices.current).
  final DiaryService? diary;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  AppServices? _services;

  DiaryService get _service => widget.diary ?? _services!.diary;

  DiarySnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  // Wizard state.
  int _step = 0;
  int? _mood;
  final _win = TextEditingController();
  final _avoided = TextEditingController();
  final _tomorrow = TextEditingController();
  final _thought = TextEditingController();
  bool _busy = false;
  String? _wizardError;

  // The prestige line from the save, shown once on the locked hero.
  DiaryPrestige? _lastPrestige;

  @override
  void initState() {
    super.initState();
    trackScreen('/diary');
    _load();
  }

  @override
  void dispose() {
    _win.dispose();
    _avoided.dispose();
    _tomorrow.dispose();
    _thought.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.diary == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.fetchToday();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(e, fallback: 'Could not load your diary.');
        _loading = false;
      });
    }
  }

  // Wizard step map; first-ever users get a warning step up front.
  bool get _hasWarningStep => (_snapshot?.stats.totalEntries ?? 0) == 0;

  int get _totalSteps => _hasWarningStep ? 6 : 5;

  int get _moodIndex => _hasWarningStep ? 1 : 0;
  int get _winIndex => _moodIndex + 1;
  int get _avoidedIndex => _winIndex + 1;
  int get _tomorrowIndex => _avoidedIndex + 1;
  int get _thoughtIndex => _tomorrowIndex + 1;

  void _goTo(int n) {
    setState(() {
      _wizardError = '';
      _step = n.clamp(0, _totalSteps - 1);
    });
  }

  void _next() {
    if (_step == _moodIndex && _mood == null) {
      setState(() => _wizardError = 'Pick a mood for today.');
      return;
    }
    if (_step == _winIndex && _win.text.trim().isEmpty) {
      setState(() => _wizardError =
          'Name one small win. Even a tiny one counts.');
      return;
    }
    _goTo(_step + 1);
  }

  Future<void> _save() async {
    if (_mood == null) {
      setState(() => _wizardError = 'Pick a mood for today.');
      return;
    }
    final win = _win.text.trim();
    if (win.isEmpty) {
      setState(() => _wizardError =
          'Name one small win. Even a tiny one counts.');
      return;
    }
    setState(() {
      _busy = true;
      _wizardError = '';
    });
    try {
      final result = await _service.saveToday(
        mood: _mood!,
        win: win,
        avoided: _avoided.text,
        tomorrow: _tomorrow.text,
        thought: _thought.text,
      );
      if (!mounted) return;
      setState(() {
        // Prepend the new entry to the recent list (dedup by date).
        _snapshot = DiarySnapshot(
          date: result.date,
          entry: result.entry,
          locked: result.locked,
          stats: result.stats,
          recent: [
            result.entry,
            ...?_snapshot?.recent
                .where((e) => e.date != result.entry.date),
          ],
        );
        _lastPrestige = result.prestige;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _wizardError = userFacingError(e, fallback: 'Could not save your entry.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            FaIcon(FontAwesomeIcons.book, size: 18, color: EnclavdColors.link),
            SizedBox(width: 10),
            Text('Diary'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _loadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final snapshot = _snapshot!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'A private log of the daily grind. One entry a day. No feed, '
            'no likes. Just you, the work, and the record.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EnclavdColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Locked gate = "today has an entry", not the response's `locked`
        // flag: a fresh save returns locked:false yet must land on the
        // locked card (same rule as the web page's `$today_entry` check).
        _statsRow(snapshot.stats),
        const SizedBox(height: 12),
        _moodStrip(snapshot.stats),
        const SizedBox(height: 16),
        if (snapshot.entry != null) _lockedCard() else _wizardCard(),
        const SizedBox(height: 16),
        _recentSection(snapshot),
      ],
    );
  }

  Widget _wizardCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Today's diary",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  'Step ${_step + 1} of $_totalSteps',
                  style: const TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              formatDiaryDate(_snapshot!.date),
              style: const TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _diaryProgress((_step + 1) / _totalSteps),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
            ),
            if (_wizardError != null) ...[
              const SizedBox(height: 12),
              Text(
                _wizardError!,
                style: const TextStyle(
                    color: Color(0xFFF87171), fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 20),
            _wizardNav(),
          ],
        ),
      ),
    );
  }

  Widget _diaryProgress(double value) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Container(color: const Color(0x80374151)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    if (_hasWarningStep && _step == 0) return _warningStep();
    if (_step == _moodIndex) return _moodStep();
    if (_step == _winIndex) return _winStep();
    if (_step == _avoidedIndex) return _avoidedStep();
    if (_step == _tomorrowIndex) return _tomorrowStep();
    return _thoughtStep();
  }

  Widget _stepQuestion(String emoji, String? title, Widget body,
      {String? tag, bool required = false, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji,
            style: const TextStyle(fontSize: 34, height: 1)),
        const SizedBox(height: 12),
        if (title != null)
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, height: 1.35)),
        if (tag != null) ...[
          const SizedBox(height: 10),
          Text(
            tag.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: required
                  ? const Color(0xFFFBBF24)
                  : EnclavdColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        body,
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint,
              style: const TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _warningStep() {
    return _stepQuestion(
      '\u{26A0}\u{FE0F}',
      'Before you start',
      const Text(
        'Starting a Journal is a commitment with real stakes. Every entry '
        'you lock in awards you prestige points on the site. Miss a day, '
        'and you lose prestige for every day you skip. One entry per day, '
        'and once it\'s locked in, it stays. No edits, no take-backs.',
        style: TextStyle(
            color: EnclavdColors.textSecondary,
            fontSize: 14,
            height: 1.6),
      ),
    );
  }

  Widget _moodStep() {
    return _stepQuestion(
      '\u{1F4D3}',
      null,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pick how today went, then walk through the questions. Once '
            'you hit Lock it in, it stays. Two minutes, tops.',
            style: TextStyle(
                color: EnclavdColors.textSecondary,
                fontSize: 14,
                height: 1.6),
          ),
          const SizedBox(height: 18),
          const Text(
            'How did today go?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final mood in kDiaryMoods)
                Expanded(child: _moodButton(mood)),
            ],
          ),
        ],
      ),
      hint: _mood == null
          ? 'Tap a mood...'
          : kDiaryMoods.firstWhere((m) => m.value == _mood).hint,
    );
  }

  Widget _moodButton(DiaryMood mood) {
    final selected = _mood == mood.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _mood = mood.value;
          _wizardError = '';
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                : EnclavdColors.cardSecondary.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF3B82F6)
                  : EnclavdColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(mood.emoji, style: const TextStyle(fontSize: 26, height: 1)),
              const SizedBox(height: 6),
              Text(
                mood.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: selected
                      ? EnclavdColors.textPrimary
                      : EnclavdColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _winStep() {
    return _stepQuestion(
      '\u{1F3C6}',
      'What was a small win you achieved today?',
      TextField(
        controller: _win,
        maxLines: 3,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Finished the thing you kept stalling on...',
          counterStyle:
              TextStyle(color: EnclavdColors.textSecondary, fontSize: 11),
        ),
      ),
      tag: 'Required',
      required: true,
      hint: 'Big days are rare. Small wins compound. Name one, however small.',
    );
  }

  Widget _avoidedStep() {
    return _stepQuestion(
      '\u{1F6A7}',
      'What are you avoiding?',
      TextField(
        controller: _avoided,
        maxLines: 3,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: 'The thing that keeps slipping to tomorrow...',
          counterStyle:
              TextStyle(color: EnclavdColors.textSecondary, fontSize: 11),
        ),
      ),
      tag: 'Optional',
      hint:
          'Naming it makes it real. Tomorrow it\'s a decision, not a fog.',
    );
  }

  Widget _tomorrowStep() {
    return _stepQuestion(
      '\u{1F3AF}',
      'What will you do better tomorrow?',
      TextField(
        controller: _tomorrow,
        maxLines: 3,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: 'A concrete action, not a vibe...',
          counterStyle:
              TextStyle(color: EnclavdColors.textSecondary, fontSize: 11),
        ),
      ),
      tag: 'Optional',
      hint: 'One concrete action, not a vibe.',
    );
  }

  Widget _thoughtStep() {
    return _stepQuestion(
      '\u{1F4AD}',
      'What\'s one interesting thought you explored today?',
      TextField(
        controller: _thought,
        maxLines: 3,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: 'The idea that kept circling back...',
          counterStyle:
              TextStyle(color: EnclavdColors.textSecondary, fontSize: 11),
        ),
      ),
      tag: 'Optional',
      hint: 'The idea that kept circling back while you were doing '
          'something else.',
    );
  }

  Widget _wizardNav() {
    final last = _step == _thoughtIndex;
    final first = _step == 0;
    final label = _hasWarningStep && first
        ? 'I understand. Start my journal'
        : (last ? 'Lock it in' : (_step == _moodIndex ? 'Start' : 'Next'));

    final Widget button;
    if (last) {
      button = Expanded(
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const FaIcon(FontAwesomeIcons.lock, size: 14),
          label: Text(_busy ? 'Locking in...' : label),
        ),
      );
    } else {
      button = Expanded(
        child: ElevatedButton(
          onPressed: _next,
          child: Text(label),
        ),
      );
    }

    return Row(
      children: [
        if (!first) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _goTo(_step - 1),
              style: OutlinedButton.styleFrom(
                foregroundColor: EnclavdColors.textSecondary,
                side: const BorderSide(color: EnclavdColors.divider),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 10),
        ],
        button,
      ],
    );
  }

  Widget _lockedCard() {
    final entry = _snapshot!.entry!;
    final prestige = _lastPrestige;
    // Just the lock, centered; the answers live in the Recent row below.
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            const Text('\u{1F512}', style: TextStyle(fontSize: 56, height: 1)),
            const SizedBox(height: 16),
            const Text(
              'Locked in.',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              formatDiaryDate(entry.date),
              style: const TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'See you tomorrow.',
              style: TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 13),
            ),
            if (prestige != null &&
                (prestige.awarded > 0 || prestige.penalty > 0)) ...[
              const SizedBox(height: 12),
              _prestigeLine(prestige),
            ],
          ],
        ),
      ),
    );
  }

  Widget _prestigeLine(DiaryPrestige p) {
    final String text;
    final Color color;
    if (p.penalty > 0) {
      text = 'Earned +${p.awarded} prestige. Lost ${p.penalty} for '
          '${p.missedDays} ${p.missedDays == 1 ? 'missed day' : 'missed days'}.';
      color = p.net < 0
          ? const Color(0xFFF87171)
          : const Color(0xFF34D399);
    } else {
      text = 'This entry earned you +${p.awarded} prestige.';
      color = const Color(0xFF34D399);
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 13, height: 1.4),
    );
  }

  Widget _statsRow(DiaryStats stats) {
    return Row(
      children: [
        _statCard('\u{1F525}', stats.streak, 'day streak'),
        const SizedBox(width: 10),
        _statCard('\u{1F3C6}', stats.longestStreak, 'best streak'),
        const SizedBox(width: 10),
        _statCard('\u{1F4D3}', stats.totalEntries, 'entries'),
      ],
    );
  }

  Widget _statCard(String emoji, int number, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: EnclavdColors.cardSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EnclavdColors.border, width: 1.5),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20, height: 1)),
            const SizedBox(height: 6),
            Text(
              '$number',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                color: EnclavdColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodStrip(DiaryStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mood - last 30 days',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: EnclavdColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final mood in kDiaryMoods)
                  Expanded(child: _moodChip(mood, stats)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodChip(DiaryMood mood, DiaryStats stats) {
    final count = stats.moods30d[mood.value] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Opacity(
        opacity: count == 0 ? 0.38 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF374151).withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              Text(mood.emoji,
                  style: const TextStyle(fontSize: 18, height: 1)),
              const SizedBox(height: 4),
              Text(
                'x$count',
                style: const TextStyle(
                    color: EnclavdColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentSection(DiarySnapshot snapshot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent entries',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (snapshot.recent.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: EnclavdColors.cardSecondary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Text('\u{1F331}', style: TextStyle(fontSize: 32, height: 1)),
                SizedBox(height: 10),
                Text(
                  'No entries yet. Today is a good day to start.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          )
        else
          for (final entry in snapshot.recent)
            _RecentEntryTile(
              // Key by date: without it, the tile at index 0 reuses the
              // previous day's State after a save.
              key: ValueKey(entry.date),
              entry: entry,
              initiallyOpen: entry.date == snapshot.date,
            ),
      ],
    );
  }

  Widget _loadingView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: const [
        Center(child: ShimmerBox(width: 260, height: 32, borderRadius: 8)),
        SizedBox(height: 24),
        ShimmerBox(width: double.infinity, height: 240, borderRadius: 16),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: ShimmerBox(height: 90, borderRadius: 16)),
            SizedBox(width: 10),
            Expanded(child: ShimmerBox(height: 90, borderRadius: 16)),
            SizedBox(width: 10),
            Expanded(child: ShimmerBox(height: 90, borderRadius: 16)),
          ],
        ),
        SizedBox(height: 16),
        ShimmerBox(width: double.infinity, height: 100, borderRadius: 16),
        SizedBox(height: 16),
        ShimmerBox(width: double.infinity, height: 64, borderRadius: 16),
      ],
    );
  }
}

class _DiaryFieldRow extends StatelessWidget {
  const _DiaryFieldRow({
    required this.icon,
    required this.label,
    required this.text,
  });

  final String icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 15, height: 1.4)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: EnclavdColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(
                    fontSize: 13, height: 1.55, color: EnclavdColors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentEntryTile extends StatefulWidget {
  const _RecentEntryTile({
    super.key,
    required this.entry,
    required this.initiallyOpen,
  });

  final DiaryEntry entry;
  final bool initiallyOpen;

  @override
  State<_RecentEntryTile> createState() => _RecentEntryTileState();
}

class _RecentEntryTileState extends State<_RecentEntryTile> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text(entry.moodEmoji,
                      style: const TextStyle(fontSize: 24, height: 1)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatDiaryDate(entry.date),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: EnclavdColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.win,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: EnclavdColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const FaIcon(FontAwesomeIcons.chevronDown,
                        size: 12, color: EnclavdColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final field in _fieldRows(entry)) ...[
                    _DiaryFieldRow(
                        icon: field.icon, label: field.label, text: field.text),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<({String icon, String label, String text})> _fieldRows(
      DiaryEntry entry) {
    return [
      (icon: '\u{1F3C6}', label: 'Small win', text: entry.win),
      if (entry.avoided.isNotEmpty)
        (icon: '\u{1F6A7}', label: 'Avoiding', text: entry.avoided),
      if (entry.tomorrow.isNotEmpty)
        (icon: '\u{1F3AF}', label: 'Tomorrow', text: entry.tomorrow),
      if (entry.thought.isNotEmpty)
        (icon: '\u{1F4AD}', label: 'Thought explored', text: entry.thought),
    ];
  }
}

/// ISO date -> 'Today' / 'Yesterday' / 'Aug 27, 2026' (local midnight).
String formatDiaryDate(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return iso;
  final d = DateTime(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = (today.difference(d).inHours / 24).round();
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
