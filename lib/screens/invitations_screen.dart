import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/api_client.dart';
import '../api/invitations_service.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../services/analytics_service.dart';

/// The native Invitations screen — a modern port of the site's
/// invitations.php USER view (no admin invite creation, no see-all
/// list): the remaining invite count with a "Create Invite" button and
/// the user's own invitation codes with status, expiry, copy and delete.
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key, this.invitations});

  /// Injected for tests (real screen resolves AppServices.current).
  final InvitationsService? invitations;

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  AppServices? _services;

  bool _loading = true;
  bool _creating = false;
  String? _error;
  InvitationList? _list;

  InvitationsService get _invitations =>
      widget.invitations ?? _services!.invitations;

  @override
  void initState() {
    super.initState();
    trackScreen('/invitations');
    _load();
  }

  Future<void> _load() async {
    if (widget.invitations == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _invitations.list();
      if (!mounted) return;
      setState(() {
        _list = list;
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
        _error = 'Failed to load invitations.';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final created = await _invitations.create();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invitation created — valid for 30 days'),
        duration: Duration(seconds: 3),
      ));
      // Merge the new invite into the list (newest first) + fresh count.
      setState(() {
        final items = [created.item, ...?_list?.items];
        _list = InvitationList(
            inviteCount: created.inviteCount, items: items);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create invitation.')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _delete(Invitation invite) async {
    // Site modal: confirm with the "no refund" warning.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EnclavdColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: EnclavdColors.border)),
        title: const Text('Delete Invitation'),
        content: const Text(
          'Are you sure you want to delete this invitation?\n'
          'Active invitations will not be refunded.',
          style: TextStyle(color: EnclavdColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final count = await _invitations.delete(invite.id);
      if (!mounted) return;
      setState(() {
        _list = InvitationList(
          inviteCount: count,
          items: [
            for (final i in _list?.items ?? const <Invitation>[])
              if (i.id != invite.id) i,
          ],
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Invitation code copied'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
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
    final list = _list!;
    return RefreshIndicator(
      color: EnclavdColors.link,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Create row: the site's button only exists with invites left.
          if (list.inviteCount > 0)
            FilledButton.icon(
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const FaIcon(FontAwesomeIcons.bolt, size: 15),
              label: Text('Create Invite (${list.inviteCount} left)'),
              style: FilledButton.styleFrom(
                backgroundColor: EnclavdColors.primaryButton,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
            ),
          if (list.inviteCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.triangleExclamation,
                      size: 14, color: EnclavdColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "You don't have any invites available",
                      style: TextStyle(
                          color: EnclavdColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (list.items.isEmpty)
            const _EmptyState()
          else
            for (final invite in list.items) ...[
              _InviteCard(
                invite: invite,
                onCopy: () => _copy(invite.code),
                onDelete: invite.deletable ? () => _delete(invite) : null,
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.onCopy,
    required this.onDelete,
  });

  final Invitation invite;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invite.status) {
      'accepted' => const Color(0xFF4ADE80), // green-400
      'expired' => const Color(0xFFF87171), // red-400
      _ => EnclavdColors.warning, // pending
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The site's code chip (secondaryCardColor + mono).
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: EnclavdColors.cardSecondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    invite.code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: EnclavdColors.textPrimary,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const FaIcon(FontAwesomeIcons.copy,
                    size: 14, color: EnclavdColors.link),
                tooltip: 'Copy code',
                visualDensity: VisualDensity.compact,
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const FaIcon(FontAwesomeIcons.trashCan,
                      size: 14, color: EnclavdColors.likeActive),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatusChip(status: invite.status, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Expires: ${formatInviteExpiry(invite.validUntil)}',
                  style: const TextStyle(
                      fontSize: 12.5, color: EnclavdColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The site's status pill (pending yellow / accepted green / expired red).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
          FaIcon(FontAwesomeIcons.ticket,
              size: 30, color: EnclavdColors.link),
          SizedBox(height: 12),
          Text('No Active Invitations',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(
            "You haven't created any invitations yet.",
            textAlign: TextAlign.center,
            style: TextStyle(color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
