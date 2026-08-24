import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme/enclavd_theme.dart';
import '../utils/ied_filter.dart';

/// Post-image editor — a mobile-first port of the site's ied (image
/// editor) from post_form.php.
///
///   Crop:    pan (drag) / zoom (pinch) the image under a centered crop
///            frame; ratio presets Free / 1:1 / 4:3 / 16:9 / 3:4 / 9:16 —
///            the site's "Drag image to pan · Scroll to zoom · Change ratio
///            to crop".
///   Filters: the site's 14 presets (IED_FILTERS). Preview is a live
///            ColorFilter.matrix; the baked output uses the identical
///            matrix per-pixel, so what you see is what uploads.
///   Output:  the cropped region, filter baked, resized to ≤1200px (the
///            site's MAX) and JPEG q85 — bounded payloads that fit any
///            post_max_size, and the same visual the site ships.
///
/// Pops with the edited image bytes (JPEG) on Apply, null on cancel.
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key, required this.imagePath});

  final String imagePath;

  static const routeName = '/image-editor';

  /// The site's MAX output dimension.
  static const int maxOutput = 1200;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  img.Image? _source;
  String? _error;

  /// Tiny JPEG of the source (≤160px) — the ONE shared byte source for
  /// every filter thumbnail (same bytes → one decode, 14 filtered views).
  Uint8List? _thumbBytes;

  final _transform = TransformationController();
  Size? _viewport; // latest preview size (set by the LayoutBuilder)

  /// The initial contain-fit transform has been applied (once per image).
  bool _transformReady = false;

  bool _tabCrop = true;
  double _ratio = 0; // 0 = free
  IedFilter _filter = IedFilter.presets.first;
  bool _busy = false;

  static const _ratios = <(String, double)>[
    ('Free', 0),
    ('1:1', 1),
    ('4:3', 4 / 3),
    ('16:9', 16 / 9),
    ('3:4', 3 / 4),
    ('9:16', 9 / 16),
  ];

  @override
  void initState() {
    super.initState();
    // Crop is confined to the image: every pan/zoom lands through this
    // clamp, so the crop frame can never leave the image's bounds.
    _transform.addListener(_clampTransform);
    _decode();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted) return;
      setState(() {
        _source = decoded;
        _transformReady = false;
        if (decoded == null) {
          _error = 'Unsupported image format.';
        } else {
          final thumb = img.copyResize(decoded, width: 160);
          _thumbBytes = Uint8List.fromList(img.encodeJpg(thumb, quality: 70));
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not read the image.');
    }
  }

  /// The smallest scale at which the image still COVERS the crop frame —
  /// zooming out past this would put empty space inside the crop.
  double _requiredMinScale(Size viewport) {
    final src = _source!;
    final fit = math.min(viewport.width / src.width, viewport.height / src.height);
    final iw = src.width * fit;
    final ih = src.height * fit;
    final frame = _frameRect(viewport);
    return math.max(frame.width / iw, frame.height / ih);
  }

  /// Re-fits the image inside the crop frame: keeps the current zoom when
  /// it is still valid, otherwise zooms to just-cover, and centers the
  /// image on the frame. Called on ratio changes and once after decode.
  void _refit() {
    final src = _source;
    final vp = _viewport;
    if (src == null || vp == null) return;
    final current = _transform.value.getMaxScaleOnAxis();
    final s = math.max(current, _requiredMinScale(vp));
    final fit = math.min(vp.width / src.width, vp.height / src.height);
    final iw = src.width * fit;
    final ih = src.height * fit;
    final ox = (vp.width - iw) / 2;
    final oy = (vp.height - ih) / 2;
    // Center the IMAGE RECT (letterbox offsets included) on the viewport.
    final tx = (vp.width - iw * s) / 2 - ox * s;
    final ty = (vp.height - ih * s) / 2 - oy * s;
    _transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _selectRatio(double ratio) {
    setState(() => _ratio = ratio);
    _refit();
  }

  /// The crop frame never leaves the image: the image must cover the
  /// frame (zoom floor), and panning is bounded so the frame stays inside
  /// the image at the current zoom.
  void _clampTransform() {
    final src = _source;
    final vp = _viewport;
    if (src == null || vp == null) return;
    final m = _transform.value;
    final clamped = clampCropTransform(
      imgW: src.width.toDouble(),
      imgH: src.height.toDouble(),
      viewport: vp,
      frame: _frameRect(vp),
      scale: m.getMaxScaleOnAxis(),
      tx: m.getTranslation().x,
      ty: m.getTranslation().y,
      maxScale: 6,
    );
    if (clamped.scale == m.getMaxScaleOnAxis() &&
        clamped.tx == m.getTranslation().x &&
        clamped.ty == m.getTranslation().y) {
      return;
    }
    _transform.value = Matrix4.identity()
      ..translateByDouble(clamped.tx, clamped.ty, 0, 1)
      ..scaleByDouble(clamped.scale, clamped.scale, 1, 1);
  }

  /// The crop frame in VIEWPORT coordinates: the full viewport for Free,
  /// otherwise the largest centered rect at the selected ratio.
  Rect _frameRect(Size size) {
    if (_ratio <= 0) return Offset.zero & size;
    var w = size.width;
    var h = w / _ratio;
    if (h > size.height) {
      h = size.height;
      w = h * _ratio;
    }
    return Rect.fromCenter(
        center: size.center(Offset.zero), width: w, height: h);
  }

  /// Maps the crop frame into SOURCE-image coordinates using the current
  /// pan/zoom transform (contain-fit child geometry).
  Rect _imageCropRect(Size viewport) {
    final src = _source!;
    final imgW = src.width.toDouble();
    final imgH = src.height.toDouble();
    final vw = viewport.width;
    final vh = viewport.height;
    final fit = math.min(vw / imgW, vh / imgH);
    final iw = imgW * fit;
    final ih = imgH * fit;
    final ox = (vw - iw) / 2;
    final oy = (vh - ih) / 2;
    final m = _transform.value;
    final s = m.getMaxScaleOnAxis();
    final tx = m.getTranslation().x;
    final ty = m.getTranslation().y;

    Offset toImage(Offset v) {
      final childX = (v.dx - tx) / s;
      final childY = (v.dy - ty) / s;
      return Offset((childX - ox) / fit, (childY - oy) / fit);
    }

    final frame = _frameRect(viewport);
    final tl = toImage(frame.topLeft);
    final br = toImage(frame.bottomRight);
    return Rect.fromPoints(tl, br);
  }

  Future<void> _apply() async {
    final src = _source;
    final viewport = _viewport;
    if (src == null || viewport == null) return;
    setState(() => _busy = true);
    try {
      final crop = _imageCropRect(viewport);
      final x = crop.left.round().clamp(0, src.width - 1);
      final y = crop.top.round().clamp(0, src.height - 1);
      final w = crop.width.round().clamp(1, src.width - x);
      final h = crop.height.round().clamp(1, src.height - y);

      var out = img.copyCrop(src, x: x, y: y, width: w, height: h);
      if (_filter.id != 'normal') {
        IedFilter.applyToImage(out, _filter.matrix());
      }
      final maxDim = math.max(out.width, out.height);
      if (maxDim > ImageEditorScreen.maxOutput) {
        final scale = ImageEditorScreen.maxOutput / maxDim;
        out = img.copyResize(out,
            width: (out.width * scale).round(),
            height: (out.height * scale).round(),
            interpolation: img.Interpolation.cubic);
      }
      final bytes = Uint8List.fromList(img.encodeJpg(out, quality: 85));
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Could not process the image.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit image'),
        actions: [
          TextButton.icon(
            onPressed: _busy || _source == null ? null : _apply,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FaIcon(FontAwesomeIcons.check,
                    size: 15, color: EnclavdColors.link),
            label: const Text('Apply'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(color: EnclavdColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
    if (_source == null) {
      return const Center(
          child: CircularProgressIndicator(color: EnclavdColors.link));
    }
    return Column(
      children: [
        // Card-backed preview so letterboxed areas never look "transparent"
        // against the page background.
        Expanded(
          child: Container(
            color: EnclavdColors.card,
            child: _preview(),
          ),
        ),
        // SafeArea keeps the tool rows above the system navigation bar.
        SafeArea(
          top: false,
          child: Column(
            children: [
              _toolTabs(),
              if (_tabCrop) _cropTools() else _filterTools(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _viewport = size;
        // First layout after decode: place the image so the crop frame is
        // exactly covered and centered (the clamp enforces it from there).
        if (!_transformReady && _source != null) {
          _transformReady = true;
          _refit();
        }
        final frame = _frameRect(size);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Filtered, pannable/zoomable image.
            ColorFiltered(
              colorFilter: ColorFilter.matrix(_filter.matrix()),
              child: InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                minScale: 1,
                maxScale: 6,
                boundaryMargin: EdgeInsets.all(size.longestSide * 2),
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Center(
                    child: Image.file(File(widget.imagePath),
                        fit: BoxFit.contain,
                        width: size.width,
                        height: size.height),
                  ),
                ),
              ),
            ),
            // Crop frame + mask.
            if (_tabCrop)
              IgnorePointer(
                child: CustomPaint(
                  painter: _CropFramePainter(
                    frame: frame,
                    frameColor: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _toolTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EnclavdColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          _tab('Crop', FontAwesomeIcons.crop, _tabCrop),
          _tab('Filters', FontAwesomeIcons.sliders, !_tabCrop),
        ],
      ),
    );
  }

  Widget _tab(String label, FaIconData icon, bool active) {
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabCrop = label == 'Crop'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? EnclavdColors.link : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(icon,
                  size: 14,
                  color: active
                      ? EnclavdColors.link
                      : EnclavdColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? EnclavdColors.link
                        : EnclavdColors.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cropTools() {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final item in _ratios)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ratioCard(
                item,
                selected: _ratio == item.$2,
                onTap: () => _selectRatio(item.$2),
              ),
            ),
        ],
      ),
    );
  }

  /// A ratio preset as a CARD whose glyph shows the ACTUAL shape of the
  /// ratio (a square for 1:1, a wide bar for 16:9, a tall bar for 9:16…)
  /// instead of a bare text label — the user sees what they are picking.
  Widget _ratioCard((String, double) item,
      {required bool selected, required VoidCallback onTap}) {
    final (label, ratio) = item;
    final color = selected ? EnclavdColors.link : EnclavdColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? EnclavdColors.link.withValues(alpha: 0.15)
              : EnclavdColors.cardSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? EnclavdColors.link : EnclavdColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (ratio <= 0)
              FaIcon(FontAwesomeIcons.crop, size: 16, color: color)
            else
              CustomPaint(
                size: const Size(36, 18),
                painter: _RatioGlyphPainter(ratio: ratio, color: color),
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterTools() {
    final thumbs = _thumbBytes;
    return SizedBox(
      height: 82,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final f in IedFilter.presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _filterCard(
                f,
                thumbs: thumbs,
                selected: _filter.id == f.id,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  /// A filter as a THUMBNAIL button: a small crop of the actual image with
  /// the filter applied, so the user sees the real effect before picking
  /// (the same ColorFilter.matrix the preview and the baked output use).
  Widget _filterCard(IedFilter filter,
      {required Uint8List? thumbs,
      required bool selected,
      required VoidCallback onTap}) {
    final color = selected ? EnclavdColors.link : EnclavdColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 54,
            height: 54,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? EnclavdColors.link : EnclavdColors.divider,
                width: selected ? 2 : 1,
              ),
              color: EnclavdColors.cardSecondary,
            ),
            child: thumbs == null
                ? const Center(
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5)),
                  )
                : ColorFiltered(
                    colorFilter: ColorFilter.matrix(filter.matrix()),
                    child: Image.memory(
                      thumbs,
                      fit: BoxFit.cover,
                      width: 54,
                      height: 54,
                      cacheWidth: 108,
                      gaplessPlayback: true,
                    ),
                  ),
          ),
          const SizedBox(height: 3),
          Text(
            filter.label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens everything outside the crop frame and draws its border — the
/// site's fixed crop-window overlay.
class _CropFramePainter extends CustomPainter {
  const _CropFramePainter({required this.frame, required this.frameColor});

  final Rect frame;
  final Color frameColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);
    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = frameColor,
    );
  }

  @override
  bool shouldRepaint(_CropFramePainter oldDelegate) =>
      oldDelegate.frame != frame;
}

/// Clamps a crop pan/zoom transform so the crop frame NEVER leaves the
/// image (pure math, unit-tested):
///
/// - Zoom floor: the image must still COVER the frame — zooming out past
///   `max(frame.w/iw, frame.h/ih)` would put empty space inside the crop,
///   so the scale is pulled back up to exactly-cover.
/// - Pan bounds: with the image at `scale`, its rect in viewport coords is
///   `[ox*s+tx, (ox+iw)*s+tx] × [oy*s+ty, (oy+ih)*s+ty]`; the translation
///   is clamped so that rect contains the frame.
///
/// The image is rendered contain-fit (centered) inside a viewport-sized
/// child, so `ox/oy` = letterbox offsets and `iw/ih` = image size at
/// scale 1. `tx/ty`/`scale` come from the transformation matrix
/// (scale-about-origin then translate, the InteractiveViewer convention).
({double scale, double tx, double ty}) clampCropTransform({
  required double imgW,
  required double imgH,
  required Size viewport,
  required Rect frame,
  required double scale,
  required double tx,
  required double ty,
  double maxScale = 6,
}) {
  final fit = math.min(viewport.width / imgW, viewport.height / imgH);
  final iw = imgW * fit;
  final ih = imgH * fit;
  final ox = (viewport.width - iw) / 2;
  final oy = (viewport.height - ih) / 2;

  // Zoom floor: the image must cover the crop frame (and never exceed
  // the max zoom).
  final minScale = math.max(frame.width / iw, frame.height / ih);
  final s = scale.clamp(minScale, maxScale);

  // Pan bounds: the frame stays inside the image at this zoom.
  //   image.left  = ox*s + tx ≤ frame.left  → tx ≤ frame.left  - ox*s
  //   image.right = (ox+iw)*s + tx ≥ frame.right → tx ≥ frame.right - (ox+iw)*s
  final txLower = frame.right - (ox + iw) * s;
  final txUpper = frame.left - ox * s;
  final tyLower = frame.bottom - (oy + ih) * s;
  final tyUpper = frame.top - oy * s;
  return (
    scale: s,
    tx: tx.clamp(txLower, txUpper),
    ty: ty.clamp(tyLower, tyUpper),
  );
}

/// Draws a small rounded-rect OUTLINE in the exact proportions of a crop
/// ratio (contain-fit into the box) — the glyph on the ratio cards.
class _RatioGlyphPainter extends CustomPainter {
  const _RatioGlyphPainter({required this.ratio, required this.color});

  /// width / height of the ratio (e.g. 16/9, 3/4).
  final double ratio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color;
    var w = size.width - 6;
    var h = w / ratio;
    if (h > size.height - 6) {
      h = size.height - 6;
      w = h * ratio;
    }
    final rect = Rect.fromCenter(
        center: size.center(Offset.zero), width: w, height: h);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
  }

  @override
  bool shouldRepaint(_RatioGlyphPainter oldDelegate) =>
      oldDelegate.ratio != ratio || oldDelegate.color != color;
}
