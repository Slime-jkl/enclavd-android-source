import 'dart:io';
import 'dart:typed_data';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_image.dart';
import 'image_editor_screen.dart';

/// Post composer — port of the site's post_form.php / edit modal.
///
/// Create mode: text (2000 max, live "N/2000 characters" counter) + optional
/// image (fa-image → gallery → the image editor for crop/resize/filters —
/// ied port — then preview with fa-xmark remove; server requires text OR
/// image). Submit = fa-paper-plane "Post".
///
/// Edit mode: content prefilled, image shown read-only (the api/v1 update
/// action only replaces content — the gallery row is untouched). Submit =
/// fa-floppy-disk "Save".
///
/// The composer input is a plain multiline field (Instagram/Facebook-style)
/// — no highlight-while-typing; the container draws the box, and no focus
/// outline is drawn. #hashtags/links still render blue in the feed cards.
/// Pops with `true` on success so the caller refreshes.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.post});

  /// Null = create a new post; set = edit that post's content.
  final Post? post;

  static const routeName = '/compose';

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  /// The attached image: an XFile from the picker OR the editor's baked
  /// output (in-memory bytes; [bytes] non-null then).
  XFile? _image;
  Uint8List? _imageBytes; // set when _image came from the editor

  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.post?.content ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    // The editor bakes a bounded JPEG (≤1200px, q85) — this also guarantees
    // a small upload payload regardless of what the picker returned (the
    // Android photo picker ignores maxWidth/imageQuality, which previously
    // let multi-MB originals through and blew past the server's
    // post_max_size).
    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
          builder: (_) => ImageEditorScreen(imagePath: picked.path)),
    );
    if (!mounted) return;
    if (edited == null) return; // cancelled in the editor

    setState(() {
      _image =
          XFile.fromData(edited, name: 'edited.jpg', mimeType: 'image/jpeg');
      _imageBytes = edited;
    });
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    final post = widget.post;
    if (!_isEdit && content.isEmpty && _image == null) {
      setState(() => _error = 'Write something or add an image.');
      return;
    }
    if (_isEdit && content.isEmpty) {
      setState(() => _error = 'Post content cannot be empty.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final services = await AppServices.create();
      if (_isEdit) {
        await services.posts.updatePost(
          postId: post!.id,
          content: content,
          originalContent: post.content,
        );
      } else {
        await services.posts.createPost(content: content, image: _image);
        // Site: action_sound when a new post is successfully created.
        SoundService.instance.action();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Post' : 'Create Post')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _composerField(),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF87171).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFF87171).withValues(alpha: 0.25)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFF87171), fontSize: 13)),
                ),
              ],
              const SizedBox(height: 16),
              // Image area: picker + preview in create mode, read-only
              // existing image in edit mode.
              if (!_isEdit)
                _image != null
                    ? _ImagePreview(
                        path: _image!.path,
                        bytes: _imageBytes,
                        onRemove: () => setState(() {
                          _image = null;
                          _imageBytes = null;
                        }),
                      )
                    : OutlinedButton.icon(
                        onPressed: _busy ? null : _pickImage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: EnclavdColors.textPrimary,
                          side: const BorderSide(color: EnclavdColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const FaIcon(FontAwesomeIcons.image,
                            size: 16, color: EnclavdColors.textSecondary),
                        label: const Text('Add Image'),
                      )
              else if (post?.image != null && post!.image!.isNotEmpty)
                // Existing post image — shown, not replaceable (update
                // action only edits content).
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: EnclavdImage(
                      resolveMediaUrl(AppConfig.apiBaseUrl,
                          galleryName: post.image),
                      fit: BoxFit.contain,
                      height: 220,
                      placeholderHeight: 180,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : FaIcon(
                        _isEdit
                            ? FontAwesomeIcons.floppyDisk
                            : FontAwesomeIcons.paperPlane,
                        size: 15,
                        color: Colors.white,
                      ),
                label: Text(_busy
                    ? (_isEdit ? 'Saving…' : 'Posting…')
                    : (_isEdit ? 'Save' : 'Post')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The composer input — a plain multiline field like Instagram/Facebook:
  /// visible white text, the Container draws the box, and NO focus outline
  /// (the theme's blue focusedBorder is suppressed on every state).
  /// #hashtags/links are NOT highlighted while typing (feed rendering is
  /// unaffected — that happens in the post cards).
  Widget _composerField() {
    const base = TextStyle(
      color: EnclavdColors.textPrimary,
      fontSize: 16,
      height: 1.5,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            minLines: 3,
            maxLines: 8,
            // Hard 2000-char cap (the site's MAX_CHARS / api limit) — the
            // counter below mirrors the site's "N/2000 characters".
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            style: base,
            cursorColor: EnclavdColors.textPrimary,
            decoration: const InputDecoration(
              // The container draws the box — the theme's decoration must
              // not leak in, and CRUCIALLY no focusedBorder: the global
              // inputDecorationTheme's blue OutlineInputBorder is what
              // drew the unwanted blue outline on focus.
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              counterText: '',
              hintText: 'Write post..', // the site's Quill placeholder
              hintStyle: TextStyle(color: EnclavdColors.textSecondary),
              // Zero padding — the container's (14,12) padding positions
              // the text; any extra shifts the text vs. the cursor.
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 4),
          // Mirrors post_form.php's "N/2000 characters" (textSecondary, right).
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => Text(
                '${value.text.characters.length}/2000 characters',
                style: const TextStyle(
                    color: EnclavdColors.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picked/edited image preview (site: max-h-300 object-contain rounded +
/// × remove). Shows editor bytes when present, else the picker file.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.path,
    required this.bytes,
    required this.onRemove,
  });

  final String? path;
  final Uint8List? bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: bytes != null
                ? Image.memory(bytes!,
                    fit: BoxFit.contain, width: double.infinity)
                : Image.file(File(path!),
                    fit: BoxFit.contain, width: double.infinity),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const FaIcon(FontAwesomeIcons.xmark,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
