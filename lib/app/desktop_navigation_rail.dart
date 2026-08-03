import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'adaptive_split_layout.dart';

class DesktopNavigationDestination {
  const DesktopNavigationDestination({required this.label, required this.icon});

  final String label;
  final AppIconData icon;
}

/// Project-owned desktop navigation chrome. The compact icon rail replaces the
/// phone tab bar without changing the tab state or its nested navigators.
class DesktopNavigationRail extends StatelessWidget {
  const DesktopNavigationRail({
    super.key,
    required this.destinations,
    required this.selection,
    required this.onSelect,
    required this.unread,
    required this.onClearUnread,
  });

  final List<DesktopNavigationDestination> destinations;
  final int selection;
  final ValueChanged<int> onSelect;
  final int unread;
  final VoidCallback onClearUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('desktop-navigation-rail'),
      width: desktopNavigationRailWidth,
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(
          right: BorderSide(color: c.divider, width: AppMetric.divider),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        itemCount: destinations.length,
        itemBuilder: (context, index) {
          final destination = destinations[index];
          return _DesktopNavigationButton(
            key: ValueKey('desktop-navigation-item-$index'),
            destination: destination,
            selected: selection == index,
            unread: index == 0 ? unread : 0,
            onClearUnread: onClearUnread,
            onTap: () => onSelect(index),
          );
        },
      ),
    );
  }
}

class _DesktopNavigationButton extends StatelessWidget {
  const _DesktopNavigationButton({
    super.key,
    required this.destination,
    required this.selected,
    required this.unread,
    required this.onClearUnread,
    required this.onTap,
  });

  final DesktopNavigationDestination destination;
  final bool selected;
  final int unread;
  final VoidCallback onClearUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedPositionedDirectional(
            duration: AppMotion.duration(context, AppMotion.responsive),
            curve: AppMotion.standard,
            start: 0,
            top: selected ? 13 : 24,
            bottom: selected ? 13 : 24,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? AppTheme.brand : Colors.transparent,
                borderRadius: const BorderRadiusDirectional.horizontal(
                  end: Radius.circular(3),
                ),
              ),
            ),
          ),
          Tooltip(
            message: destination.label,
            waitDuration: const Duration(milliseconds: 450),
            child: AppInteractiveSurface(
              semanticLabel: destination.label,
              selected: selected,
              onTap: onTap,
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.responsive),
                curve: AppMotion.standard,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.brand.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AppIcon(
                      destination.icon,
                      size: 23,
                      color: selected ? AppTheme.brand : c.textSecondary,
                    ),
                    if (unread > 0)
                      PositionedDirectional(
                        top: 2,
                        end: 2,
                        child: UnreadBadge(
                          count: unread,
                          onClear: onClearUnread,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
