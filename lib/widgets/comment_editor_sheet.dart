import 'package:flutter/material.dart';

import '../api/api_client.dart'; // friendlyErrorText
import '../theme/enclavd_theme.dart';

/// Bottom-sheet editor for a comment or a forum reply. The sheet owns the
/// request, so a rejected edit keeps the typed text on screen instead of
/// closing over it. Pops with the saved body, or null when dismissed.
Future<String?> showCommentEditor(
  BuildContext context, {
  required String title,
  required String initialText,
  required Future<void> Function(String) onSubmit,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentEditorSheet(
      title: title,
      initialText: initialText,
      onSubmit: onSubmit,
    ),
  );
}

class _CommentEditorSheet extends StatefulWidget {
  const _CommentEditorSheet({
    required this.title,
    required this.initialText,
    required this.onSubmit,
  });

  final String title;
  final String initialText;
  final Future<void> Function(String) onSubmit;

  @override
  State<_CommentEditorSheet> createState() => _CommentEditorSheetState();
}

class _CommentEditorSheetState extends State<_CommentEditorSheet> {
  // Same cap as the composer; the server clamps at 2000 anyway.
  static const int _limit = 1000;

  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  final FocusNode _focus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Cursor at the end: this is fixing your own text, not retyping it.
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    if (text == widget.initialText.trim()) {
      Navigator.of(context).pop(); // nothing changed
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(text);
      if (!mounted) return;
      Navigator.of(context).pop(text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('commentEditorField'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: _limit,
                  cursorColor: palette.link,
                  style: TextStyle(fontSize: 14, color: palette.textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: palette.background,
                    isDense: true,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: palette.link, width: 2),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: palette.error),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) {
                        final canSave =
                            !_saving && _controller.text.trim().isNotEmpty;
                        return FilledButton(
                          onPressed: canSave ? _save : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.primaryButton,
                            foregroundColor: palette.primaryButtonText,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.primaryButtonText,
                                  ),
                                )
                              : const Text('Save'),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
