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

  final _transform = TransformationController();
  Size? _viewport; // latest preview size (set by the LayoutBuilder)

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
        if (decoded == null) _error = 'Unsupported image format.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not read the image.');
    }
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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final (label, ratio) in _ratios)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: _pill(
                  label,
                  selected: _ratio == ratio,
                  onTap: () => setState(() => _ratio = ratio),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterTools() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final f in IedFilter.presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: _pill(
                  f.label,
                  selected: _filter.id == f.id,
                  onTap: () => setState(() => _filter = f),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Theme-styled pill (the site's rounded-full filter buttons) — plain
  /// Material ChoiceChips draw light M3 outlines that look broken on the
  /// dark design system.
  Widget _pill(String label,
      {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? EnclavdColors.link.withValues(alpha: 0.15)
              : EnclavdColors.cardSecondary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? EnclavdColors.link : EnclavdColors.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? EnclavdColors.link : EnclavdColors.textPrimary,
          ),
        ),
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
