import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';

/// Share of the horizontal geometry (slot pitch and strip width) that is
/// removed as the dock compresses from its expanded state to its compact one.
const double _kCompress = 0.34;

/// Focus of an item at distance [d] slots from the strip's centre: 1 at the
/// centre, falling to 0 once it is about two slots away. Linear, so the
/// strip's motion stays even while dragged.
double _focusFor(double d) => math.max(0.0, 1.0 - d.abs() * 0.45);

/// Carousel emphasis: the centred item reads about 1.16x, far items settle
/// toward 0.9x — progressive, never a dramatic zoom.
double _itemScale(double frac, int i) {
  return 0.9 + 0.26 * _focusFor(i - frac);
}

/// Prominence: the centred item is fully opaque, far items dim a touch, and
/// an item sliding past the strip's own edge melts away instead of hitting a
/// hard clip boundary.
double _itemOpacity(double frac, int i, double capsuleWidth, double slot) {
  final f = _focusFor(i - frac);
  final screenX = (i - frac) * slot;
  final edge = (capsuleWidth / 2 - screenX.abs() + 24) / 24;
  final edgeFade = math.min(1.0, math.max(0.0, edge));
  return (0.85 + 0.15 * f) * edgeFade;
}

/// The caption under the active item fades out as the dock compresses, over
/// the upper stretch of the scroll range, so the icon-only compact state is
/// reached smoothly.
double _labelOpacity(double t) {
  if (t <= 0.55) return 1.0;
  if (t >= 0.9) return 0.0;
  return (0.9 - t) / 0.35;
}

/// The installed phone app's primary navigation: a floating frosted-glass
/// dock that behaves like a carousel, not a static bar.
///
/// The five destinations ride a frosted glass carrier — the same blur, wash,
/// hairline and shadow recipe as the browser's floating top pill, so the two
/// navigations read as one system. Only the active destination is enlarged
/// and tinted deep forest with a small brand underline and its caption;
/// inactive destinations sit smaller and quieter, and the strip slides so
/// the selected glyph is always the largest, centred one.
///
/// Five destinations ride a strip that tracks the finger 1:1 while dragged
/// horizontally. The item nearest the strip's centre is the live selection;
/// releasing springs that item into the centre and opens its section. A
/// quick tap on any destination (or on the empty space around it, which maps
/// to the nearest item) works exactly like the old bottom bar.
///
/// The strip owns *only* horizontal drags. Its hit-testing is translucent, so
/// a vertical gesture over the dock falls straight through to the page's own
/// scroll — the dock can never swallow a vertical scroll. In-page horizontal
/// carousels, maps, forms and text selection are untouched.
///
/// The dock is sized along a 0..1 [compression] animation driven by the
/// page's scroll position. It compresses in BOTH directions: taller, airier
/// and wider at the top of the page, shorter and tighter once the user
/// scrolls down — the band shrinks, the slots pull the destinations closer
/// and the icons shrink — always smoothly, never a crude scale transform.
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

  /// The section to centre. May change from outside the dock (back gliding
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
  /// Continuous carousel position: 0 = first label centred, n-1 = last
  /// centred. Fractions are the strip mid-slide between two sections.
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

  /// Last laid-out strip width and pixel-per-slot pitch; the gesture math
  /// reads them so a gesture that starts mid-frame uses the current geometry.
  double _capsuleWidth = 456;
  double _slotPx = 66;

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
    setState(() {
      _frac = (_frac - d.delta.dx / _slotPx).clamp(0.0, _last.toDouble());
    });
  }

  void _endDrag(DragEndDetails d) {
    _dragging = false;
    final v = d.velocity.pixelsPerSecond.dx;
    // A deliberate fling carries momentum across the next slot; a slow drag
    // simply snaps to whichever item is nearest the centre.
    final nudge = v.abs() > 800 ? -v.sign * 0.3 : 0.0;
    final target = (_frac + nudge).round().clamp(0, _last);
    if (target == widget.index) {
      // Released back where we started: spring the strip to the centre but
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

  /// A tap anywhere on the dock (glyph or the empty space around it) picks
  /// the nearest item — the strip position tells us which.
  void _tapAt(double localDx) {
    final index =
        (_frac + (localDx - _capsuleWidth / 2) / _slotPx)
            .round()
            .clamp(0, _last);
    _select(index);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    // The compression animation drives the whole strip's metrics, so the
    // dock rebuilds only when it ticks (never on every page-scroll frame).
    return ListenableBuilder(
      listenable: widget.compression,
      builder: (context, _) {
        final t = widget.compression.value.clamp(0.0, 1.0);

        // Geometry compresses on BOTH axes as the page scrolls down: the
        // strip shortens and narrows, the slots pull the destinations closer,
        // and the band tightens toward a compact floating cluster. Neither
        // axis is a scale transform — real spacing and sizes change, so touch
        // targets and rendering stay crisp at every compression.
        final slotE = math.min(66.0, (screenWidth - 24.0) / 5);
        final slot = slotE * (1.0 - _kCompress * t);
        final wideWidth = (screenWidth - 24.0).clamp(240.0, 620.0);
        _capsuleWidth = wideWidth * (1.0 - _kCompress * t);
        _slotPx = slot;
        final height = 78.0 + (58.0 - 78.0) * t;
        final active = _frac.round().clamp(0, _last);

        // Paint order: farthest from the centre first, so the scaled-up
        // centred item sits on top where it overlaps its neighbours.
        final order = List<int>.generate(widget.labels.length, (i) => i)
          ..sort((a, b) => (a - _frac).abs().compareTo((b - _frac).abs()));

        // The strip is the ONLY hit-testable surface: it joins the hit path
        // as translucent (added to the result but reporting no hit), and the
        // purely visual glyphs are wrapped in IgnorePointer, so a touch over
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
            child: SizedBox(
              width: _capsuleWidth,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Frosted-glass carrier — the dock's visible surface. It
                  // joins the inner IgnorePointer subtree, so it is purely
                  // visual: the translucent strip above it remains the
                  // dock's only hit-testable surface and vertical page
                  // scrolls still fall straight through.
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(MxRadius.lg),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: const ColoredBox(color: Colors.transparent),
                      ),
                    ),
                  ),
                  // Wash, hairline and shadow over the blur: the border
                  // stays crisp while the content scrolling behind the
                  // glass is what actually blurs (same recipe as the
                  // browser's floating top pill).
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: MxColors.creamSoft.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(MxRadius.lg),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MxColors.charcoal.withValues(alpha: 0.14),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                          iconSize: 24.0 + (19.0 - 24.0) * t,
                          labelOpacity: _labelOpacity(t),
                          slot: slot,
                          stripHeight: height,
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
        );
      },
    );
  }
}

/// One destination: a glyph floating over the dock's glass carrier. The
/// active item is tinted deep forest and carries a small brand underline and
/// caption; every other item is a quieter muted glyph. Purely visual —
/// pointer input lives on the strip so the dock never swallows a page
/// gesture.
class _DockItem extends StatelessWidget {
  const _DockItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.iconSize,
    required this.labelOpacity,
    required this.slot,
    required this.stripHeight,
    required this.opacity,
    required this.scale,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final double iconSize;
  final double labelOpacity;
  final double slot;
  final double stripHeight;
  final double opacity;
  final double scale;

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
          child: SizedBox(
            width: slot,
            height: stripHeight,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              tween: Tween<double>(end: selected ? 1 : 0),
              builder: (context, s, _) {
                // The active glyph warms from muted stone to deep forest; the
                // retarget eases as the selection moves between items while
                // dragging.
                final iconColor =
                    Color.lerp(MxColors.stone, MxColors.forest, s) ??
                    MxColors.stone;
                // The caption band is reserved on every item so glyphs sit on
                // one line; the caption itself appears only under the active
                // one, fading with the strip's compression.
                final captionOn = labelOpacity > 0.02;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: iconSize, color: iconColor),
                    const SizedBox(height: 6),
                    // A short brand underline grows beneath the active glyph.
                    SizedBox(
                      height: 3,
                      child: Opacity(
                        opacity: s,
                        child: Container(
                          width: 22,
                          height: 3,
                          decoration: BoxDecoration(
                            color: MxColors.forest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: captionOn ? 16.0 : 0.0,
                      child: Opacity(
                        opacity: s * labelOpacity,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MxType.label(
                            color: MxColors.forest,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
