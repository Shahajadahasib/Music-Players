import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Consistent iOS-style bounce + smooth scrolling on all platforms.
class AuroraScrollBehavior extends MaterialScrollBehavior {
  const AuroraScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}
