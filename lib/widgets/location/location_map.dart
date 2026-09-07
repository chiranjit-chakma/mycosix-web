import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';

/// Interactive map pane for choosing a delivery location.
///
/// The Google Maps embed stays centered on the candidate coordinate. A gesture
/// layer above the iframe lets the user drag or tap: pixel offsets are
/// converted to geographic deltas (Web-Mercator) and a fresh embed is centered
/// on the new coordinate. The pin always marks the exact candidate.
///
/// A +/− zoom control (street level 14 .. 20, default 17) re-centers the embed
/// on the candidate at the new zoom, so customers can zoom right down to their
/// building and set the pin precisely.
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
  /// Zoom bounds for the embed. 20 is close enough to read a building outline;
  /// 14 still shows the surrounding streets so the customer can find their
  /// block first.
  static const int minZoom = 14;
  static const int maxZoom = 20;
  int _zoom = 17;

  Offset _dragOffset = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    // The iframe uses the embed endpoint (output=embed); a plain google.com/maps
    // URL is not reliably frameable and can bounce through consent redirects.
    final src = MxConfig.mapsEmbedUrl
        .replaceAll('{lat}', widget.latitude.toStringAsFixed(6))
        .replaceAll('{lng}', widget.longitude.toStringAsFixed(6))
        .replaceFirst('z=16', 'z=$_zoom');

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MxRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The embed (centered at the candidate).
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_dragOffset.dx, _dragOffset.dy, 0),
              child: _MapFrame(src: src),
            ),
            // Gesture layer: drag to move, tap to re-center.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (details) {
                  setState(() => _dragOffset += details.delta);
                },
                onPanEnd: (_) => _commitDrag(),
                onPanCancel: () => _commitDrag(),
                onTapUp: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  final w = box?.size.width ?? MediaQuery.of(context).size.width;
                  final h = box?.size.height ?? widget.height;
                  final center = Offset(w / 2, h / 2);
                  final delta = details.localPosition - center;
                  widget.onChanged(_offsetToGeo(delta));
                },
              ),
            ),
            // Center pin (visual only).
            const IgnorePointer(
              child: Center(
                child: _Pin(),
              ),
            ),
            // Coordinate pill.
            Positioned(
              left: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: MxColors.cream.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(color: MxColors.charcoal.withValues(alpha: 0.15), blurRadius: 12),
                    ],
                  ),
                  child: Text(
                    '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
                    style: MxType.bodyXs(
                      color: MxColors.charcoal,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            // Zoom control (+ / −). Re-centers the embed on the candidate at
            // the new zoom, so the customer can zoom into their street and set
            // the pin precisely. Sits above the gesture layer, so taps on it
            // never drag the map.
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _ZoomButton(
                    key: const Key('map-zoom-in'),
                    icon: Icons.add_rounded,
                    tooltip: 'Zoom in',
                    onTap: _zoom >= maxZoom
                        ? null
                        : () => setState(() => _zoom += 1),
                  ),
                  const SizedBox(height: 8),
                  _ZoomButton(
                    key: const Key('map-zoom-out'),
                    icon: Icons.remove_rounded,
                    tooltip: 'Zoom out',
                    onTap: _zoom <= minZoom
                        ? null
                        : () => setState(() => _zoom -= 1),
                  ),
                ],
              ),
            ),
            // Hint pill (kept clear of the zoom control on narrow maps).
            Positioned(
              top: 12,
              left: 52,
              right: 52,
              child: Center(
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: MxColors.charcoal.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _dragging
                          ? 'Release to set the pin'
                          : 'Drag the map or use + / − to zoom',
                      style: MxType.bodyXs(
                        color: Colors.white,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commitDrag() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      final geo = _offsetToGeo(_dragOffset);
      _dragOffset = Offset.zero;
      widget.onChanged(geo);
    });
  }

  /// Converts a pixel offset from the widget center into a geographic delta.
  ///
  /// The drag offset is measured relative to this map's own [context] size,
  /// so the tile is converted with the widget's actual [RenderBox] extents.
  (double, double) _offsetToGeo(Offset offset) {
    final box = context.findRenderObject() as RenderBox?;
    final w = box?.size.width ?? MediaQuery.of(context).size.width;
    final h = box?.size.height ?? widget.height;
    final center = Offset(w / 2, h / 2);
    final dx = offset.dx - center.dx;
    final dy = offset.dy - center.dy;

    final latRad = widget.latitude * math.pi / 180;
    final mpp =
        156543.03392 * math.cos(latRad) / math.pow(2, _zoom);
    final latDelta = -dy * mpp / 111320.0;
    final lngDelta = dx * mpp / (111320.0 * math.cos(latRad));

    final newLat = (widget.latitude + latDelta).clamp(-85.0, 85.0);
    final newLng = widget.longitude + lngDelta;
    return (newLat, newLng);
  }
}

/// A circular zoom button (Google-Maps-style + / −) that floats over the map.
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

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on_rounded,
          size: 40,
          color: MxColors.danger,
          shadows: [Shadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 6)],
        ),
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: MxColors.danger,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

/// HTML iframe embedding Google Maps, registered as a Flutter platform view.
class _MapFrame extends StatelessWidget {
  const _MapFrame({required this.src});

  final String src;

  @override
  Widget build(BuildContext context) {
    // A unique viewType per src forces a fresh iframe when the center moves.
    final viewType = 'mx-map-${_simpleHash(src)}';
    final manager = _frameManager(src);
    return SizedBox.expand(
      child: _PlatformView(viewType: viewType, src: src, manager: manager),
    );
  }

  static int _simpleHash(String s) {
    var h = 0;
    for (var i = 0; i < s.length; i++) {
      h = (h * 31 + s.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }
}

// Registry of created iframes, so a rebuilt widget reuses its live iframe.
final Map<String, web.HTMLIFrameElement> _liveFrames = {};
final Map<String, String> _registered = {};

class _PlatformView extends StatefulWidget {
  const _PlatformView({required this.viewType, required this.src, required this.manager});

  final String viewType;
  final String src;
  final Map<String, web.HTMLIFrameElement> manager;

  @override
  State<_PlatformView> createState() => _PlatformViewState();
}

class _PlatformViewState extends State<_PlatformView> {
  @override
  Widget build(BuildContext context) {
    _ensureRegistered(widget.viewType, widget.src);
    return HtmlElementView(viewType: widget.viewType);
  }
}

void _ensureRegistered(String viewType, String src) {
  if (_registered[viewType] == src) return;
  _registered[viewType] = src;
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final frame = web.HTMLIFrameElement();
    frame.src = src;
    frame.style.border = 'none';
    frame.style.width = '100%';
    frame.style.height = '100%';
    frame.style.pointerEvents = 'none';
    _liveFrames[viewType] = frame;
    return frame;
  });
}

// ignore: unused_element
Map<String, web.HTMLIFrameElement> _frameManager(String src) => _liveFrames;
