import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'desktop_window_drag_area.dart';

/// Flutter-owned chrome for the primary macOS window.
///
/// The native traffic-light controls remain visible in the leading clearance.
/// Only the intentionally blank middle region moves the window, keeping the
/// identity slots available for interactive controls.
class MacosDesktopTitleBar extends StatelessWidget {
  const MacosDesktopTitleBar({
    super.key,
    required this.appIdentity,
    this.accountIdentity,
    this.backgroundColor,
  });

  static const double height = 40;
  static const double trafficLightLeadingClearance = 78;
  static const double identityGap = 12;
  static const double trailingPadding = 12;
  static const double dividerWidth = 0.5;

  final Widget appIdentity;
  final Widget? accountIdentity;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountIdentity = this.accountIdentity;

    return SizedBox(
      key: const ValueKey('macos-desktop-title-bar'),
      height: height,
      child: DecoratedBox(
        key: const ValueKey('macos-desktop-title-bar-decoration'),
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.navBar,
          border: Border(
            bottom: BorderSide(color: colors.divider, width: dividerWidth),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              key: ValueKey('macos-traffic-light-clearance'),
              width: trafficLightLeadingClearance,
            ),
            KeyedSubtree(
              key: const ValueKey('macos-app-identity'),
              child: appIdentity,
            ),
            const SizedBox(width: identityGap),
            Expanded(
              child: desktopWindowDragArea(
                child: const SizedBox.expand(
                  key: ValueKey('macos-title-bar-drag-area'),
                ),
              ),
            ),
            if (accountIdentity != null) ...[
              const SizedBox(width: identityGap),
              KeyedSubtree(
                key: const ValueKey('macos-account-identity'),
                child: accountIdentity,
              ),
            ],
            const SizedBox(width: trailingPadding),
          ],
        ),
      ),
    );
  }
}
