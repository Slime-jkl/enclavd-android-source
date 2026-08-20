import 'dart:io';

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

/// Post composer — port of the site's post_form.php / edit modal.
///
/// Create mode: text (500 max, live "N/500 characters" counter) + optional
/// image (fa-image → gallery, compressed at pick time to 1600px/q80 like the
/// site's ied editor; preview with fa-xmark remove; server requires text OR
/// image). Submit = fa-paper-plane "Post".
///
/// Edit mode: content prefilled, image shown read-only (the api/v1 update
/// action only replaces content — the gallery row is untouched). Submit =
/// fa-save "Save".
///
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
  XFile? _image;
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
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80, // ied-equivalent compression (JPEG)
    );
    if (picked == null || !mounted) return;
    setState(() => _image = picked);
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
        _error = e.toString().replaceFirst('ApiException', 'Error');
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
              TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 3,
                maxLines: 8,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:
                      _isEdit ? 'Edit your post…' : "What's on your mind?",
                  // Mirrors post_form.php's "N/500 characters" (textSecondary,
                  // bottom-right).
                  counter: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) => Text(
                          '${value.text.characters.length}/500 characters',
                          style: const TextStyle(
                              color: EnclavdColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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
                        onRemove: () => setState(() => _image = null))
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
}

/// Picked-image preview (site: max-h-300 object-contain rounded + × remove).
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image.file(File(path),
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
