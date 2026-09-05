import 'package:flutter/material.dart';
import 'mx_colors.dart';

/// Typography scale — editorial serif display (Fraunces) + geometric sans
/// (Manrope). All sizes are fluid: they scale between phone and desktop.
class MxType {
  MxType._();

  /// Display sizes — Fraunces serif, tight leading, editorial feel.
  static TextStyle display(double width, {Color color = MxColors.charcoal}) {
    final s = _fluid(width, 44, 92);
    return TextStyle(
      fontFamily: 'Fraunces',
      fontSize: s,
      height: 1.02,
      letterSpacing: -1.4,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }

  static TextStyle displayAlt(double width, {Color color = MxColors.charcoal}) {
    final s = _fluid(width, 40, 76);
    return TextStyle(
      fontFamily: 'Fraunces',
      fontSize: s,
      height: 1.04,
      letterSpacing: -1.0,
      fontWeight: FontWeight.w400,
      color: color,
    );
  }

  static TextStyle h1(double width, {Color color = MxColors.charcoal}) {
    final s = _fluid(width, 32, 56);
    return TextStyle(
      fontFamily: 'Fraunces',
      fontSize: s,
      height: 1.06,
      letterSpacing: -0.8,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }

  static TextStyle h2(double width, {Color color = MxColors.charcoal}) {
    final s = _fluid(width, 26, 40);
    return TextStyle(
      fontFamily: 'Fraunces',
      fontSize: s,
      height: 1.12,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }

  static TextStyle h3({Color color = MxColors.charcoal}) => TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 21,
        height: 1.2,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle h4({Color color = MxColors.charcoal}) => TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: color,
      );

  // Body — Manrope.
  static TextStyle body(double width,
          {Color color = MxColors.charcoalSoft, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: _fluid(width, 15, 17),
        height: 1.55,
        fontWeight: weight,
        color: color,
      );

  static TextStyle bodySm({
    Color color = MxColors.charcoalSoft,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13.5,
        height: 1.5,
        fontWeight: weight,
        color: color,
      );

  static TextStyle bodyXs({
    Color color = MxColors.stone,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        height: 1.45,
        fontWeight: weight,
        color: color,
      );

  static TextStyle label({Color color = MxColors.moss, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0.18,
        fontWeight: weight,
        color: color,
      );

  static TextStyle labelLg(
          {Color color = MxColors.moss, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        height: 1.2,
        letterSpacing: 0.22,
        fontWeight: weight,
        color: color,
      );

  static TextStyle overline({Color color = MxColors.earth, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        height: 1.3,
        letterSpacing: 0.3,
        fontWeight: weight,
        color: color,
      );

  /// Fluid clamp between [min] and [max], tuned on a 360..1440 viewport.
  static double _fluid(double width, double min, double max) {
    const lo = 360.0;
    const hi = 1440.0;
    final t = ((width - lo) / (hi - lo)).clamp(0.0, 1.0);
    return min + (max - min) * t;
  }
}
