import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import 'footer.dart';
import 'top_bar.dart';

/// Master layout: floating top bar over a scrolling page + footer.
///
/// Owns scroll state and passes it to [MxTopBar].
class MxShell extends StatefulWidget {
  const MxShell({super.key, required this.child, this.showFooter = true});

  final Widget child;
  final bool showFooter;

  @override
  State<MxShell> createState() => _MxShellState();
}

class _MxShellState extends State<MxShell> {
  bool _scrolled = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _handleScroll(ScrollNotification notification) {
    final scrolled = notification.metrics.pixels > 24;
    if (scrolled != _scrolled && mounted) {
      setState(() => _scrolled = scrolled);
    }
    return false;
  }

  void openDrawer() {
    // The scaffold is this widget's descendant, so Scaffold.of(context) can't
    // find it — use the key directly.
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: MxColors.cream,
      endDrawer: const MxDrawer(),
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: Stack(
          children: [
            Positioned.fill(
              child: Scrollbar(
                thumbVisibility: width >= 1024,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: Column(
                    children: [
                      widget.child,
                      if (widget.showFooter) const MxFooter(),
                    ],
                  ),
                ),
              ),
            ),
            // Floating top bar — taps pass through where it is transparent.
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: false,
                child: MxTopBar(
                  scrolled: _scrolled,
                  onMenu: openDrawer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
