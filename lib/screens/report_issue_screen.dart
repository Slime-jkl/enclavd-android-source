import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/api_client.dart';
import '../api/reports_service.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import 'ticket_detail_screen.dart';
import '../services/analytics_service.dart';

/// The native Report an issue screen — a modern port of the site's
/// reports.php USER view: the report form (issue type + description) and
/// the viewer's own tickets grouped open/pending then closed/sealed.
class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key, this.reports});

  /// Injected for tests (real screen resolves AppServices.current).
  final ReportsService? reports;

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  AppServices? _services;

  final _contentController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _submitError;
  String? _submitSuccess;
  ReportPage? _page;
  String _type = 'Bug';

  ReportsService get _reports => widget.reports ?? _services!.reports;

  @override
  void initState() {
    super.initState();
    trackScreen('/reports');
    _load();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.reports == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _reports.list();
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load reports.';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    setState(() {
      _submitError = null;
      _submitSuccess = null;
    });
    if (content.isEmpty) {
      setState(() => _submitError = 'Please describe the issue you are reporting.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final ticket = await _reports.create(type: _type, content: content);
      if (!mounted) return;
      setState(() {
        _contentController.clear();
        _submitSuccess =
            'Your report has been submitted. We will review it as soon as possible.';
      });
      // Prepend the new ticket (open group first).
      final current = _page;
      _page = current == null
          ? null
          : ReportPage(
              items: [ticket, ...current.items],
              total: current.total + 1,
              page: current.page,
              totalPages: current.totalPages,
              allowedTypes: current.allowedTypes,
            );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitError = 'There was a problem submitting your report.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openTicket(ReportTicket ticket) {
    // Pushed detail (the site's /reports/<id>): pass the injected
    // service along so tests can drive it, else the real screen
    // resolves AppServices.current itself.
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TicketDetailScreen(
        reports: widget.reports,
        ticketId: ticket.id,
      ),
    ));
  }

  Future<void> _goToPage(int page) async {
    setState(() => _loading = true);
    try {
      final p = await _reports.list(page: page);
      if (!mounted) return;
      setState(() {
        _page = p;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
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
    if (_error != null) {
return ErrorView(message: _error!, onRetry: _load);
    }
    final page = _page!;
    final types = page.allowedTypes;
    if (!types.contains(_type)) {
      _type = types.isNotEmpty ? types.first : 'Other';
    }
    return RefreshIndicator(
      color: EnclavdColors.link,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // ── Report form (reports.php's form card) ──
          Container(
            padding: const EdgeInsets.all(16),
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
                    FaIcon(FontAwesomeIcons.flag,
                        size: 15, color: EnclavdColors.likeActive),
                    SizedBox(width: 8),
                    Text('Report an issue',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Use this form to report bugs, account problems, abuse, '
                  'or anything else that needs attention from the team.',
                  style: TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 13),
                ),
                if (_submitSuccess != null) ...[
                  const SizedBox(height: 12),
                  _Banner(
                    color: const Color(0xFF4ADE80),
                    icon: FontAwesomeIcons.circleCheck,
                    text: _submitSuccess!,
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  _Banner(
                    color: EnclavdColors.likeActive,
                    icon: FontAwesomeIcons.triangleExclamation,
                    text: _submitError!,
                  ),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: _inputDecoration('Issue type'),
                  dropdownColor: EnclavdColors.cardSecondary,
                  style: const TextStyle(color: EnclavdColors.textPrimary),
                  items: [
                    for (final t in types)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _type = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  maxLength: 255,
                  style: const TextStyle(color: EnclavdColors.textPrimary),
                  decoration: _inputDecoration(
                    'Describe the issue',
                    hint: 'Example: When I try to update my profile picture, '
                        'I get an error saying ...',
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const FaIcon(FontAwesomeIcons.paperPlane, size: 14),
                    label: const Text('Submit report'),
                    style: FilledButton.styleFrom(
                        backgroundColor: EnclavdColors.primaryButton),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // ── Your reports ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your reports',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (page.total > 0)
                Text('page ${page.page} of ${page.totalPages} '
                    '(${page.total} total)',
                    style: const TextStyle(
                        fontSize: 11.5, color: EnclavdColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          if (page.total == 0)
            const _EmptyReports()
          else ...[
            if (page.open.isNotEmpty) ...[
              const _GroupHeader(dot: Color(0xFF4ADE80), label: 'Open & pending'),
              for (final t in page.open) ...[
                _TicketRow(ticket: t, onTap: () => _openTicket(t)),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 6),
            ],
            if (page.closed.isNotEmpty) ...[
              const _GroupHeader(dot: EnclavdColors.textSecondary, label: 'Closed'),
              for (final t in page.closed) ...[
                _TicketRow(ticket: t, onTap: () => _openTicket(t)),
                const SizedBox(height: 8),
              ],
            ],
            if (page.totalPages > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: page.page > 1
                        ? () => _goToPage(page.page - 1)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EnclavdColors.link,
                      side: const BorderSide(color: EnclavdColors.border),
                    ),
                    child: const Text('Previous'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: page.page < page.totalPages
                        ? () => _goToPage(page.page + 1)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EnclavdColors.link,
                      side: const BorderSide(color: EnclavdColors.border),
                    ),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
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
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final FaIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.dot, required this.label});

  final Color dot;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: EnclavdColors.textSecondary)),
        ],
      ),
    );
  }
}

/// One ticket row (reports.php's list item): #id · type · date, a
/// two-line content clamp, and the status pill. Tapping opens the
/// ticket detail (the site's /reports/<id>).
class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, required this.onTap});

  final ReportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (ticket.status) {
      'Pending' => (
          const Color(0xFFFACC15),
          FontAwesomeIcons.hourglassHalf
        ),
      'Closed' => (
          const Color(0xFF4ADE80),
          FontAwesomeIcons.circleCheck
        ),
      'Sealed' => (
          const Color(0xFFC084FC),
          FontAwesomeIcons.circleCheck
        ),
      _ => (EnclavdColors.link, FontAwesomeIcons.hourglassHalf),
    };
    return Material(
      color: EnclavdColors.cardSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: EnclavdColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${ticket.id}',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: EnclavdColors.textSecondary)),
                    const Text('  ·  ',
                        style: TextStyle(
                            color: EnclavdColors.textSecondary, fontSize: 11)),
                    Flexible(
                      child: Text(ticket.type,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    if (ticket.date.isNotEmpty) ...[
                      const Text('  ·  ',
                          style: TextStyle(
                              color: EnclavdColors.textSecondary,
                              fontSize: 11)),
                      Text(ticket.date,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: EnclavdColors.textSecondary)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ticket.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(icon, size: 10, color: color),
                const SizedBox(width: 5),
                Text(ticket.status,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: const Column(
        children: [
          FaIcon(FontAwesomeIcons.inbox,
              size: 30, color: EnclavdColors.textSecondary),
          SizedBox(height: 12),
          Text('You have not submitted any reports yet.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('Use the form above to send your first report.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 12.5)),
        ],
      ),
    );
  }
}
