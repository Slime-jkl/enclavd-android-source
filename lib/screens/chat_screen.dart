import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/messages_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/message_notifications.dart';
import '../services/realtime_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import '../services/analytics_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.myUserId,
    required this.messages,
    required this.realtime,
    this.participantId,
    this.participantName = '',
    this.participantAvatar,
    this.participantPersonality,
    this.participantIsOnline = false,
  });

  final int conversationId;
  final int myUserId;
  final MessagesService messages;
  final RealtimeService realtime;

  /// The other member; header tap opens their profile.
  final int? participantId;
  final String participantName;
  final String? participantAvatar; // root-relative path
  final String? participantPersonality;
  final bool participantIsOnline;

  /// Reconcile/fallback cadence while the thread is open (WS is primary).
  static const Duration pollInterval = Duration(seconds: 15);

  /// History window size (site parity: 30 per page).
  static const int windowSize = 30;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final Set<int> _visibleTimes = {};
  final _input = TextEditingController();

  bool _loading = true;
  String? _error;
  bool _sending = false;
  Timer? _pollTimer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  int _maxInboundId = 0;

  // History paging: the thread opens on the newest window; older pages
  // load when the reader scrolls to the top.
  bool _hasMore = false;
  bool _loadingOlder = false;
  int? _oldestId;

  // Block state vs the other participant (either side blocks => frozen).
  bool _blockedByMe = false;
  bool _blockedByThem = false;
  bool _busyBlock = false;

  bool _typingPingSent = false;
  Timer? _typingStopTimer;

  bool _otherTyping = false;

  bool get _blocked => _blockedByMe || _blockedByThem;

  @override
  void initState() {
    super.initState();
    trackScreen('/chat');
    // Reading a thread counts as the messages screen being open.
    MessageNotifications.instance?.setMessagesOpen(true);
    _load();
    _pollTimer = Timer.periodic(ChatScreen.pollInterval, (_) => _poll());
    _realtimeSub = widget.realtime.events.listen(_onRealtime);
    widget.realtime.join(widget.conversationId);
  }

  @override
  void dispose() {
    MessageNotifications.instance?.setMessagesOpen(false);
    _pollTimer?.cancel();
    _typingStopTimer?.cancel();
    _realtimeSub?.cancel();
    // The site's blur handler stops the ping on leaving.
    if (_typingPingSent) {
      widget.realtime.sendTyping(widget.conversationId, false);
    }
    widget.realtime.leave(widget.conversationId);
    _input.dispose();
    super.dispose();
  }

  void _onRealtime(RealtimeEvent event) {
    if (event.conversationId != widget.conversationId) return;
    switch (event.type) {
      case 'message':
        _onLiveMessage(event);
      case 'read':
        _onLiveRead(event);
      case 'typing':
        final typing = event.isTyping;
        if (mounted && typing != _otherTyping) {
          setState(() => _otherTyping = typing);
        }
      case 'message_deleted':
        _onLiveDeleted(event);
      case 'conversation_blocked':
        _onLiveBlocked(event);
    }
  }

  void _onLiveMessage(RealtimeEvent event) {
    final messageId = event.messageId;
    final senderId = event.senderId;
    if (messageId == null ||
        messageId <= 0 ||
        senderId == null ||
        senderId == widget.myUserId) {
      return;
    }
    if (_messages.any((m) => m.id == messageId)) return; // dedupe
    final live = ChatMessage(
      id: messageId,
      conversationId: widget.conversationId,
      senderId: senderId,
      senderName: '',
      message: event.message,
      isRead: null,
      createdAt: event.data['timestamp'] as String? ?? _nowDbString(),
    );
    if (!mounted) return;
    // Merge BEFORE clearing: an inline merge in the cascade reads the
    // cleared list and drops the whole thread.
    final merged = _merge([live]);
    setState(() {
      _messages
        ..clear()
        ..addAll(merged);
    });
    // Our inbox badge clears server-side only via mark_read.
    _markReadIfNeeded([live]);
  }

  // The other participant deleted a message for everyone: swap the
  // bubble for the tombstone. (The actor's own sockets are excluded from
  // the fan-out, so this only ever touches inbound messages here.)
  void _onLiveDeleted(RealtimeEvent event) {
    final messageId = event.messageId;
    if (messageId == null || messageId <= 0) return;
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || !mounted) return;
    final m = _messages[index];
    setState(() {
      _messages[index] = ChatMessage(
        id: m.id,
        conversationId: m.conversationId,
        senderId: m.senderId,
        senderName: m.senderName,
        message: '',
        isRead: true,
        deletedForEveryone: true,
        createdAt: m.createdAt,
      );
    });
  }

  // Block state flipped on the other side (the blocker's own UI already
  // updated from its request response; the fan-out excludes the actor).
  void _onLiveBlocked(RealtimeEvent event) {
    final actorId = event.actorId;
    if (actorId == null || actorId == widget.myUserId) return;
    if (!mounted) return;
    setState(() => _blockedByThem = event.blocked);
  }

  void _onLiveRead(RealtimeEvent event) {
    final readerId = event.readerId;
    if (readerId == null || readerId == widget.myUserId) return;
    if (!_messages.any((m) => m.isFrom(widget.myUserId) && m.isRead != true)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.isFrom(widget.myUserId) && m.isRead != true) {
          _messages[i] = ChatMessage(
            id: m.id,
            conversationId: m.conversationId,
            senderId: m.senderId,
            senderName: m.senderName,
            message: m.message,
            isRead: true,
            deletedForEveryone: m.deletedForEveryone,
            createdAt: m.createdAt,
          );
        }
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.messages.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasMore;
        _oldestId = page.messages.isEmpty ? null : page.messages.first.id;
        _blockedByMe = page.blockedByMe;
        _blockedByThem = page.blockedByThem;
        _loading = false;
      });
      _markReadIfNeeded(page.messages);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.status == 403
            ? 'You are not part of this conversation.'
            : e.message;
      });
      if (e.status == 401) {
        // Session died; back to login like every other screen.
        final services = await AppServices.create();
        await services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load messages.';
      });
    }
  }

  List<ChatMessage> _merge(List<ChatMessage> fresh) {
    final byId = <int, ChatMessage>{for (final m in fresh) m.id: m};
    final merged = [..._messages];
    for (var i = 0; i < merged.length; i++) {
      final replacement = byId[merged[i].id];
      if (replacement != null) merged[i] = replacement;
    }
    final known = merged.map((m) => m.id).toSet();
    merged.addAll(fresh.where((m) => !known.contains(m.id)));
    merged.sort((a, b) => a.id.compareTo(b.id));
    return merged;
  }

  Future<void> _poll() async {
    try {
      final page = await widget.messages.messages(widget.conversationId);
      if (!mounted) return;
      final countBefore = _messages.length;
      final merged = _merge(page.messages);
      final flagsChanged = page.blockedByMe != _blockedByMe ||
          page.blockedByThem != _blockedByThem;
      if (merged.length == countBefore &&
          !_receiptsChanged(merged) &&
          !flagsChanged) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(merged);
        _blockedByMe = page.blockedByMe;
        _blockedByThem = page.blockedByThem;
      });
      // Older-page state is owned by the load/load-older cursors; the
      // poll only reconciles the newest window and receipts.
      if (merged.length > countBefore) _markReadIfNeeded(page.messages);
    } catch (_) {
      // Silent.
    }
  }

  // One older window (before the oldest loaded id), appended at the top
  // of the thread. Reverse list: the top IS the oldest end.
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore) return;
    final beforeId = _oldestId;
    if (beforeId == null) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await widget.messages.messages(
        widget.conversationId,
        beforeId: beforeId,
      );
      if (!mounted) return;
      setState(() {
        if (page.messages.isEmpty) {
          _hasMore = false;
        } else {
          _messages.insertAll(0, page.messages); // older ids sort first
          _oldestId = page.messages.first.id;
          _hasMore = page.hasMore;
        }
        _loadingOlder = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  bool _receiptsChanged(List<ChatMessage> merged) {
    if (merged.length != _messages.length) return true;
    for (var i = 0; i < merged.length; i++) {
      if (merged[i].isRead != _messages[i].isRead) return true;
      if (merged[i].deletedForEveryone != _messages[i].deletedForEveryone) {
        return true;
      }
    }
    return false;
  }

  void _markReadIfNeeded(List<ChatMessage> history) {
    final newInbound = history
        .where((m) => m.senderId != widget.myUserId && m.id > _maxInboundId);
    if (newInbound.isEmpty) return;
    _maxInboundId =
        newInbound.fold<int>(_maxInboundId, (m, x) => x.id > m ? x.id : m);
    widget.messages.markRead(widget.conversationId).catchError((_) {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _blocked) return;
    _input.clear();
    _stopTypingPing(); // sending, no longer typing
    setState(() => _sending = true);
    try {
      final messageId = await widget.messages.send(widget.conversationId, text);
      if (!mounted) return;
      // Server-authoritative append; the next poll replaces it with the DB row.
      final sent = ChatMessage(
        id: messageId,
        conversationId: widget.conversationId,
        senderId: widget.myUserId,
        senderName: '',
        message: text,
        isRead: false,
        createdAt: _nowDbString(),
      );
      // Same merge-before-clear rule as _onLiveMessage.
      final merged = _merge([sent]);
      setState(() {
        _messages
          ..clear()
          ..addAll(merged);
        _sending = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _input.text = text; // restore, like the site's send failure path
      setState(() => _sending = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      _input.text = text;
      setState(() => _sending = false);
      _toast('Could not send the message. Please try again.');
    }
  }

  // ── Delete for me / for everyone ───────────────────────────────────
  Future<void> _deleteMessage(ChatMessage message, String scope) async {
    if (scope == 'everyone') {
      final ok = await _confirm(
        'Delete for everyone?',
        'This removes the message for both of you. This cannot be undone.',
      );
      if (ok != true || !mounted) return;
    }
    try {
      await widget.messages.deleteMessage(message.id, scope: scope);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
      return;
    } catch (_) {
      if (mounted) _toast('Could not delete the message. Please try again.');
      return;
    }
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index < 0) return;
      if (scope == 'everyone') {
        // The server keeps a tombstone; mirror it in place.
        _messages[index] = ChatMessage(
          id: message.id,
          conversationId: message.conversationId,
          senderId: message.senderId,
          senderName: message.senderName,
          message: '',
          isRead: true,
          deletedForEveryone: true,
          createdAt: message.createdAt,
        );
      } else {
        _messages.removeAt(index);
      }
    });
  }

  void _showMessageActions(ChatMessage message) {
    final isMine = message.isFrom(widget.myUserId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMine)
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.trash,
                    color: Color(0xFFF87171)),
                title: const Text('Delete for everyone',
                    style: TextStyle(color: Color(0xFFF87171))),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _deleteMessage(message, 'everyone');
                },
              ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.trash,
                  color: EnclavdColors.textSecondary),
              title: const Text('Delete for me',
                  style: TextStyle(color: EnclavdColors.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteMessage(message, 'me');
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // ── Block / unblock ───────────────────────────────────────────────
  Future<void> _toggleBlock() async {
    if (_busyBlock) return;
    final name = widget.participantName.isEmpty ? 'this user' : widget.participantName;
    final blocking = !_blockedByMe;
    final ok = await _confirm(
      blocking ? 'Block $name?' : 'Unblock $name?',
      blocking
          ? 'They will not be able to send you messages until you unblock.'
          : 'Messages will work again once unblocked.',
    );
    if (ok != true || !mounted) return;
    setState(() => _busyBlock = true);
    try {
      if (blocking) {
        await widget.messages.block(widget.conversationId);
      } else {
        await widget.messages.unblock(widget.conversationId);
      }
      if (!mounted) return;
      setState(() {
        _blockedByMe = blocking;
        _busyBlock = false;
      });
      if (blocking) {
        _toast('$name is blocked');
      } else {
        _toast('$name is unblocked');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyBlock = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyBlock = false);
      _toast('Could not ${blocking ? 'block' : 'unblock'} $name.');
    }
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EnclavdColors.card,
        title: Text(title, style: const TextStyle(color: EnclavdColors.textPrimary)),
        content: Text(body, style: const TextStyle(color: EnclavdColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: EnclavdColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('OK', style: TextStyle(color: EnclavdColors.link)),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openParticipant() {
    final id = widget.participantId;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProfileScreen(userId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.participantName;
    final blocked = _blocked;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (widget.participantAvatar != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: EnclavdAvatar(
                  size: 32,
                  url: resolveAvatarUrl(
                      AppConfig.apiBaseUrl, widget.participantAvatar!),
                  borderColor:
                      PersonalityColors.forType(widget.participantPersonality),
                ),
              ),
            Expanded(
              child: InkWell(
                onTap: _openParticipant,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? 'Conversation' : name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: EnclavdColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      blocked
                          ? '- blocked'
                          : (widget.participantIsOnline ? '- online' : '- offline'),
                      style: TextStyle(
                        fontSize: 12,
                        color: blocked
                            ? const Color(0xFFF87171)
                            : (widget.participantIsOnline
                                ? const Color(0xFF4ADE80) // green-400
                                : const Color(0xFF9CA3AF)), // gray-400
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('block-button'),
            tooltip: _blockedByMe ? 'Unblock user' : 'Block user',
            onPressed: _busyBlock ? null : _toggleBlock,
            icon: FaIcon(
              _blockedByMe
                  ? FontAwesomeIcons.userCheck
                  : FontAwesomeIcons.userSlash,
              size: 18,
              color: _blockedByMe
                  ? const Color(0xFFF87171)
                  : EnclavdColors.textSecondary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        // Gesture-nav phones draw under the system bar; the input bar clears it.
        top: false,
        child: Column(
          children: [
            if (blocked) _buildBlockedBanner(),
            Expanded(child: _buildThread()),
            _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedBanner() {
    final name =
        widget.participantName.isEmpty ? 'this user' : widget.participantName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: const Color(0x1FEF4444), // red-500/12
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.ban, size: 13, color: Color(0xFFFCA5A5)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _blockedByMe
                  ? 'You blocked $name. Messages are paused until you unblock.'
                  : "You can't send messages to $name.",
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFFCA5A5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThread() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: EnclavdColors.link),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_messages.isEmpty) {
      // Fresh conversation: no history yet.
      return const SizedBox.shrink();
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Reverse list: offset 0 is the newest message at the bottom;
        // the top (oldest end) is maxScrollExtent. Load one window early.
        final metrics = notification.metrics;
        if (metrics.maxScrollExtent > 0 &&
            metrics.pixels >= metrics.maxScrollExtent - 120) {
          _loadOlder();
        }
        return false;
      },
      child: ListView.builder(
        reverse: true, // index 0 = newest; a reader at the bottom stays pinned
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: _messages.length + (_loadingOlder ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            // Older-page fetch in flight (rendered at the top end).
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: EnclavdColors.link),
                ),
              ),
            );
          }
          // Key by message id so merges never reuse a bubble's element
          // for another message.
          final message = _messages[_messages.length - 1 - index];
          return _MessageBubble(
            key: ValueKey(message.id),
            message: message,
            isMine: message.isFrom(widget.myUserId),
            showTime: _visibleTimes.contains(message.id),
            onTap: () {
              setState(() {
                if (!_visibleTimes.add(message.id)) {
                  _visibleTimes.remove(message.id);
                }
              });
            },
            onLongPress: message.deletedForEveryone
                ? null
                : () => _showMessageActions(message),
          );
        },
      ),
    );
  }

  void _onInputChanged(String _) {
    if (_input.text.trim().isNotEmpty && !_typingPingSent && !_blocked) {
      _typingPingSent = true;
      widget.realtime.sendTyping(widget.conversationId, true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 3), _stopTypingPing);
  }

  void _stopTypingPing() {
    _typingStopTimer?.cancel();
    if (_typingPingSent) {
      _typingPingSent = false;
      widget.realtime.sendTyping(widget.conversationId, false);
    }
  }

  Widget _buildTypingIndicator() {
    if (!_otherTyping) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: const Text(
        'Typing...',
        style: TextStyle(
          fontSize: 12, // text-xs
          fontStyle: FontStyle.italic,
          color: Color(0xCC93C5FD), // text-blue-300/80
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final blocked = _blocked;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0x4D000000), // black/30 (site bg-black/[0.3])
        border: Border(top: BorderSide(color: EnclavdColors.divider)),
      ),
      child: Opacity(
        opacity: blocked ? 0.55 : 1,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_loading && !blocked,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: _onInputChanged,
                onSubmitted: (_) => _send(),
                // No autofillHints: they detach the IME on Android.
                style: const TextStyle(
                    color: EnclavdColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: blocked
                      ? 'Messages paused'
                      : 'Type your message...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  filled: true,
                  fillColor: const Color(0x0DFFFFFF), // white/[0.05]
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                    borderSide:
                        const BorderSide(color: EnclavdColors.border), // white/10
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: EnclavdColors.link, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button: icon-only paper-plane.
            SizedBox(
              width: 44,
              height: 44,
              child: ElevatedButton(
                key: const ValueKey('send-button'),
                onPressed: (_sending || _loading || blocked) ? null : _send,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: EnclavdColors.primaryButton,
                  foregroundColor: EnclavdColors.primaryButtonText,
                  disabledBackgroundColor:
                      EnclavdColors.primaryButton.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const FaIcon(FontAwesomeIcons.paperPlane, size: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showTime,
    required this.onTap,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showTime;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.7; // site max-w 70%
    final tombstone = message.deletedForEveryone;
    final bubbleText = tombstone
        ? (isMine ? 'You deleted this message' : 'This message was deleted')
        : message.message;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Sent: rgba(30,58,138,0.8); received: rgba(255,255,255,0.1);
        // tombstones keep a faint shell so the row reads as a placeholder.
        color: isMine
            ? (tombstone ? const Color(0x661E3A8A) : const Color(0xCC1E3A8A))
            : (tombstone ? const Color(0x0AFFFFFF) : const Color(0x1AFFFFFF)),
        borderRadius: BorderRadius.only(
          // Site: 1.5rem with the sender-side corner 0.5rem.
          topLeft: Radius.circular(isMine ? 24 : 8),
          topRight: Radius.circular(isMine ? 8 : 24),
          bottomLeft: const Radius.circular(24),
          bottomRight: const Radius.circular(24),
        ),
      ),
      child: Text(
        bubbleText,
        style: TextStyle(
          color: isMine
              ? (tombstone
                  ? const Color(0x80FFFFFF)
                  : Colors.white)
              : (tombstone
                  ? const Color(0x66E2E8F0)
                  : const Color(0xFFE2E8F0)), // slate-200 (site received text)
          fontSize: 15,
          height: 1.3,
          fontStyle: tombstone ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );

    final timeLine = showTime
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              formatMessageTime(message.createdAt),
              style: const TextStyle(
                fontSize: 10, // 0.625rem (site .message-time)
                color: Color(0x99FFFFFF), // white/60
              ),
            ),
          )
        : const SizedBox.shrink();

    // Tap = toggle the timestamp (site parity); long-press = actions
    // (delete for me / for everyone). Tombstones only toggle the time.
    final gesture = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: bubble,
    );

    if (isMine) {
      // Check = sent, double-check blue-400 = seen. Tombstones carry no
      // receipts (the row was cleared server-side).
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: gesture),
                const SizedBox(width: 5),
                if (!tombstone)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: FaIcon(
                      message.isRead == true
                          ? FontAwesomeIcons.checkDouble
                          : FontAwesomeIcons.check,
                      key: ValueKey('receipt-${message.id}'),
                      size: 11,
                      color: message.isRead == true
                          ? const Color(0xFF60A5FA) // blue-400 (seen)
                          : const Color(0x99FFFFFF), // white/60 (sent)
                    ),
                  ),
              ],
            ),
            timeLine,
          ],
        ),
      );
    }
    // Received.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gesture,
          timeLine,
        ],
      ),
    );
  }
}

/// Local DB-style UTC timestamp; the next poll replaces it with the server row.
String _nowDbString() {
  final t = DateTime.now().toUtc();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${p(t.month)}-${p(t.day)} '
      '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
}

/// Root-relative avatar path -> absolute URL.
String resolveAvatarUrl(String base, String path) =>
    path.startsWith('/') ? '$base$path' : path;
