import 'package:flutter/material.dart';

/// [MediaQuery] helpers.
class MxMedia {
  MxMedia._();

  static bool isDesktop(double width) => width >= 1024;
  static bool isTablet(double width) => width >= 768 && width < 1024;
  static bool isMobile(double width) => width < 768;

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
