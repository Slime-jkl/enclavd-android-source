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
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/enclavd_image.dart';
import '../widgets/shimmer.dart';
import 'image_editor_screen.dart';
import '../services/analytics_service.dart';

/// One attached slide. [baked] is null while the pick is still being
/// decoded and standardised; the slot exists from the tap so the strip never
/// sits empty.
class _ComposeSlide {
  _ComposeSlide({this.sourcePath});

  Uint8List? baked;
  final String? sourcePath;

  bool get pending => baked == null;
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
  int _bakeDone = 0;
  int _bakeTotal = 0;

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

  /// Picks one or more images and standardises each one. Every pick drops a
  /// placeholder into the strip on the same frame as the tap, then fills in
  /// as its file finishes, so a slow decode still feels responsive. A single
  /// first image still goes straight into the editor; the rest land in the
  /// strip, where a tap re-opens the editor for that slide.
  Future<void> _pickImages() async {
    if (_busy || _baking) return;

    final picked = await (widget.pickImages ?? _pickFromGallery)();
    if (picked.isEmpty || !mounted) return;

    if (_slides.length + picked.length > ComposeScreen.maxImages) {
      setState(() => _error =
          'Up to ${ComposeScreen.maxImages} images per post.');
      return;
    }

    final placeholders = [for (final f in picked) _ComposeSlide(sourcePath: f.path)];
    setState(() {
      _baking = true;
      _bakeDone = 0;
      _bakeTotal = picked.length;
      _error = null;
      _slides.addAll(placeholders);
    });

    var failed = 0;
    for (var i = 0; i < picked.length; i++) {
      final slide = placeholders[i];
      try {
        final bytes = await picked[i].readAsBytes();
        final baked = await bakePickedBytes(bytes);
        if (!mounted) return;
        // The slide may have been removed while its file was decoding.
        if (!_slides.contains(slide)) continue;
        setState(() {
          slide.baked = baked;
          _bakeDone++;
        });
      } catch (_) {
        failed++;
        if (!mounted) return;
        setState(() {
          _slides.remove(slide);
          _bakeDone++;
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _baking = false;
      if (failed > 0) {
        _error = picked.length == 1
            ? 'Could not read that image.'
            : '$failed of ${picked.length} images could not be read.';
      }
    });
    if (failed > 0) return;

    // The single-image flow behaves exactly as before: pick, then edit.
    if (picked.length == 1 && _slides.length == 1) {
      await _editSlide(0);
    }
  }

  static Future<List<XFile>> _pickFromGallery() =>
      ImagePicker().pickMultiImage();

  Future<void> _editSlide(int index) async {
    if (index < 0 || index >= _slides.length) return;
    final slide = _slides[index];
    final path = slide.sourcePath;
    if (path == null || slide.pending) return; // still decoding

    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => ImageEditorScreen(imagePath: path)),
    );
    if (edited == null || !mounted) return; // cancelled in the editor

    setState(() {
      slide.baked = edited;
    });
  }

  void _removeSlide(int index) {
    if (_baking && _slides[index].pending) return; // finishing anyway
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
              XFile.fromData(slide.baked!,
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
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _errorBanner(),
                ),
              ),
              const SizedBox(height: 16),
              // Image area: picker + preview in create mode, read-only
              // existing images in edit mode.
              if (!_isEdit) ...[
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    child: _attachmentArea(),
                  ),
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

  Widget _errorBanner() {
    if (_error == null) return const SizedBox.shrink(key: ValueKey('none'));
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF87171).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFFF87171).withValues(alpha: 0.25)),
        ),
        child: Text(_error!,
            style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
      ),
    );
  }

  /// The attached-image area. Placeholders appear the instant the picker
  /// returns and every state change is a fade, never a pop.
  Widget _attachmentArea() {
    if (_slides.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('none'));
    }
    if (_slides.length == 1) {
      final slide = _slides.first;
      return AnimatedSwitcher(
        key: const ValueKey('single'),
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: slide.pending
            ? const _PendingPreview(key: ValueKey('pending'))
            : _ImagePreview(
                key: const ValueKey('ready'),
                bytes: slide.baked!,
                onRemove: () => _removeSlide(0),
              ),
      );
    }
    return _ImageStrip(
      key: const ValueKey('strip'),
      slides: _slides,
      baking: _baking,
      done: _bakeDone,
      total: _bakeTotal,
      onEdit: _editSlide,
      onRemove: _removeSlide,
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
            // Hard 20000-char cap (the site's MAX_CHARS / api limit).
            maxLength: 20000,
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
          // Mirrors post_form.php's "N/20000 characters" (textSecondary, right).
          Row(
            children: [
              EmojiPickerButton(controller: _controller, focusNode: _focus),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => Text(
                  '${value.text.characters.length}/20000 characters',
                  style: TextStyle(
                      color: context.enclavd.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single attached image, faded in once its bytes exist.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    super.key,
    required this.bytes,
    required this.onRemove,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              width: double.infinity,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) {
                if (sync) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: child,
                );
              },
            ),
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

/// A picked file that is still being decoded: same footprint as the final
/// preview so the layout does not jump.
class _PendingPreview extends StatelessWidget {
  const _PendingPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 220,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ShimmerBox(
                width: double.infinity, height: 220, borderRadius: 10),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: context.enclavd.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Preparing image...',
                    style: TextStyle(
                        color: context.enclavd.textSecondary, fontSize: 12),
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

/// Several attached images: thumbnails in post order, tap to edit, x to
/// remove (the website composer's strip). A thumbnail still decoding shows
/// the shimmer in its place.
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    super.key,
    required this.slides,
    required this.baking,
    required this.done,
    required this.total,
    required this.onEdit,
    required this.onRemove,
  });

  final List<_ComposeSlide> slides;
  final bool baking;
  final int done;
  final int total;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? (done + 1).clamp(1, total) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: slides.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final slide = slides[i];
              final baked = slide.baked;
              if (baked == null) {
                return const SizedBox(
                  width: 88,
                  height: 88,
                  child: ShimmerBox(
                      width: 88, height: 88, borderRadius: 8),
                );
              }
              return _Thumb(
                bytes: baked,
                label: '${i + 1}',
                onTap: slide.sourcePath == null ? null : () => onEdit(i),
                onRemove: () => onRemove(i),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            baking && total > 0
                ? 'Preparing $progress of $total...'
                : '${slides.length}/${ComposeScreen.maxImages} images - tap to edit',
            key: ValueKey(baking && total > 0),
            style: TextStyle(color: context.enclavd.textSecondary, fontSize: 12),
          ),
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
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) {
                if (sync) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: child,
                );
              },
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
