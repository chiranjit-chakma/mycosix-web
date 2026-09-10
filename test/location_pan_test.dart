import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/widgets/location/location_pan.dart';

void main() {
  // A 200x200 map: clip half = 100 px each side, glyph tip confined to
  // [2, 198], paper band 150 each side (0.75 * axis).
  const double w = 200, h = 200, bx = 150, by = 150;

  ({Offset pin, Offset paper}) step(
    Offset pin,
    Offset paper,
    Offset delta,
  ) => slidePinDrag(
    pin: pin,
    paper: paper,
    fingerDelta: delta,
    width: w,
    height: h,
    bandX: bx,
    bandY: by,
  );

  test('a small drag near the centre tracks the finger, paper stays still', () {
    final r = step(const Offset(10, 8), Offset.zero, const Offset(5, 3));
    expect(r.pin, const Offset(15, 11));
    expect(r.paper, Offset.zero);
  });

  test('the candidate (pin - paper) advances by the full finger delta', () {
    // Start mid-map; drag diagonally; the candidate must move exactly the
    // finger distance and never lag it while it stays inside the clip.
    final r = step(const Offset(10, 100), Offset.zero, const Offset(40, -30));
    expect(r.pin - r.paper, const Offset(50, 70));
    expect(r.paper, Offset.zero);
  });

  test('reaching the right edge keeps sliding: paper moves, candidate continues',
      () {
    // Pin near the right edge; pushing right slides the map under it.
    final r = step(const Offset(190, 100), Offset.zero, const Offset(20, 0));
    // Candidate advanced to 210, but the glyph cannot leave the clip, so it
    // rests at the right edge (198) and the paper slides -12 (map moves left
    // under the pin, revealing the area further east).
    expect(r.pin.dx, 198);
    expect(r.paper.dx, closeTo(-12, 1e-9));
    expect(r.pin - r.paper, const Offset(210, 100));
  });

  test('reaching the bottom edge slides vertically too', () {
    // Tip near the bottom (max y = 198); pushing down (south, +y) slides.
    final r = step(const Offset(100, 196), Offset.zero, const Offset(0, 10));
    expect(r.pin.dy, 198);
    expect(r.paper.dy, closeTo(-8, 1e-9));
    expect(r.pin - r.paper, const Offset(100, 206));
  });

  test('one huge drag caps at the far reach of the loaded imagery', () {
    // Dragging right thousands of pixels saturates: glyph at the right edge,
    // paper at its -band, candidate at hi + band = 198 + 150 = 348.
    final r = step(const Offset(190, 100), Offset.zero, const Offset(9000, 0));
    expect(r.pin.dx, 198);
    expect(r.paper.dx, closeTo(-150, 1e-9));
    expect((r.pin - r.paper).dx, closeTo(348, 1e-9));

    // And a huge drag left caps at lo - band = 2 - 150 = -148.
    final l = step(const Offset(10, 100), Offset.zero, const Offset(-9000, 0));
    expect(l.pin.dx, 2);
    expect(l.paper.dx, closeTo(150, 1e-9));
    expect((l.pin - l.paper).dx, closeTo(-148, 1e-9));
  });

  test('paper and glyph both stay inside their bounds on every step', () {
    final rnd = math.Random(7);
    var pin = const Offset(0, 0);
    var paper = Offset.zero;
    for (var i = 0; i < 4000; i++) {
      final delta = Offset(
        (rnd.nextDouble() * 400 - 200) * 4,
        (rnd.nextDouble() * 400 - 200) * 4,
      );
      final r = step(pin, paper, delta);
      pin = r.pin;
      paper = r.paper;
      // Glyph tip never leaves the clip.
      expect(pin.dx, inInclusiveRange(2.0, 198.0));
      expect(pin.dy, inInclusiveRange(2.0, 198.0));
      // Paper never leaves its band (imagery always covers the clip).
      expect(paper.dx.abs(), lessThanOrEqualTo(150.0 + 1e-9));
      expect(paper.dy.abs(), lessThanOrEqualTo(150.0 + 1e-9));
    }
  });

  test('a drag that overshoots can be dragged back the other way', () {
    // Slide fully right, then drag back left a little: the candidate comes
    // back off the cap and the paper relaxes.
    final r = step(const Offset(190, 100), Offset.zero, const Offset(9000, 0));
    final back = step(r.pin, r.paper, const Offset(-100, 0));
    expect(back.paper.dx, closeTo(-50, 1e-9));
    expect((back.pin - back.paper).dx, closeTo(248, 1e-9));
  });
}
