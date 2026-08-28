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

  bool _typingPingSent = false;
  Timer? _typingStopTimer;

  bool _otherTyping = false;

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
      final history = await widget.messages.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      _markReadIfNeeded(history);
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
      final fresh = await widget.messages.messages(widget.conversationId);
      if (!mounted) return;
      final countBefore = _messages.length;
      final merged = _merge(fresh);
      if (merged.length == countBefore && !_receiptsChanged(merged)) return;
      setState(() => _messages
        ..clear()
        ..addAll(merged));
      if (merged.length > countBefore) _markReadIfNeeded(fresh);
    } catch (_) {
      // Silent.
    }
  }

  bool _receiptsChanged(List<ChatMessage> merged) {
    if (merged.length != _messages.length) return true;
    for (var i = 0; i < merged.length; i++) {
      if (merged[i].isRead != _messages[i].isRead) return true;
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
    if (text.isEmpty || _sending) return;
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
                      widget.participantIsOnline ? '- online' : '- offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.participantIsOnline
                            ? const Color(0xFF4ADE80) // green-400
                            : const Color(0xFF9CA3AF), // gray-400
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        // Gesture-nav phones draw under the system bar; the input bar clears it.
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildThread()),
            _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
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
    return ListView.builder(
      reverse: true, // index 0 = newest; a reader at the bottom stays pinned
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
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
        );
      },
    );
  }

  void _onInputChanged(String _) {
    if (_input.text.trim().isNotEmpty && !_typingPingSent) {
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0x4D000000), // black/30 (site bg-black/[0.3])
        border: Border(top: BorderSide(color: EnclavdColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_loading,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onChanged: _onInputChanged,
              onSubmitted: (_) => _send(),
              // No autofillHints: they detach the IME on Android.
              style: const TextStyle(
                  color: EnclavdColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Type your message...',
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
              onPressed: (_sending || _loading) ? null : _send,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: EnclavdColors.primaryButton,
                foregroundColor: Colors.white,
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
  });

  final ChatMessage message;
  final bool isMine;
  final bool showTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.7; // site max-w 70%
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Sent: rgba(30,58,138,0.8); received: rgba(255,255,255,0.1).
        color: isMine
            ? const Color(0xCC1E3A8A)
            : const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.only(
          // Site: 1.5rem with the sender-side corner 0.5rem.
          topLeft: Radius.circular(isMine ? 24 : 8),
          topRight: Radius.circular(isMine ? 8 : 24),
          bottomLeft: const Radius.circular(24),
          bottomRight: const Radius.circular(24),
        ),
      ),
      child: Text(
        message.message,
        style: TextStyle(
          color: isMine
              ? Colors.white
              : const Color(0xFFE2E8F0), // slate-200 (site received text)
          fontSize: 15,
          height: 1.3,
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

    if (isMine) {
      // Check = sent, double-check blue-400 = seen.
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: GestureDetector(onTap: onTap, child: bubble)),
                const SizedBox(width: 5),
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
          GestureDetector(onTap: onTap, child: bubble),
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
