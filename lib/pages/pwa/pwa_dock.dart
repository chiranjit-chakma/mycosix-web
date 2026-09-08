import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';

/// Focus of an item at distance [d] slots from the strip's center: 1 at the
/// center, falling to 0 once it is about two slots away. Linear, so the
/// strip's motion stays even while dragged.
double _focusFor(double d) => math.max(0.0, 1.0 - d.abs() * 0.45);

/// Carousel emphasis: the center item reads 1.18x, far items shrink toward
/// 0.86x — progressive, never a dramatic zoom.
double _itemScale(double frac, int i) {
  return 0.86 + 0.32 * _focusFor(i - frac);
}

/// Prominence: the center item is fully opaque, far items dim toward 0.55,
/// and an item sliding past the capsule's own edge melts away instead of
/// hitting a hard clip boundary.
double _itemOpacity(double frac, int i, double capsuleWidth, double slot) {
  final f = _focusFor(i - frac);
  final screenX = (i - frac) * slot;
  final edge = (capsuleWidth / 2 - screenX.abs() + 24) / 24;
  final edgeFade = math.min(1.0, math.max(0.0, edge));
  return (0.55 + 0.45 * f) * edgeFade;
}

/// Labels fade out as the dock compresses, over the upper stretch of the
/// scroll range so the icon-only state is reached smoothly.
double _labelOpacity(double t) {
  if (t <= 0.55) return 1.0;
  if (t >= 0.9) return 0.0;
  return (0.9 - t) / 0.35;
}

/// The installed phone app's primary navigation: a floating frosted-glass
/// dock that behaves like a carousel, not a static bar.
///
/// Five destinations ride a strip that tracks the finger 1:1 while dragged
/// horizontally. The item nearest the strip's center is the live selection;
/// releasing springs that item into the center and opens its section. A
/// quick tap on any destination (or on the empty glass around it, which
/// maps to the nearest item) works exactly like the old bottom bar.
///
/// The strip owns *only* horizontal drags. Its hit-testing is translucent,
/// so a vertical gesture over the dock falls straight through to the page's
/// own scroll — the dock can never swallow a vertical scroll. In-page
/// horizontal carousels, maps, forms and text selection are untouched.
///
/// The dock is sized along a 0..1 [compression] animation driven by the
/// page's scroll position: taller and airier at the top of the page,
/// shorter and tighter once the user scrolls down, always smoothly.
///
/// This widget is built only for the installed phone-size PWA
/// ([isStandaloneMobile]). Browser tabs and desktop keep the ordinary
/// website navigation.
class PwaDock extends StatefulWidget {
  const PwaDock({
    super.key,
    required this.index,
    required this.labels,
    required this.icons,
    required this.onSelect,
    required this.compression,
  });

  /// The section to center. May change from outside the dock (back gliding
  /// Home, a deep link, a More link) — the strip glides to match.
  final int index;

  final List<String> labels;
  final List<IconData> icons;

  /// Called with the chosen section when a tap picks it or a drag releases
  /// on it. The parent glides the pager while the dock springs in parallel.
  final ValueChanged<int> onSelect;

  /// Page-scroll position as a 0..1 animation (1 = fully compressed).
  final Animation<double> compression;

  @override
  State<PwaDock> createState() => _PwaDockState();
}

class _PwaDockState extends State<PwaDock>
    with SingleTickerProviderStateMixin {
  /// Continuous carousel position: 0 = first label centered, n-1 = last
  /// centered. Fractions are the strip mid-slide between two sections.
  double _frac = 0;

  bool _dragging = false;

  /// Springs [_snapStart, _snapEnd] with easeOutBack so the strip overshoots
  /// a touch and settles — the "no jitter, no delayed response" snap.
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_onSnapTick);

  double _snapStart = 0;
  double _snapEnd = 0;

  /// Last laid-out capsule width; the drag math reads it so a gesture that
  /// starts mid-frame still uses the current geometry.
  double _capsuleWidth = 456;

  int get _last => widget.labels.length - 1;

  @override
  void initState() {
    super.initState();
    _frac = widget.index.toDouble();
  }

  @override
  void didUpdateWidget(PwaDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A section change from outside the dock (back to Home, a deep link, a
    // More link) glides the strip to match. While the finger is down, it
    // owns the strip; during the dock's own release-snap the pager's
    // intermediate page notifications land where the strip already is, so
    // the distance check skips them.
    if (widget.index != oldWidget.index &&
        !_dragging &&
        (widget.index - _frac).abs() > 0.05) {
      _animateTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  /// Mirrors the dock's placement: SafeArea minimum 12 left/right, capped
  /// at the desktop pill width.
  double _computeCapsuleWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width - 24.0;
    return math.min(w, 620.0).clamp(240.0, 620.0).toDouble();
  }

  double _slot(double capsuleWidth) {
    return math.min(70.0, (capsuleWidth - 24.0) / widget.labels.length);
  }

  void _onSnapTick() {
    final t = Curves.easeOutBack.transform(_snap.value);
    setState(() => _frac = _snapStart + (_snapEnd - _snapStart) * t);
  }

  void _animateTo(double target) {
    _snapStart = _frac;
    _snapEnd = target.clamp(0.0, _last.toDouble());
    _snap.forward(from: 0);
  }

  void _beginDrag(DragStartDetails _) {
    _snap.stop();
    _dragging = true;
  }

  void _updateDrag(DragUpdateDetails d) {
    final slot = _slot(_capsuleWidth);
    setState(() {
      _frac = (_frac - d.delta.dx / slot).clamp(0.0, _last.toDouble());
    });
  }

  void _endDrag(DragEndDetails d) {
    _dragging = false;
    final v = d.velocity.pixelsPerSecond.dx;
    // A deliberate fling carries momentum across the next slot; a slow drag
    // simply snaps to whichever item is nearest the center.
    final nudge = v.abs() > 800 ? -v.sign * 0.3 : 0.0;
    final target = (_frac + nudge).round().clamp(0, _last);
    if (target == widget.index) {
      // Released back where we started: spring the strip to the center but
      // leave the page alone — no surprise scroll-to-top from a nudge.
      _animateTo(target.toDouble());
    } else {
      _select(target);
    }
  }

  void _cancelDrag() {
    _dragging = false;
    _animateTo(_frac.roundToDouble().clamp(0.0, _last.toDouble()));
  }

  void _select(int target) {
    final index = target.clamp(0, _last);
    if ((index - _frac).abs() > 0.001) _animateTo(index.toDouble());
    widget.onSelect(index);
  }

  /// A tap anywhere on the dock (item or the glass around it) picks the
  /// nearest item — the strip position tells us which.
  void _tapAt(double localDx) {
    final slot = _slot(_capsuleWidth);
    final index =
        (_frac + (localDx - _capsuleWidth / 2) / slot).round().clamp(0, _last);
    _select(index);
  }

  @override
  Widget build(BuildContext context) {
    _capsuleWidth = _computeCapsuleWidth(context);
    // The compression animation drives the whole capsule's metrics, so the
    // strip rebuilds only when it ticks (never on every page-scroll frame).
    return ListenableBuilder(
      listenable: widget.compression,
      builder: (context, _) {
        final t = widget.compression.value.clamp(0.0, 1.0);
        final slot = _slot(_capsuleWidth);
        final gap = 6.0 + (4.0 - 6.0) * t;
        final itemWidth = slot - gap;
        final height = 78.0 + (58.0 - 78.0) * t;
    final active = _frac.round().clamp(0, _last);

        // Paint order: farthest from the center first, so the scaled-up
        // center item sits on top where it overlaps its neighbours.
        final order = List<int>.generate(widget.labels.length, (i) => i)
          ..sort((a, b) => (a - _frac).abs().compareTo((b - _frac).abs()));

        // The strip is the ONLY hit-testable surface: it joins the hit path
        // as translucent (added to the result but reporting no hit), and the
        // entire visual capsule is wrapped in IgnorePointer, so a touch over
        // the dock also reaches the page beneath. Vertical drags scroll the
        // page, horizontal drags navigate, and taps map to the nearest item;
        // the dock never swallows a page gesture.
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => _tapAt(d.localPosition.dx),
          onHorizontalDragStart: _beginDrag,
          onHorizontalDragUpdate: _updateDrag,
          onHorizontalDragEnd: _endDrag,
          onHorizontalDragCancel: _cancelDrag,
          child: IgnorePointer(
            child: Container(
              width: _capsuleWidth,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: MxColors.charcoal.withValues(alpha: 0.14),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Frosted backing: soft blur of whatever scrolls beneath,
                    // under a translucent cream surface with a hairline border.
                    // The glass is decorative and pointer-invisible.
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: const ColoredBox(color: Colors.transparent),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: MxColors.cream.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    // Destinations, painted farthest from the center first so
                    // the scaled-up center item sits on top of its neighbours.
                    // Purely visual: pointer input lives on the strip.
                    for (final i in order)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment(
                            ((i - _frac) * slot) / (_capsuleWidth / 2),
                            0,
                          ),
                          child: _DockItem(
                            key: Key(
                              'pwa-nav-${widget.labels[i].toLowerCase()}',
                            ),
                            label: widget.labels[i],
                            icon: widget.icons[i],
                            selected: i == active,
                            iconSize: 20.0 + (17.0 - 20.0) * t,
                            labelOpacity: _labelOpacity(t),
                            width: itemWidth,
                            height: height - 12,
                            opacity: _itemOpacity(
                              _frac,
                              i,
                              _capsuleWidth,
                              slot,
                            ),
                            scale: _itemScale(_frac, i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One destination inside the dock: a forest-filled glass cell that lights
/// up when it is the live selection. Purely visual — pointer input lives on
/// the strip so the dock never swallows a page gesture.
class _DockItem extends StatelessWidget {
  const _DockItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.iconSize,
    required this.labelOpacity,
    required this.width,
    required this.height,
    required this.opacity,
    required this.scale,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final double iconSize;
  final double labelOpacity;
  final double width;
  final double height;
  final double opacity;
  final double scale;

  static const _radius = 16.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            tween: Tween<double>(end: selected ? 1 : 0),
            builder: (context, s, _) {
              // The chosen section fills its cell with deep forest and lifts
              // it with a soft glow; the fill retargets smoothly as the
              // selection moves between items while dragging.
              final fill =
                  Color.lerp(Colors.transparent, MxColors.forest, s) ??
                  Colors.transparent;
              final content =
                  Color.lerp(
                    selected ? MxColors.charcoalSoft : MxColors.stone,
                    Colors.white,
                    s,
                  ) ??
                  Colors.white;
              return Material(
                color: fill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_radius),
                ),
                elevation: 4 * s,
                shadowColor: MxColors.forest.withValues(alpha: 0.45),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: iconSize, color: content),
                      const SizedBox(height: 3),
                      Opacity(
                        opacity: labelOpacity,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MxType.label(
                            color: content,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
