import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Shared pieces of the artwork-inspired look: the picture as a backdrop,
/// outlined cartoon text, chunky panels and buttons with dark outlines.

const String kArtAsset = 'assets/images/main_bg.webp';

/// Text with a thick dark outline, like the lettering in a cartoon.
TextStyle cartoon(
  double size, {
  Color color = Palette.cream,
  FontWeight weight = FontWeight.w900,
  double spacing = 0,
  double outline = 2,
}) {
  final o = outline;
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
    shadows: [
      for (final dx in [-o, 0.0, o])
        for (final dy in [-o, 0.0, o])
          if (dx != 0 || dy != 0) Shadow(color: Palette.ink, offset: Offset(dx, dy)),
      Shadow(color: Palette.ink, offset: Offset(0, o * 1.8)),
    ],
  );
}

/// The artwork behind a screen. [dim] darkens it; [blur] softens it so
/// content on top stays readable.
class ArtBackdrop extends StatelessWidget {
  const ArtBackdrop({
    super.key,
    required this.child,
    this.dim = 0.35,
    this.blur = 0,
    this.tint,
  });

  final Widget child;
  final double dim;
  final double blur;

  /// A colour washed over the picture (it fades when it changes).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    Widget art = Image.asset(
      kArtAsset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,
    );
    if (blur > 0) {
      art = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: art,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Palette.bg),
        art,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: dim * 0.6),
                Colors.black.withValues(alpha: dim),
                Colors.black.withValues(alpha: dim * 1.3),
              ],
            ),
          ),
        ),
        if (tint != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            color: tint!.withValues(alpha: 0.38),
          ),
        child,
      ],
    );
  }
}

/// A chunky rounded box with a dark outline and a soft drop shadow.
class Chunky extends StatelessWidget {
  const Chunky({
    super.key,
    required this.child,
    this.colors = const [Palette.panel, Palette.panel],
    this.radius = 18,
    this.border = 3,
    this.padding = const EdgeInsets.all(14),
    this.glow,
  });

  final Widget child;
  final List<Color> colors;
  final double radius;
  final double border;
  final EdgeInsets padding;

  /// Colour of a thin lighter line just inside the outline.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Palette.ink, width: border),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5)),
        ],
      ),
      child: glow == null
          ? child
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius - border),
                border: Border.all(color: glow!, width: 1.5),
              ),
              child: child,
            ),
    );
  }
}

/// Dark mossy panel for descriptions and settings cards.
class MossPanel extends StatelessWidget {
  const MossPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.colors = const [Color(0xEE2B4A2A), Color(0xEE1B3020)],
  });

  final Widget child;
  final EdgeInsets padding;

  /// Top and bottom colour; the select screen passes the world's own.
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Chunky(
        colors: colors,
        padding: padding,
        child: child,
      );
}

enum ButtonLook { leaf, wood, gold }

/// The big rounded button: bright leaf green, wooden plank, or gold.
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.look = ButtonLook.wood,
    this.tint,
    this.fontSize = 24,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final ButtonLook look;

  /// Overrides [look] with a custom colour (the world's accent).
  final Color? tint;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final (top, bottom, shine) = tint != null
        ? (
            Color.lerp(tint, Colors.white, 0.15)!,
            Color.lerp(tint, Colors.black, 0.28)!,
            Color.lerp(tint, Colors.white, 0.6)!,
          )
        : switch (look) {
      ButtonLook.leaf => (Palette.leaf, Palette.leafMid, const Color(0xFFB8EC84)),
      ButtonLook.gold => (const Color(0xFFFFD968), const Color(0xFFE0A21F), const Color(0xFFFFF0B0)),
      ButtonLook.wood => (Palette.woodLight, Palette.wood, const Color(0xFFE9BE86)),
    };
    final enabled = onTap != null;
    // The decoration (and its shadow) lives on a plain Container: an Ink
    // decoration clips its drop shadow. The ripple sits on top of it.
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.ink, width: 4),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 6)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: padding,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // A glossy highlight along the top edge.
                  Positioned(
                    top: -padding.top + 3,
                    left: 14,
                    right: 14,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: shine.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // The label never gets closer than 12 to the button's edge.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: fontSize * 1.25, color: Palette.cream, shadows: const [
                          Shadow(color: Palette.ink, offset: Offset(0, 2)),
                          Shadow(color: Palette.ink, offset: Offset(1.5, 0)),
                          Shadow(color: Palette.ink, offset: Offset(-1.5, 0)),
                        ]),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, style: cartoon(fontSize, spacing: 2.5)),
                        ),
                      ),
                    ],
                  ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small round or square icon button in the same style.
class ChunkyIconButton extends StatelessWidget {
  const ChunkyIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 46,
    this.round = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final radius = round ? size / 2 : 14.0;
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.woodLight, Palette.wood],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Palette.ink, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius - 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius - 2),
          child: Icon(icon, color: Palette.cream, size: size * 0.55, shadows: const [
            Shadow(color: Palette.ink, offset: Offset(0, 2)),
          ]),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// A square window onto part of the artwork (used for the world buttons).
/// [center] is the middle of the crop and [width] its width, both as
/// fractions of the picture.
class ArtCrop extends StatefulWidget {
  const ArtCrop({
    super.key,
    required this.center,
    required this.width,
    this.size = 56,
    this.radius = 12,
  });

  final Offset center;
  final double width;
  final double size;
  final double radius;

  @override
  State<ArtCrop> createState() => _ArtCropState();
}

class _ArtCropState extends State<ArtCrop> {
  static ui.Image? _shared;
  static bool _loading = false;
  static final List<VoidCallback> _waiting = [];

  @override
  void initState() {
    super.initState();
    if (_shared == null) {
      _waiting.add(_refresh);
      _load();
    }
  }

  @override
  void dispose() {
    _waiting.remove(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Decodes the picture once for all crops.
  static void _load() {
    if (_loading) return;
    _loading = true;
    final stream = const AssetImage(kArtAsset).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      _shared = info.image.clone();
      stream.removeListener(listener);
      for (final w in List.of(_waiting)) {
        w();
      }
      _waiting.clear();
    }, onError: (_, _) => _loading = false);
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: CustomPaint(painter: _CropPainter(_shared, widget.center, widget.width)),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.center, this.width);

  final ui.Image? image;
  final Offset center;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Palette.leafDark);
      return;
    }
    final w = img.width * width;
    final src = Rect.fromCenter(
      center: Offset(img.width * center.dx, img.height * center.dy),
      width: w,
      height: w * size.height / size.width,
    );
    canvas.drawImageRect(
      img,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.center != center || old.width != width;
}
