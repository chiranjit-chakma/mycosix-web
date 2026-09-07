import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';
import 'location_math.dart';

/// Interactive map pane for choosing a delivery location.
///
/// The Google Maps embed is an ordinary no-key iframe that stays centered on
/// the map's anchor coordinate. A cross-origin embed can never report its own
/// gestures, so a gesture layer above the iframe implements the map feel:
///
///  * Drag empty map space: the map paper slides under the customer's finger;
///    releasing re-centers the embed on the spot now under the pin.
///  * Tap anywhere: drops the pin exactly under the finger (no reload).
///  * Drag the pin: fine-tunes the spot without any reload.
///  * + / - zoom (street level 14 .. 20) scales around the pin's spot, so the
///    customer can zoom right down to their building without losing it.
///
/// The pin marks the exact candidate in every state. Re-centering the embed
/// (a pan release, a zoom step, or an external move such as GPS) swaps the
/// iframe's src and shows a short "Updating map..." veil until the fresh
/// embed reports that it loaded, so the old imagery never flashes white or
/// visibly slides back in front of the customer. The iframe is created once
/// per map instance and reused for its whole life, so moving around never
/// leaks orphaned frames.
class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    this.height = 320,
  });

  final double latitude;
  final double longitude;
  final ValueChanged<(double, double)> onChanged;
  final double height;

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  /// Zoom bounds for the embed. 20 is close enough to read a building
  /// outline; 14 still shows the surrounding streets so the customer can
  /// find their block first.
  static const int minZoom = 14;
  static const int maxZoom = 20;
  static const int initialZoom = 17;

  static int _nextInstance = 0;

  /// One viewType per mounted map keeps the platform view stable for the
  /// map's whole life (the iframe is reused, never recreated per move).
  late final String _viewType;

  /// Where the embed is actually centered, which is also where the candidate
  /// lives whenever the pin sits in the middle. Coordinates from the parent
  /// only move this anchor when they are not a round-trip echo of the map's
  /// own last commit.
  late double _centerLat;
  late double _centerLng;

  /// The last candidate this map told the parent about. Used to tell a
  /// parent echo (setCandidate -> rebuild with the same value) apart from a
  /// genuine external move (GPS, another entry point), so round trips never
  /// reload the embed.
  late double _emitLat;
  late double _emitLng;

  int _zoom = initialZoom;

  /// Pin tip, in pixels from the map center (the pointed end).
  Offset _pin = Offset.zero;

  /// Current map-paper translation while the customer drags empty space.
  Offset _paper = Offset.zero;

  bool _pinDrag = false;
  bool _paperDrag = false;

  /// True while the embed is loading or being re-centered; the veil absorbs
  /// all pointers so gestures can never desync from the imagery.
  bool _busy = true;
  bool _everLoaded = false;
  Timer? _loadFallback;

  Size _size = Size.zero;

  /// How close to the pin tip a touch counts as grabbing the pin (touch
  /// friendly without stealing drags that clearly start on empty map space).
  static const double _grabRadius = 30;

  @override
  void initState() {
    super.initState();
    _viewType = 'mx-locmap-${_nextInstance++}';
    _centerLat = widget.latitude;
    _centerLng = widget.longitude;
    _emitLat = widget.latitude;
    _emitLng = widget.longitude;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createFrame);
    _pendingSrc[_viewType] = _embedSrc();
    // Safety net: if the embed never fires a load event (blocked network,
    // odd browser), lift the veil so the map is never stuck behind it.
    _loadFallback = Timer(const Duration(seconds: 8), _finishLoad);
  }

  @override
  void dispose() {
    _loadFallback?.cancel();
    _loadFallback = null;
    _pendingSrc.remove(_viewType);
    _frames.remove(_viewType);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat == _emitLat && lng == _emitLng) return; // Echo of our own commit.
    // A genuine external move (GPS, another entry point): jump the whole map.
    setState(() {
      _centerLat = lat;
      _centerLng = lng;
      _emitLat = lat;
      _emitLng = lng;
      _pin = Offset.zero;
      _paper = Offset.zero;
      _reload();
    });
  }

  double get _mpp => metersPerPixelAt(_centerLat, _zoom);

  /// Degrees of latitude at a screen offset [dyPx] below the map center.
  double _latAt(double dyPx) => _centerLat + latitudeDeltaForPixels(dyPx, _mpp);

  /// Degrees of longitude at a screen offset [dxPx] right of the map center.
  double _lngAt(double dxPx) =>
      _centerLng + longitudeDeltaForPixels(dxPx, _mpp, _centerLat);

  (double, double) _clamped(double lat, double lng) =>
      (lat.clamp(-85.0, 85.0), lng.clamp(-180.0, 180.0));

  Offset _centerPx() => Offset(_size.width / 2, _size.height / 2);

  bool _onPin(Offset local) =>
      (local - _centerPx() - _pin).distance <= _grabRadius;

  Offset _clampTip(Offset tip) => Offset(
    tip.dx.clamp(2.0, math.max(2.0, _size.width - 2)),
    tip.dy.clamp(2.0, math.max(2.0, _size.height - 2)),
  );

  String _embedSrc() => MxConfig.mapsEmbedUrl
      .replaceAll('{lat}', _centerLat.toStringAsFixed(6))
      .replaceAll('{lng}', _centerLng.toStringAsFixed(6))
      .replaceFirst('z=16', 'z=$_zoom');

  web.HTMLIFrameElement _createFrame(int viewId) {
    final frame = web.HTMLIFrameElement();
    frame.style.border = 'none';
    frame.style.width = '100%';
    frame.style.height = '100%';
    frame.style.display = 'block';
    frame.style.pointerEvents = 'none';
    frame.src = _pendingSrc[_viewType] ?? _embedSrc();
    _frames[_viewType] = frame;
    frame.addEventListener(
      'load',
      ((web.Event _) {
        if (!mounted) return;
        final f = _frames[_viewType];
        // Only the load of the src this map is currently asking for may lift
        // the veil; a stale load (superseded mid-flight) must not.
        if (f != null && f.src == _embedSrc()) _finishLoad();
      }).toJS,
    );
    return frame;
  }

  void _reload() {
    _busy = true;
    _loadFallback?.cancel();
    _loadFallback = Timer(const Duration(seconds: 6), _finishLoad);
    final frame = _frames[_viewType];
    if (frame == null) {
      _pendingSrc[_viewType] = _embedSrc();
      return;
    }
    final want = _embedSrc();
    if (frame.src == want) {
      _finishLoad();
      return;
    }
    frame.src = want;
  }

  void _finishLoad() {
    _loadFallback?.cancel();
    _loadFallback = null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _everLoaded = true;
    });
  }

  /// Tells the parent about a new candidate. Moves smaller than one pixel
  /// are treated as no-ops so micro-jitter never reloads the embed or
  /// re-saves the location.
  void _emit(double lat, double lng, {required bool recenter}) {
    final mpp = _mpp;
    final kLat = mpp / 111320.0;
    final kLng = kLat / math.cos(_centerLat * math.pi / 180);
    final pxDx = (lng - _emitLng) / kLng;
    final pxDy = (lat - _emitLat) / kLat;
    if (math.max(pxDx.abs(), pxDy.abs()) < 1.0) return;

    setState(() {
      _emitLat = lat;
      _emitLng = lng;
      if (recenter) {
        // The spot under the pin becomes the new center: re-anchor the
        // embed there, pin back to the middle, paper back to rest.
        _centerLat = lat;
        _centerLng = lng;
        _pin = Offset.zero;
        _paper = Offset.zero;
        _reload();
      }
    });
    widget.onChanged((lat, lng));
  }

  void _zoomBy(int step) {
    final next = _zoom + step;
    if (_busy || next < minZoom || next > maxZoom) return;
    final mppNext = metersPerPixelAt(_centerLat, next);
    final pinGeo = _clamped(_latAt(_pin.dy), _lngAt(_pin.dx));
    final centerLat = centerLatitudeForPin(pinGeo.$1, _pin.dy, mppNext);
    final centerLng = centerLongitudeForPin(
      pinGeo.$2,
      _pin.dx,
      mppNext,
      centerLat,
    );
    setState(() {
      _zoom = next;
      // Keep the spot under the pin exactly where it is: re-anchor the
      // center at the new scale so the pin's spot never drifts under zoom.
      _centerLat = centerLat;
      _centerLng = centerLng;
      _reload();
    });
  }

  // --- Gestures ------------------------------------------------------------

  void _onPanStart(DragStartDetails details) {
    setState(() {
      if (_onPin(details.localPosition)) {
        _pinDrag = true;
        _paperDrag = false;
      } else {
        _paperDrag = true;
        _pinDrag = false;
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      if (_pinDrag) {
        _pin = _clampTip(_pin + details.delta);
      } else if (_paperDrag) {
        _paper += details.delta;
      }
    });
  }

  void _onPanEnd() {
    if (_pinDrag) {
      setState(() => _pinDrag = false);
      final (lat, lng) = _clamped(_latAt(_pin.dy), _lngAt(_pin.dx));
      _emit(lat, lng, recenter: false);
      return;
    }
    if (_paperDrag) {
      setState(() => _paperDrag = false);
      if (_paper == Offset.zero) return;
      // The paper moved by [_paper], so the imagery now under the pin tip
      // came from (pin - paper): the spot the embed must re-center on.
      final tip = _pin - _paper;
      final (lat, lng) = _clamped(_latAt(tip.dy), _lngAt(tip.dx));
      _paper = Offset.zero;
      _emit(lat, lng, recenter: true);
    }
  }

  void _onTapUp(TapUpDetails details) {
    final q = details.localPosition - _centerPx();
    if ((q - _pin).distance < 8) return; // Already exactly there.
    setState(() {
      _pin = _clampTip(q);
    });
    final (lat, lng) = _clamped(_latAt(_pin.dy), _lngAt(_pin.dx));
    _emit(lat, lng, recenter: false);
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MxRadius.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            final c = _centerPx();
            final dragging = _pinDrag || _paperDrag;
            return Stack(
              fit: StackFit.expand,
              children: [
                // The embed, translated while the customer drags the paper.
                Transform.translate(
                  offset: _paper,
                  child: HtmlElementView(viewType: _viewType),
                ),
                // Gesture layer: map drag, pin drag, tap to drop.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: (_) => _onPanEnd(),
                    onPanCancel: _onPanEnd,
                    onTapUp: _onTapUp,
                  ),
                ),
                // The pin, tip-anchored at [_pin]. It stays put while the
                // paper moves and follows the finger only when grabbed.
                Positioned(
                  left: c.dx + _pin.dx - 20,
                  top: c.dy + _pin.dy - 40, // Box bottom edge sits on the tip.
                  width: 40,
                  height: 40,
                  child: IgnorePointer(child: _Pin()),
                ),
                // Reload veil: opaque while the embed re-centers so the old
                // imagery never contradicts the gesture just made; inert
                // (and transparent) the rest of the time.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_busy,
                    child: AnimatedOpacity(
                      opacity: _busy ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: ColoredBox(
                        color: MxColors.cream,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: MxColors.forest,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _everLoaded
                                    ? 'Updating map...'
                                    : 'Loading map...',
                                style: MxType.bodySm(
                                  color: MxColors.stone,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Hint pill while a gesture is in flight; hidden when the
                // map is idle or updating so it never sits there empty.
                if (dragging)
                  Positioned(
                    top: 12,
                    left: 52,
                    right: 52,
                    child: Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: MxColors.charcoal.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Release to set the pin',
                            style: MxType.bodyXs(
                              color: Colors.white,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Zoom control (+ / -), above the gesture layer so its taps
                // never drag the map; disabled while the map is updating.
                Positioned(
                  top: 12,
                  right: 12,
                  child: Column(
                    children: [
                      _ZoomButton(
                        key: const Key('map-zoom-in'),
                        icon: Icons.add_rounded,
                        tooltip: 'Zoom in',
                        onTap: _busy || _zoom >= maxZoom
                            ? null
                            : () => _zoomBy(1),
                      ),
                      const SizedBox(height: 8),
                      _ZoomButton(
                        key: const Key('map-zoom-out'),
                        icon: Icons.remove_rounded,
                        tooltip: 'Zoom out',
                        onTap: _busy || _zoom <= minZoom
                            ? null
                            : () => _zoomBy(-1),
                      ),
                    ],
                  ),
                ),
                // Coordinate pill, always live: it shows the pin's current
                // spot, and during a map drag the spot it will land on.
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: MxColors.cream.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: MxColors.charcoal.withValues(alpha: 0.15),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Text(
                        _pillText(),
                        style: MxType.bodyXs(
                          color: MxColors.charcoal,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _pillText() {
    Offset spot = _pin;
    if (_paperDrag) spot = _pin - _paper;
    final (lat, lng) = _clamped(_latAt(spot.dy), _lngAt(spot.dx));
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }
}

// Registry of live iframes, one entry per mounted map. The iframe for a
// map's viewType is created once, on the map's first layout, and is then
// reused for every re-center for the rest of the map's life; entries are
// dropped when the map disposes so long sessions never pile up frames.
final Map<String, web.HTMLIFrameElement> _frames =
    <String, web.HTMLIFrameElement>{};
final Map<String, String> _pendingSrc = <String, String>{};

/// A circular zoom button (Google-Maps-style + / -) that floats over the
/// map. Disabled (via a null [onTap]) at the zoom bounds and while the map
/// is re-centering.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: MxColors.cream,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: MxColors.charcoal.withValues(alpha: 0.25),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null ? MxColors.stoneLight : MxColors.forest,
            ),
          ),
        ),
      ),
    );
  }
}

/// The delivery pin. Its pointed tip, at the bottom center of the glyph,
/// marks the exact spot: the pin's box is positioned so that the tip lands
/// on the candidate pixel the math talks about.
class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Icon(
        Icons.location_on_rounded,
        size: 40,
        color: MxColors.danger,
        shadows: [
          Shadow(color: Colors.white.withValues(alpha: 0.92), blurRadius: 7),
        ],
      ),
    );
  }
}
