import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/messages_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/message_notifications.dart';
import '../services/realtime_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import 'chat_screen.dart';

/// Messages inbox — Instagram-style DM list, port of the site's
/// messages.php conversations sidebar.
///
/// Each row: the other member's avatar (white/10 ring like the site, with
/// the 5-minute online dot), their name (white, semibold), a red unread
/// count badge when the conversation has unread messages, and the latest
/// message preview (truncated, white/60 — 'No messages yet' when empty).
/// Unread rows keep the site's faint highlight (white/[0.05]).
///
/// LIVE path: the inbox joins every conversation's WebSocket room (bounded
/// by the sidecar's per-client room cap) so inbound messages and
/// conversation updates refresh previews + unread badges instantly. A 15s
/// poll remains as the reconcile/fallback — the site's own REST pattern.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    this.messages,
    this.auth,
    this.myUserId,
    this.realtime,
  });

  /// Injected for tests; when null the screen builds its own AppServices.
  final MessagesService? messages;
  final AuthService? auth;
  final int? myUserId;
  final RealtimeService? realtime;

  /// Poll cadence for the inbox while it is visible (WS is primary).
  static const Duration pollInterval = Duration(seconds: 15);

  /// The sidecar caps rooms per client (REALTIME_MAX_ROOMS_PER_CLIENT).
  static const int maxJoinedRooms = 20;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  MessagesService? _messages;
  RealtimeService? _realtime;
  int? _myUserId;

  final List<Conversation> _conversations = [];
  final Set<int> _joinedRooms = {};
  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;
  Timer? _pollTimer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    // In the messages area: suppress message notifications while this is
    // the visible screen (the app-lifecycle check in the service handles
    // the minimized case).
    MessageNotifications.instance?.setMessagesOpen(true);
    _init();
    _pollTimer =
        Timer.periodic(MessagesScreen.pollInterval, (_) => _silentRefresh());
  }

  @override
  void dispose() {
    MessageNotifications.instance?.setMessagesOpen(false);
    _pollTimer?.cancel();
    _realtimeSub?.cancel();
    // Leave every room this screen joined (the pushed ChatScreen leaves
    // its own room when it pops — order is chat first, then us).
    for (final conversationId in _joinedRooms) {
      _realtime?.leave(conversationId);
    }
    super.dispose();
  }

  Future<void> _init() async {
    AppServices? services;
    if (widget.messages == null) {
      services = await AppServices.create();
      if (!mounted) return;
    }
    final messages = widget.messages ?? services!.messages;
    final auth = widget.auth ?? services!.auth;
    final realtime = widget.realtime ?? services!.realtime;

    var myUserId = widget.myUserId;
    if (myUserId == null) {
      try {
        myUserId = (await auth.me())?.id;
      } catch (_) {
        // The inbox itself needs no id; a null id only disables the
        // sent/received split in threads pushed from here.
      }
    }
    if (!mounted) return;
    _messages = messages;
    _realtime = realtime;
    _myUserId = myUserId;
    _realtimeSub = realtime.events.listen(_onRealtime);
    _loadConversations();
  }

  /// Live frames: a message anywhere or a conversation change refreshes
  /// the list (previews + unread counts) instantly.
  void _onRealtime(RealtimeEvent event) {
    if (event.type != 'message' && event.type != 'conversation_update') {
      return;
    }
    _silentRefresh();
  }

  Future<void> _loadConversations() async {
    final messages = _messages;
    if (messages == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = await messages.conversations();
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(conversations);
        _loading = false;
        _loadedOnce = true;
      });
      _joinRooms(conversations);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _error = e.status == 401
            ? 'Session expired. Please log in again.'
            : e.message;
      });
      if (e.status == 401) {
        final services = await AppServices.create();
        await services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _error = 'Failed to load conversations.';
      });
    }
  }

  /// Background poll — new messages surface in previews and unread
  /// badges without user action. Silent on failure.
  Future<void> _silentRefresh() async {
    final messages = _messages;
    if (messages == null || !_loadedOnce) return;
    try {
      final conversations = await messages.conversations();
      if (!mounted) return;
      final changed = conversations.length != _conversations.length ||
          !_samePreviews(conversations);
      if (!changed) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(conversations);
      });
      _joinRooms(conversations);
    } catch (_) {
      // Silent.
    }
  }

  /// Live delivery needs a room subscription per conversation — join every
  /// row the sidecar allows (per-client cap), and any NEW rows the next
  /// refresh brings in. Idempotent.
  void _joinRooms(List<Conversation> conversations) {
    final realtime = _realtime;
    if (realtime == null) return;
    for (final conversation in conversations) {
      if (_joinedRooms.length >= MessagesScreen.maxJoinedRooms) break;
      if (_joinedRooms.add(conversation.id)) {
        realtime.join(conversation.id);
      }
    }
  }

  bool _samePreviews(List<Conversation> fresh) {
    for (var i = 0; i < fresh.length; i++) {
      if (i >= _conversations.length) return false;
      final a = fresh[i];
      final b = _conversations[i];
      if (a.id != b.id ||
          a.lastMessage != b.lastMessage ||
          a.unreadCount != b.unreadCount) {
        return false;
      }
    }
    return true;
  }

  Future<void> _openConversation(Conversation conversation) async {
    final myUserId = _myUserId;
    final messages = _messages;
    final realtime = _realtime;
    if (myUserId == null || messages == null || realtime == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: conversation.id,
          myUserId: myUserId,
          messages: messages,
          realtime: realtime,
          participantId: conversation.participantId,
          participantName: conversation.participantName,
          participantAvatar: conversation.participantAvatar,
          participantPersonality: conversation.participantPersonality,
          participantIsOnline: conversation.isOnline,
        ),
      ),
    );
    // Previews / unread counts changed while chatting — refresh.
    if (mounted) _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        color: EnclavdColors.link,
        child: SafeArea(
          // Gesture-nav phones draw content under the system bar — the
          // last row must stay reachable above it.
          top: false,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && !_loadedOnce) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _ConversationRowSkeleton(),
          _ConversationRowSkeleton(),
          _ConversationRowSkeleton(),
        ],
      );
    }
    if (_error != null && _conversations.isEmpty) {
      return _InboxError(message: _error!, onRetry: _loadConversations);
    }
    if (_conversations.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 140),
          FaIcon(FontAwesomeIcons.paperPlane,
              color: EnclavdColors.textSecondary, size: 56),
          SizedBox(height: 16),
          Text(
            'No conversations yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: EnclavdColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Open a member\u2019s profile and tap Message to start a '
              'conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        return _ConversationRow(
          key: ValueKey(conversation.id),
          conversation: conversation,
          onTap: () => _openConversation(conversation),
        );
      },
    );
  }
}

/// One inbox row (site .conversation-item): avatar + online dot, name +
/// unread badge, latest-message preview; faint highlight while unread.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({super.key, required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount;
    return InkWell(
      onTap: onTap,
      child: Container(
        // Unread rows keep the site's faint highlight (white/[0.05]).
        decoration: BoxDecoration(
          color: unread > 0 ? const Color(0x0DFFFFFF) : Colors.transparent,
          border:
              const Border(bottom: BorderSide(color: EnclavdColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with the site's online dot (green-500 within 5 min).
            Stack(
              children: [
                EnclavdAvatar(
                  size: 40, // w-10 h-10
                  url: resolveAvatarUrl(
                      AppConfig.apiBaseUrl, conversation.participantAvatar),
                  // Site ring: border-white/[0.1] (no personality color).
                  borderColor: EnclavdColors.border,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12, // w-3 h-3
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: conversation.isOnline
                          ? const Color(0xFF22C55E) // bg-green-500
                          : const Color(0xFF6B7280), // bg-gray-500
                      border: Border.all(
                          color: EnclavdColors.background, // border-gray-900
                          width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.participantName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: EnclavdColors.textPrimary,
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w600, // font-semibold
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        // Site badge: bg-red-500 rounded-full, count.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444), // bg-red-500
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11, // text-[11px]
                              fontWeight: FontWeight.w500, // font-medium
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation.lastMessage.isEmpty
                        ? 'No messages yet'
                        : conversation.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0x99FFFFFF), // text-white/60
                      fontSize: 12, // text-xs
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer rows while the inbox loads.
class _ConversationRowSkeleton extends StatelessWidget {
  const _ConversationRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EnclavdColors.divider)),
      ),
      child: const Row(
        children: [
          ShimmerCircle(),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBar(width: 140, height: 14),
                SizedBox(height: 8),
                ShimmerBar(width: 220, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal shimmer primitives (the full shimmer lives in widgets/shimmer.dart
/// with feed-specific sizes; keep the inbox self-contained).
class ShimmerCircle extends StatelessWidget {
  const ShimmerCircle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: EnclavdColors.cardSecondary,
      ),
    );
  }
}

class ShimmerBar extends StatelessWidget {
  const ShimmerBar({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const FaIcon(FontAwesomeIcons.commentSlash,
            color: EnclavdColors.textSecondary, size: 56),
        const SizedBox(height: 16),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EnclavdColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
