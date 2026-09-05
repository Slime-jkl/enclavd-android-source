import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/api_client.dart';
import '../api/results_service.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/personality_widgets.dart';
import 'test_screen.dart';
import '../services/analytics_service.dart';

class TestResultsScreen extends StatefulWidget {
  const TestResultsScreen({super.key, this.results});

  /// Injected for tests (real screen resolves AppServices.current).
  final ResultsService? results;

  @override
  State<TestResultsScreen> createState() => _TestResultsScreenState();
}

class _TestResultsScreenState extends State<TestResultsScreen> {
  AppServices? _services;

  bool _loading = true;
  bool _noResults = false;
  String? _error;
  TestResults? _results;

  ResultsService get _resultsService =>
      widget.results ?? _services!.results;

  @override
  void initState() {
    super.initState();
    trackScreen('/test-results');
    _load();
  }

  Future<void> _load() async {
    // Tests inject the service; skip the AppServices dance then.
    if (widget.results == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _noResults = false;
    });
    try {
      final r = await _resultsService.fetchResults();
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 404) {
          _noResults = true; // no valid test, the site redirects here
        } else {
          _error = e.message;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load test results.';
        _loading = false;
      });
    }
  }

  Future<void> _openTestPage() async {
    // On completion the quiz replaces itself with fresh results; refetch on return.
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TestScreen()),
    );
    if (completed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Results')),
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
    if (_noResults) return _NoResultsView(onTakeTest: _openTestPage);
    if (_error != null) {
return ErrorView(message: _error!, onRetry: _load);
    }
    return _ResultsView(results: _results!, onTakeTest: _openTestPage);
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.results, required this.onTakeTest});

  final TestResults results;
  final VoidCallback onTakeTest;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Personality type badge (the site's lg badge).
        Center(child: PersonalityTypeBadge(type: results.personalityType)),
        const SizedBox(height: 20),
        // Type card: title + description + strengths / growth areas.
        PersonalityInfoCard(
          title: results.title,
          description: results.description,
          strengths: results.strengths,
          weaknesses: results.weaknesses,
        ),
        const SizedBox(height: 14),
        // Trait bars (results.php's four percentage pairs).
        TraitBar(
          label: 'Introversion - Extraversion',
          first: 'Introversion',
          firstPercent: results.iePercentage,
          firstColor: const Color(0xFF3B82F6), // blue-500
          second: 'Extraversion',
          secondColor: const Color(0xFFEF4444), // red-500
        ),
        const SizedBox(height: 10),
        TraitBar(
          label: 'Sensing - Intuition',
          first: 'Sensing',
          firstPercent: results.snPercentage,
          firstColor: const Color(0xFF22C55E), // green-500
          second: 'Intuition',
          secondColor: const Color(0xFFA855F7), // purple-500
        ),
        const SizedBox(height: 10),
        TraitBar(
          label: 'Thinking - Feeling',
          first: 'Thinking',
          firstPercent: results.tfPercentage,
          firstColor: const Color(0xFFEAB308), // yellow-500
          second: 'Feeling',
          secondColor: const Color(0xFFEC4899), // pink-500
        ),
        const SizedBox(height: 10),
        TraitBar(
          label: 'Judging - Perceiving',
          first: 'Judging',
          firstPercent: results.jpPercentage,
          firstColor: const Color(0xFFF97316), // orange-500
          second: 'Perceiving',
          secondColor: const Color(0xFF6366F1), // indigo-500
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: onTakeTest,
            icon: const FaIcon(FontAwesomeIcons.users,
                size: 14, color: EnclavdColors.link),
            label: const Text('See all types'),
            style: OutlinedButton.styleFrom(
              foregroundColor: EnclavdColors.link,
              side: const BorderSide(color: EnclavdColors.border),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoResultsView extends StatelessWidget {
  const _NoResultsView({required this.onTakeTest});

  final VoidCallback onTakeTest;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(FontAwesomeIcons.chartPie,
                size: 40, color: EnclavdColors.textSecondary),
            const SizedBox(height: 14),
            const Text('No test results yet',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Take the personality test on the website to unlock '
              'your results here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: EnclavdColors.textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onTakeTest,
              icon: const FaIcon(FontAwesomeIcons.arrowUpRightFromSquare,
                  size: 14),
              label: const Text('Take the test'),
              style: FilledButton.styleFrom(
                  backgroundColor: EnclavdColors.primaryButton),
            ),
          ],
        ),
      ),
    );
  }
}
