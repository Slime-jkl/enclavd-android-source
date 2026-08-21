import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/personality_test_service.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/shimmer.dart';
import 'test_results_screen.dart';

/// The native Personality Assessment — modern port of test_page.php:
/// intro card (about/instructions), then the 40 questions one at a time
/// with the site's five options (Strongly Agree → Strongly Disagree),
/// a progress bar, and a submit that scores server-side with the site's
/// OWN engine (questions_logic.php). On success the quiz is REPLACED by
/// the Test Results screen (site parity: /test/submit → /results).
///
/// The site shows this only when the account has no personality_type
/// (header banner); the app's feed banner uses the same rule and pushes
/// this screen. GET already_taken (a valid test row exists) jumps
/// straight to results — the site redirects /test_page → /results.
class TestScreen extends StatefulWidget {
  const TestScreen({super.key, this.test, this.resultsBuilder});

  /// Injected for tests (real screen resolves AppServices.current).
  final PersonalityTestService? test;

  /// Replaces the pushed TestResultsScreen (widget-test seam).
  final WidgetBuilder? resultsBuilder;

  @override
  State<TestScreen> createState() => _TestScreenState();
}

enum _Phase { loading, error, intro, quiz }

class _TestScreenState extends State<TestScreen> {
  PersonalityTestService? _service;
  _Phase _phase = _Phase.loading;
  String? _error;

  List<PersonalityQuestion> _questions = const [];
  final Map<int, String> _answers = {}; // question id → option value
  int _current = 0; // index into _questions
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _service ??= widget.test ??
        (AppServices.current ?? await AppServices.create()).personalityTest;
    if (!mounted) return;
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final info = await _service!.fetchTest();
      if (!mounted) return;
      if (info.alreadyTaken) {
        // Site parity: /test_page redirects to /results for completed
        // tests. Show the results instead of the quiz.
        _openResults();
        return;
      }
      setState(() {
        _questions = info.questions;
        _current = 0;
        _phase = _Phase.intro;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.status == 401 ? 'Session expired. Please log in again.' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'Failed to load the test.';
      });
    }
  }

  void _start() {
    setState(() {
      _current = 0;
      _answers.clear();
      _phase = _Phase.quiz;
    });
  }

  void _select(String value) {
    setState(() => _answers[_questions[_current].id] = value);
  }

  void _next() {
    if (_answers.containsKey(_questions[_current].id)) {
      setState(() => _current++);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _service!.submit(_answers);
      if (!mounted) return;
      _openResults();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409) {
        // Test already completed server-side (e.g. taken on the website
        // between the banner and the submit). Same outcome: show results.
        _openResults();
        return;
      }
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not submit the test.')));
    }
  }

  /// Replaces the quiz with the results screen (site: submit → /results).
  /// Pops the caller's route future with `true` so e.g. the feed banner
  /// knows to refresh the account (personality now set).
  void _openResults() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: widget.resultsBuilder ?? (_) => const TestResultsScreen(),
      ),
      result: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personality Test')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loading:
        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerBox(width: 200, height: 26),
            SizedBox(height: 16),
            ShimmerBox(width: double.infinity, height: 120),
            SizedBox(height: 12),
            ShimmerBox(width: double.infinity, height: 44),
            SizedBox(height: 12),
            ShimmerBox(width: double.infinity, height: 44),
          ],
        );
      case _Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FaIcon(FontAwesomeIcons.cloudArrowDown,
                    size: 34, color: EnclavdColors.textSecondary),
                const SizedBox(height: 12),
                Text(_error ?? 'Something went wrong.',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: EnclavdColors.textSecondary)),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: EnclavdColors.primaryButton),
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      case _Phase.intro:
        return _IntroView(onStart: _start);
      case _Phase.quiz:
        return _QuizView(
          questions: _questions,
          answers: _answers,
          current: _current,
          submitting: _submitting,
          onSelect: _select,
          onNext: _next,
          onSubmit: _submit,
        );
    }
  }
}

/// The site's test_page.php intro card: about the test, instructions,
/// time + completion notes, and the Start button.
class _IntroView extends StatelessWidget {
  const _IntroView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EnclavdColors.cardSecondary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EnclavdColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FaIcon(FontAwesomeIcons.circleInfo,
                      color: EnclavdColors.link, size: 18),
                  SizedBox(width: 10),
                  Text('About this test',
                      style: TextStyle(
                          color: EnclavdColors.link,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'You are about to take a personality test consisting of 40 '
                'questions. This test will help evaluate various aspects of '
                'your personality and determine your compatibility with our '
                'community.',
                style: TextStyle(
                    color: Color(0xFFD1D5DB), // gray-300
                    fontSize: 14,
                    height: 1.4),
              ),
              SizedBox(height: 14),
              _IntroList(
                title: 'Instructions',
                color: Color(0xFF93C5FD), // blue-300
                items: [
                  'Answer all questions honestly',
                  'Choose one option for each question',
                  'Take your time to consider each answer',
                  'There are no right or wrong answers',
                ],
              ),
              SizedBox(height: 12),
              _IntroList(
                title: 'Time & Completion',
                color: Color(0xFF93C5FD),
                items: [
                  'Estimated time: 15-20 minutes',
                  'All questions are required',
                  'Results available immediately',
                  'Cannot be retaken once submitted',
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: EnclavdColors.primaryButton,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            onPressed: onStart,
            icon: const FaIcon(FontAwesomeIcons.play, size: 14),
            label: const Text('Start Test'),
          ),
        ),
      ],
    );
  }
}

class _IntroList extends StatelessWidget {
  const _IntroList({
    required this.title,
    required this.color,
    required this.items,
  });

  final String title;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1F374151), // gray-700/30-ish
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            color: Color(0xFFD1D5DB), // gray-300
                            fontSize: 13,
                            height: 1.3)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The site's five options (test_page.php): Strongly Agree (green
/// fa-check-double) → Agree (fa-check) → Neutral (fa-scale-balanced) →
/// Disagree (fa-times) → Strongly Disagree (fa-circle-xmark).
class _Option {
  const _Option(this.value, this.label, this.icon, this.color);

  final String value;
  final String label;
  final FaIconData icon;
  final Color color;
}

const _kOptions = [
  _Option('strongly_agree', 'Strongly Agree', FontAwesomeIcons.checkDouble,
      Color(0xFF22C55E)), // green-500
  _Option('agree', 'Agree', FontAwesomeIcons.check, Color(0xFF4ADE80)), // green-400
  _Option('neutral', 'Neutral', FontAwesomeIcons.scaleBalanced,
      Color(0xFF9CA3AF)), // gray-400
  _Option('disagree', 'Disagree', FontAwesomeIcons.xmark, Color(0xFFF87171)), // red-400
  _Option('strongly_disagree', 'Strongly Disagree',
      FontAwesomeIcons.circleXmark, Color(0xFFEF4444)), // red-500
];

class _QuizView extends StatelessWidget {
  const _QuizView({
    required this.questions,
    required this.answers,
    required this.current,
    required this.submitting,
    required this.onSelect,
    required this.onNext,
    required this.onSubmit,
  });

  final List<PersonalityQuestion> questions;
  final Map<int, String> answers;
  final int current;
  final bool submitting;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final total = questions.length;
    final question = questions[current];
    final selected = answers[question.id];
    final isLast = current == total - 1;
    final progress = ((current + (selected != null ? 1 : 0)) / total)
        .clamp(0.0, 1.0);

    return Column(
      children: [
        // Progress (site: 4px rounded bar, blue fill).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFF4B5563), // gray-600
              color: const Color(0xFF3B82F6), // blue-500
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EnclavdColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: EnclavdColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.lightbulb,
                            color: Color(0xFFFACC15), // yellow-500
                            size: 16),
                        const SizedBox(width: 8),
                        Text('Question ${question.id} of $total',
                            style: const TextStyle(
                                color: EnclavdColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(question.question,
                        style: const TextStyle(
                            color: Color(0xFFD1D5DB), // gray-300
                            fontSize: 15,
                            height: 1.4)),
                    const SizedBox(height: 16),
                    for (final option in _kOptions)
                      _OptionRow(
                        option: option,
                        selected: selected == option.value,
                        onTap: () => onSelect(option.value),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Footer (site: sticky button-container).
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Color(0xCC111827), // gray-900/80
            border: Border(top: BorderSide(color: EnclavdColors.divider)),
          ),
          child: isLast
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A), // green-600
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (selected == null || submitting)
                      ? null
                      : onSubmit,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const FaIcon(FontAwesomeIcons.paperPlane, size: 14),
                  label: Text(submitting ? 'Submitting…' : 'Submit Test'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: EnclavdColors.primaryButton,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: selected == null ? null : onNext,
                  icon: const FaIcon(FontAwesomeIcons.arrowRight, size: 14),
                  label: const Text('Next Question'),
                ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Option option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? const Color(0x333B82F6) // blue-500/20 (site .selected)
            : EnclavdColors.cardSecondary.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? EnclavdColors.link // blue-400 selected ring
                : EnclavdColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                FaIcon(option.icon, color: option.color, size: 17),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(option.label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFFD1D5DB), // gray-300
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      )),
                ),
                if (selected)
                  const FaIcon(FontAwesomeIcons.circleCheck,
                      color: EnclavdColors.link, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
