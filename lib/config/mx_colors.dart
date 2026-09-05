import 'package:flutter/material.dart';

/// MYCOSIX brand design tokens — the "glow garden" identity.
///
/// Warm parchment foundation, near-black forest depths, a luminous lime
/// accent and mushroom-earth neutrals. Editorial serif display (Fraunces)
/// paired with a clean geometric sans (Manrope). Distinct from generic
/// farm/restaurant templates: dark botanical drama + one electric accent.
class MxColors {
  MxColors._();

  // Parchment foundation
  static const cream = Color(0xFFF2ECDF); // page background
  static const creamDeep = Color(0xFFE9E0CE); // raised surfaces
  static const creamSoft = Color(0xFFFBF7EE); // card surfaces
  static const parchment = Color(0xFFF6F1E6); // light wash

  // Forest depths
  static const forest = Color(0xFF1D2717); // hero, footer, dark sections
  static const forestDeep = Color(0xFF121A0E); // deepest — footer bottom
  static const forestRaised = Color(0xFF26331F); // raised dark panels

  // Greens
  static const moss = Color(0xFF4E6B36); // primary accent (on light)
  static const mossDeep = Color(0xFF3A5228); // pressed / darker
  static const mossSoft = Color(0xFFDDE6C9); // tint backgrounds
  static const mossTint = Color(0xFFEEF2E0); // lightest tint

  // Glow accent — the Gen-Z pop. Used sparingly for impact.
  static const glow = Color(0xFFD9E96E); // luminous lime
  static const glowSoft = Color(0xFFEFF6C8); // pale lime tint
  static const glowDeep = Color(0xFFB7CC3F); // deeper lime (text on cream)

  // Charcoal + mushroom / earth tones
  static const charcoal = Color(0xFF1D201A); // primary text
  static const charcoalSoft = Color(0xFF3A3E35); // secondary text
  static const stone = Color(0xFF6E7268); // muted text
  static const stoneLight = Color(0xFF9AA093); // faint text
  static const earth = Color(0xFF9C7A5B); // mushroom brown — accents
  static const earthSoft = Color(0xFFEADFD1); // brown tint
  static const oyster = Color(0xFFE9E3D8); // oyster grey

  // Functional
  static const ok = Color(0xFF4C7A4E);
  static const okSoft = Color(0xFFE4EDE0);
  static const warn = Color(0xFFB7791F);
  static const warnSoft = Color(0xFFF6EAD3);
  static const danger = Color(0xFFB4552D);
  static const dangerSoft = Color(0xFFF6E3DA);

  // Lines
  static const line = Color(0xFFE2D9C4);
  static const lineDark = Color(0xFF3A4632);
}

class MxSpace {
  MxSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
  static const xxl = 64.0;
  static const xxxl = 96.0;

  /// Horizontal page gutter for a given width.
  static double gutter(double width) {
    if (width >= 1440) return 88;
    if (width >= 1024) return 56;
    if (width >= 768) return 40;
    if (width >= 480) return 28;
    return 20;
  }
}

class MxRadius {
  MxRadius._();

  static const sm = 10.0;
  static const md = 18.0;
  static const lg = 26.0;
  static const xl = 40.0;
  static const pill = 999.0;
}

class MxDurations {
  MxDurations._();

  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 560);
  static const page = Duration(milliseconds: 420);
}

class MxEasing {
  MxEasing._();

  // A soft, natural ease — slightly decelerating.
  static const standard = Cubic(0.22, 0.61, 0.36, 1);

  // For large-scale motion (hero, sections).
  static const emo = Cubic(0.16, 1, 0.3, 1);
}
