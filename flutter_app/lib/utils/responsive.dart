import 'package:flutter/material.dart';

/// Wraps Scaffold body content with SafeArea and a max-width constraint
/// so layouts look great on both mobile and desktop.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveBody({super.key, required this.child, this.maxWidth = 700});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
