import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/personality_test_service.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/shimmer.dart';
import 'test_results_screen.dart';
import '../services/analytics_service.dart';

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
  final Map<int, String> _answers = {}; // question id -> option value
  int _current = 0; // index into _questions
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    trackScreen('/test');
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
        // Site parity: completed tests show results instead of the quiz.
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
        // Completed server-side in the meantime; same outcome: show results.
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
      appBar: AppBar(
        title: const Text('Personality Test'),
        backgroundColor: const Color(0xFF0B1628),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1628), EnclavdColors.background],
          ),
        ),
        child: SafeArea(child: _buildBody()),
      ),
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

class _IntroView extends StatelessWidget {
  const _IntroView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: EnclavdColors.link.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: FaIcon(FontAwesomeIcons.brain,
                  size: 38, color: EnclavdColors.link),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Personality Test',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          '40 questions that reveal how you think, decide and connect - '
          'and how you fit into the Enclavd community.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: EnclavdColors.textSecondary,
              fontSize: 14,
              height: 1.45),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            _StatChip(
                icon: FontAwesomeIcons.listCheck,
                value: '40',
                label: 'Questions'),
            SizedBox(width: 10),
            _StatChip(
                icon: FontAwesomeIcons.clock,
                value: '15-20',
                label: 'Minutes'),
            SizedBox(width: 10),
            _StatChip(
                icon: FontAwesomeIcons.lock, value: 'No', label: 'Retakes'),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: EnclavdColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EnclavdColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FaIcon(FontAwesomeIcons.circleInfo,
                      color: EnclavdColors.link, size: 16),
                  SizedBox(width: 8),
                  Text('About this test',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Answer every question honestly and pick the option that '
                'feels most like you. Your results appear instantly.',
                style: TextStyle(
                    color: Color(0xFFD1D5DB), // gray-300
                    fontSize: 13.5,
                    height: 1.45),
              ),
              SizedBox(height: 12),
              _InfoRow(
                icon: FontAwesomeIcons.checkDouble,
                color: Color(0xFF4ADE80),
                text: 'Results appear immediately after you submit',
              ),
              _InfoRow(
                icon: FontAwesomeIcons.clock,
                color: EnclavdColors.link,
                text: 'Estimated time: 15-20 minutes',
              ),
              _InfoRow(
                icon: FontAwesomeIcons.lock,
                color: Color(0xFFFACC15),
                text: 'Cannot be retaken once submitted',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: EnclavdColors.primaryButton,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          onPressed: onStart,
          icon: const FaIcon(FontAwesomeIcons.play, size: 14),
          label: const Text('Start Test'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.value, required this.label});

  final FaIconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: EnclavdColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EnclavdColors.border),
        ),
        child: Column(
          children: [
            FaIcon(icon, size: 15, color: EnclavdColors.link),
            const SizedBox(height: 6),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: EnclavdColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.color, required this.text});

  final FaIconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          FaIcon(icon, size: 13, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Color(0xFFD1D5DB), // gray-300
                    fontSize: 13,
                    height: 1.35)),
          ),
        ],
      ),
    );
  }
}

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
        // Progress header: counter + percent + rounded bar.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${current + 1} of $total',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: EnclavdColors.textSecondary)),
                  Text('${(progress * 100).round()}%',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: EnclavdColors.link)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF1F2937), // gray-800
                  color: const Color(0xFF3B82F6), // blue-500
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: EnclavdColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: EnclavdColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(question.question,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.45)),
                    const SizedBox(height: 18),
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
        // Footer: full-width action (Next / Submit).
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: Color(0xE6030712), // background at ~90%
            border: Border(top: BorderSide(color: EnclavdColors.divider)),
          ),
          child: isLast
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A), // green-600
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
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
                  label: Text(submitting ? 'Submitting...' : 'Submit Test'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: EnclavdColors.primaryButton,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
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
          borderRadius: BorderRadius.circular(14),
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
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
                        fontSize: 14.5,
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
