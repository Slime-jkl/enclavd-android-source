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
import '../utils/image_bake.dart';
import '../utils/submit_lock.dart';
import '../widgets/enclavd_image.dart';
import 'image_editor_screen.dart';
import '../services/analytics_service.dart';

/// One attached slide: the baked bytes that get uploaded, plus the picked
/// file they came from so the editor can re-open it.
class _ComposeSlide {
  _ComposeSlide({required this.baked, this.sourcePath});

  Uint8List baked;
  final String? sourcePath;
}

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.post, this.pickImages});

  /// Null = create a new post; set = edit that post's content.
  final Post? post;

  /// Test seam: replaces the platform picker.
  final Future<List<XFile>> Function()? pickImages;

  static const routeName = '/compose';

  /// Slides one post may carry (the server's cap).
  static const int maxImages = 6;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  final List<_ComposeSlide> _slides = [];
  bool _baking = false;

  bool _busy = false;
  // One attempt at a time plus a cooldown (site: the post button locks
  // for 5s), so a spam tap cannot publish twice.
  final _submitLock = SubmitLock();
  String? _error;

  bool get _isEdit => widget.post != null;

  bool get _canAddMore => _slides.length < ComposeScreen.maxImages;

  @override
  void initState() {
    super.initState();
    trackScreen('/compose');
    _controller = TextEditingController(text: widget.post?.content ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _submitLock.dispose();
    super.dispose();
  }

  /// Picks one or more images and bakes each one. A single first image still
  /// goes straight into the editor; the rest land in the strip, where a tap
  /// re-opens the editor for that slide.
  Future<void> _pickImages() async {
    if (_busy || _baking) return;

    final picked = await (widget.pickImages ?? _pickFromGallery)();
    if (picked.isEmpty || !mounted) return;

    if (_slides.length + picked.length > ComposeScreen.maxImages) {
      setState(() => _error =
          'Up to ${ComposeScreen.maxImages} images per post.');
      return;
    }

    setState(() {
      _baking = true;
      _error = null;
    });

    try {
      final baked = <_ComposeSlide>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        baked.add(_ComposeSlide(
          baked: bakePickedBytes(bytes),
          sourcePath: file.path,
        ));
      }
      if (!mounted) return;
      setState(() {
        _baking = false;
        _slides.addAll(baked);
      });
      // The single-image flow behaves exactly as before: pick, then edit.
      if (baked.length == 1 && _slides.length == 1) {
        await _editSlide(0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _baking = false;
        _error = 'Could not read that image.';
      });
    }
  }

  static Future<List<XFile>> _pickFromGallery() =>
      ImagePicker().pickMultiImage();

  Future<void> _editSlide(int index) async {
    final slide = _slides[index];
    final path = slide.sourcePath;
    if (path == null) return;

    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => ImageEditorScreen(imagePath: path)),
    );
    if (edited == null || !mounted) return; // cancelled in the editor

    setState(() {
      _slides[index] = _ComposeSlide(baked: edited, sourcePath: path);
    });
  }

  void _removeSlide(int index) {
    setState(() => _slides.removeAt(index));
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    final post = widget.post;
    if (!_isEdit && content.isEmpty && _slides.isEmpty) {
      setState(() => _error = 'Write something or add an image.');
      return;
    }
    if (_isEdit && content.isEmpty) {
      setState(() => _error = 'Post content cannot be empty.');
      return;
    }
    if (!_submitLock.begin()) return; // in flight, or cooling down

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
        await services.posts.createPost(
          content: content,
          images: [
            for (final slide in _slides)
              XFile.fromData(slide.baked,
                  name: 'edited.jpg', mimeType: 'image/jpeg'),
          ],
        );
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
    } finally {
      // Cooldown on the way out of every attempt.
      _submitLock.end(_onSubmitLockFree);
    }
  }

  void _onSubmitLockFree() {
    if (mounted) setState(() {});
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
              // existing images in edit mode.
              if (!_isEdit) ...[
                if (_slides.length == 1)
                  _ImagePreview(
                    path: _slides.first.sourcePath,
                    bytes: _slides.first.baked,
                    onRemove: () => _removeSlide(0),
                  )
                else if (_slides.length > 1)
                  _ImageStrip(
                    slides: _slides,
                    onEdit: _editSlide,
                    onRemove: _removeSlide,
                  ),
                if (_slides.isEmpty || _canAddMore) ...[
                  if (_slides.isNotEmpty) const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: (_busy || _baking) ? null : _pickImages,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.enclavd.textPrimary,
                      side: BorderSide(color: context.enclavd.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _baking
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.enclavd.textSecondary),
                          )
                        : FaIcon(FontAwesomeIcons.image,
                            size: 16, color: context.enclavd.textSecondary),
                    label: Text(_baking
                        ? 'Preparing...'
                        : (_slides.isEmpty ? 'Add Image' : 'Add More')),
                  ),
                ],
              ] else if (post != null && post.galleryImages.isNotEmpty) ...[
                _ReadOnlyImages(post: post),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: (_busy || _baking || _submitLock.locked)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.enclavd.primaryButtonText),
                      )
                    : FaIcon(
                        _isEdit
                            ? FontAwesomeIcons.floppyDisk
                            : FontAwesomeIcons.paperPlane,
                        size: 15,
                        color: context.enclavd.primaryButtonText,
                      ),
                label: Text(_busy
                    ? (_isEdit ? 'Saving...' : 'Posting...')
                    : (_isEdit ? 'Save' : 'Post')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerField() {
    final base = TextStyle(
      color: context.enclavd.textPrimary,
      fontSize: 16,
      height: 1.5,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.enclavd.cardSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.enclavd.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            minLines: 3,
            maxLines: 8,
            // Hard 2000-char cap (the site's MAX_CHARS / api limit).
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            style: base,
            cursorColor: context.enclavd.textPrimary,
            decoration: InputDecoration(
              // No focusedBorder: the theme's blue OutlineInputBorder drew
              // an unwanted outline on focus.
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              counterText: '',
              hintText: 'Write post..', // the site's Quill placeholder
              hintStyle: TextStyle(color: context.enclavd.textSecondary),
              // Zero padding: the container's own padding positions the text.
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
                style: TextStyle(
                    color: context.enclavd.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Several attached images: thumbnails in post order, tap to edit, x to
/// remove (the website composer's strip).
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.slides,
    required this.onEdit,
    required this.onRemove,
  });

  final List<_ComposeSlide> slides;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: slides.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _Thumb(
              bytes: slides[i].baked,
              label: '${i + 1}',
              onTap: slides[i].sourcePath == null ? null : () => onEdit(i),
              onRemove: () => onRemove(i),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${slides.length}/${ComposeScreen.maxImages} images - tap to edit',
          style: TextStyle(color: context.enclavd.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Edit mode: the post's existing images, shown read-only (updates only
/// touch the text).
class _ReadOnlyImages extends StatelessWidget {
  const _ReadOnlyImages({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final slides = post.galleryImages;
    if (slides.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: EnclavdImage(
            resolveMediaUrl(AppConfig.apiBaseUrl, galleryName: slides.first),
            fit: BoxFit.contain,
            height: 220,
            placeholderHeight: 180,
          ),
        ),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slides.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => SizedBox(
          width: 88,
          height: 88,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: EnclavdImage(
              resolveMediaUrl(AppConfig.apiBaseUrl, galleryName: slides[i]),
              fit: BoxFit.cover,
              height: 88,
              placeholderHeight: 88,
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.bytes,
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  final Uint8List bytes;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: context.enclavd.card,
                shape: BoxShape.circle,
                border: Border.all(color: context.enclavd.border),
              ),
              child: FaIcon(FontAwesomeIcons.xmark,
                  size: 11, color: context.enclavd.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
