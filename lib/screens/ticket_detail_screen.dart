import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/api_client.dart';
import '../api/reports_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/analytics_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/rank_badge.dart';

/// The native ticket detail screen — a modern port of the site's
/// /reports/<id> page (ticket.php) with the USER-facing parts only:
/// the owner header, type + status with the mark-as-solved action, the
/// description, and the merged activity timeline of replies and status
/// logs, plus the reply box (hidden when the ticket is sealed).
class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    this.reports,
  });

  final int ticketId;

  /// Injected for tests (real screen resolves AppServices.current).
  final ReportsService? reports;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  AppServices? _services;

  final _replyController = TextEditingController();

  ReportDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _actionError;

  ReportsService get _reports => widget.reports ?? _services!.reports;

  @override
  void initState() {
    super.initState();
    trackScreen('/report');
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
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
      _actionError = null;
    });
    try {
      final detail = await _reports.fetchDetail(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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
        _error = 'Failed to load this report.';
        _loading = false;
      });
    }
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await _reports.addReply(ticketId: widget.ticketId, content: content);
      _replyController.clear();
      await _load(); // refetch: new event + status flipped to Pending
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Unable to save your reply right now.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markSolved() async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await _reports.markSolved(widget.ticketId);
      await _load(); // refetch: status + solved date + log event
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Unable to update ticket status.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Report #${widget.ticketId}')),
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
    final detail = _detail!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_actionError != null) ...[
          _ErrorBanner(text: _actionError!),
          const SizedBox(height: 12),
        ],
        // ── Owner header (ticket.php's avatar + identity row) ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EnclavdColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EnclavdColors.border),
          ),
          child: Row(
            children: [
              if (detail.owner != null)
                EnclavdAvatar(
                  size: 48,
                  url: _avatarUrl(detail.owner!.profilePictureUrl),
                  borderColor: RankColors.forRank(detail.owner!.rank),
                )
              else
                const FaIcon(FontAwesomeIcons.user,
                    size: 22, color: EnclavdColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            detail.owner?.username ?? 'You',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: detail.owner != null
                                  ? RankColors.forRank(detail.owner!.rank)
                                  : EnclavdColors.textPrimary,
                            ),
                          ),
                        ),
                        if (detail.owner != null) ...[
                          const SizedBox(width: 6),
                          RankBadge(rank: detail.owner!.rank),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Report #${detail.id}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: EnclavdColors.textSecondary)),
                  ],
                ),
              ),
              Text(detail.date,
                  style: const TextStyle(
                      fontSize: 11, color: EnclavdColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Type + status + solve action ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EnclavdColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EnclavdColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _TypeChip(type: detail.type),
                  _StatusPill(status: detail.status),
                  if (detail.solvedDate != null)
                    Text(
                      'Resolved on ${detail.solvedDate}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4ADE80)), // green-400
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Description',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: EnclavdColors.textSecondary)),
              const SizedBox(height: 6),
              Text(detail.content,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.45, color: EnclavdColors.textPrimary)),
              if (!detail.isClosed) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _markSolved,
                    icon: const FaIcon(FontAwesomeIcons.circleCheck, size: 14),
                    label: const Text('Mark as solved'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D), // green-700
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Activity timeline (replies + logs, oldest first) ──
        Container(
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
                  FaIcon(FontAwesomeIcons.comments,
                      size: 14, color: EnclavdColors.link),
                  SizedBox(width: 8),
                  Text('Activity',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              if (detail.events.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'No activity yet. Use the box below to add more '
                    'information or follow up.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: EnclavdColors.textSecondary),
                  ),
                )
              else
                for (final event in detail.events) ...[
                  if (event.isLog)
                    _LogChip(event: event)
                  else
                    _ReplyBubble(event: event),
                  const SizedBox(height: 10),
                ],
              // ── Reply box (hidden when sealed) ──
              if (detail.sealed)
                const Row(
                  children: [
                    FaIcon(FontAwesomeIcons.lock,
                        size: 12, color: EnclavdColors.likeActive),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This ticket has been sealed. It cannot be reopened.',
                        style: TextStyle(
                            fontSize: 12, color: EnclavdColors.likeActive),
                      ),
                    ),
                  ],
                )
              else ...[
                const Divider(height: 20, color: EnclavdColors.divider),
                TextField(
                  controller: _replyController,
                  maxLines: 3,
                  maxLength: 255,
                  style: const TextStyle(color: EnclavdColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Add a reply',
                    filled: true,
                    fillColor: EnclavdColors.cardSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: EnclavdColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        (_busy || _replyController.text.trim().isEmpty)
                            ? null
                            : _sendReply,
                    icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 14),
                    label: const Text('Send reply'),
                    style: FilledButton.styleFrom(
                      backgroundColor: EnclavdColors.primaryButton,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _avatarUrl(String path) =>
      path.startsWith('/') ? '${AppConfig.apiBaseUrl}$path' : path;
}

/// The type chip (ticket.php's fa-tag pill).
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.tag,
              size: 10, color: EnclavdColors.link),
          const SizedBox(width: 6),
          Text(type,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// The status pill with ticket.php's exact colors per status.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      'Pending' => (const Color(0xFFFACC15), FontAwesomeIcons.hourglassHalf),
      'Closed' => (const Color(0xFF4ADE80), FontAwesomeIcons.circleCheck),
      'Sealed' => (const Color(0xFFC084FC), FontAwesomeIcons.lock),
      _ => (EnclavdColors.link, FontAwesomeIcons.hourglassHalf),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          Text(status,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// One reply in the timeline (ticket.php's avatar + bubble row).
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.event});

  final TicketEvent event;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EnclavdAvatar(
          size: 32,
          url: event.profilePictureUrl.startsWith('/')
              ? '${AppConfig.apiBaseUrl}${event.profilePictureUrl}'
              : event.profilePictureUrl,
          borderColor: EnclavdColors.border,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(event.username,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  RankBadge(rank: event.rank),
                  const Spacer(),
                  Text(event.date,
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: EnclavdColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: EnclavdColors.cardSecondary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: EnclavdColors.border),
                ),
                child: Text(event.content,
                    style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One status log in the timeline (ticket.php's fa-history chip).
class _LogChip extends StatelessWidget {
  const _LogChip({required this.event});

  final TicketEvent event;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: EnclavdColors.cardSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(FontAwesomeIcons.clockRotateLeft,
                size: 11, color: EnclavdColors.textSecondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(event.ticketLog,
                  style: const TextStyle(
                      fontSize: 11.5, color: EnclavdColors.textSecondary)),
            ),
            const SizedBox(width: 8),
            Text(event.date,
                style: const TextStyle(
                    fontSize: 10, color: EnclavdColors.textSecondary)),
          ],
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
