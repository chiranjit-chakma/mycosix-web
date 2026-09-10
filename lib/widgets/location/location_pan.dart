/// Pure viewport geometry for the map's drag gestures, kept separate from the
/// widgets so it is unit-testable in isolation (like [location_math]).
///
/// Conventions (shared with location_math / LocationMap):
///  * Pixel offsets are measured from the map center; +x is east/right,
///    +y is south/down.
///  * The candidate under the pin tip always sits at `pin - paper` offset
///    from the map center, where [pin] is the glyph's on-screen offset and
///    [paper] the oversized map paper's translation.
library;

import 'dart:math' as math;
import 'dart:ui';

/// One step of a pin drag.
///
/// The pin glyph follows the finger freely across the whole map, and when the
/// tip reaches the map edge the map paper keeps sliding under it (the "keep
/// sliding as you drag" feel): the candidate under the tip therefore keeps
/// advancing at the full finger rate, while the glyph rests at the edge and
/// the imagery slides beneath it. Sliding stops only when the paper has
/// reached its canvas band - i.e. the candidate has travelled all the way to
/// the far edge of the loaded imagery - so a single drag can carry the pin
/// across the whole visible map and then about one more map's worth of the
/// area beyond, before the usual release (re-center) reload.
///
/// `fingerDelta` is this frame's pointer movement. `bandX`/`bandY` are the
/// paper's elastic travel limits on each axis (the imagery overhang beyond the
/// clip). `glyphInset` is how close the pin tip may sit to the clip edge.
({Offset pin, Offset paper}) slidePinDrag({
  required Offset pin,
  required Offset paper,
  required Offset fingerDelta,
  required double width,
  required double height,
  required double bandX,
  required double bandY,
  double glyphInset = 2.0,
}) {
  final loX = math.min(glyphInset, math.max(0.0, width / 2));
  final hiX = math.max(loX, width - glyphInset);
  final loY = math.min(glyphInset, math.max(0.0, height / 2));
  final hiY = math.max(loY, height - glyphInset);

  double mid(double v, double lo, double hi) =>
      math.min(math.max(v, lo), hi).toDouble();

  // Desired candidate offset: advance at the full finger rate.
  final dX = (pin.dx - paper.dx) + fingerDelta.dx;
  final dY = (pin.dy - paper.dy) + fingerDelta.dy;
  // The candidate can only reach as far as the paper will carry it: the glyph
  // is confined to the clip and the paper to +/- its band, so the reachable
  // candidate offset on each side is glyphEdge +/- band.
  final capX = mid(dX, loX - bandX, hiX + bandX);
  final capY = mid(dY, loY - bandY, hiY + bandY);
  // The glyph cannot show a candidate beyond the clip, so it rests at the
  // edge there and the difference is absorbed by the paper.
  final pinX = mid(capX, loX, hiX);
  final pinY = mid(capY, loY, hiY);
  return (
    pin: Offset(pinX, pinY),
    paper: Offset(pinX - capX, pinY - capY),
  );
}
