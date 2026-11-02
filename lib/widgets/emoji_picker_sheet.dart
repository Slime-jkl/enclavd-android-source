import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme/enclavd_theme.dart';
import '../utils/emoji_names.dart';
import 'animated_emoji.dart';

/// Opens the animated emoji sheet. The sheet only returns a name; the caller
/// inserts it, so the cursor lands where it was before the keyboard closed.
Future<void> showEmojiPickerSheet(
  BuildContext context, {
  required TextEditingController controller,
  FocusNode? focusNode,
  int maxLength = 20000,
}) async {
  focusNode?.unfocus();
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _EmojiPickerSheet(),
  );
  if (picked != null) {
    insertEmojiShortcode(controller, picked, maxLength: maxLength);
  }
  focusNode?.requestFocus();
}

/// Inserts `:name:` at the selection, padded with one space unless the text
/// that follows already starts with whitespace (same rule as the site).
void insertEmojiShortcode(
  TextEditingController controller,
  String name, {
  int maxLength = 20000,
}) {
  final text = controller.text;
  final selection = controller.selection;
  final start =
      selection.isValid ? selection.start.clamp(0, text.length) : text.length;
  final end =
      selection.isValid ? selection.end.clamp(0, text.length) : text.length;
  final code = ':$name:';
  // Shortcodes only tokenize between boundaries, so pad a side that is glued
  // to a word (the site only pads on the right, which can strand the code).
  final prev = start > 0 ? text.substring(start - 1, start) : '';
  final next = end < text.length ? text.substring(end, end + 1) : '';
  final lead = prev.isEmpty || RegExp(r'\s').hasMatch(prev) ? '' : ' ';
  final tail = next.isEmpty || RegExp(r'\s').hasMatch(next) ? '' : ' ';
  final insert = '$lead$code$tail';
  final updated = text.replaceRange(start, end, insert);
  if (updated.length > maxLength) return;
  controller.value = TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet();

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _names => _query.isEmpty
      ? emojiNames
      : emojiNames.where((n) => n.contains(_query)).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Container(
      height: MediaQuery.of(context).size.height * 0.62,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.faceSmile,
                      size: 16, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Emoji',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_names.length}',
                    style:
                        TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 14, color: palette.textPrimary),
                cursorColor: palette.link,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search emoji',
                  hintStyle:
                      TextStyle(color: palette.textSecondary, fontSize: 14),
                  filled: true,
                  fillColor: palette.background,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            ),
            Expanded(
              child: _names.isEmpty
                  ? Center(
                      child: Text(
                        'No emoji match',
                        style: TextStyle(
                            fontSize: 13, color: palette.textSecondary),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      // Only a couple of rows of animation stay alive
                      // ahead of the viewport; the rest parse on scroll.
                      scrollCacheExtent: const ScrollCacheExtent.pixels(160),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: _names.length,
                      itemBuilder: (context, i) {
                        final name = _names[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.of(context).pop(name),
                          child: Center(
                            child: AnimatedEmoji(name: name, size: 30),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The smiley trigger used by every composer. Opens the sheet and inserts at
/// the cursor of [controller].
class EmojiPickerButton extends StatelessWidget {
  const EmojiPickerButton({
    super.key,
    required this.controller,
    this.focusNode,
    this.maxLength = 20000,
    this.size = 20,
    this.tooltip = 'Emoji',
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final int maxLength;
  final double size;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => showEmojiPickerSheet(
        context,
        controller: controller,
        focusNode: focusNode,
        maxLength: maxLength,
      ),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: FaIcon(
        FontAwesomeIcons.faceSmile,
        size: size,
        color: context.enclavd.textSecondary,
      ),
    );
  }
}
