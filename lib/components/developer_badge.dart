//
//  developer_badge.dart
//
//  Blue check that marks the Telegram accounts of Mithka's developers. It sits
//  on the bottom-right of their avatar in chats and on their profile; on the
//  profile it can be tapped to explain what it means.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Telegram user ids of the people who build and maintain Mithka.
const Set<int> mithkaDeveloperUserIds = {
  5555116287,
  7041948142,
  176871465,
  5896096480,
  5754487330,
};

bool isMithkaDeveloper(int? userId) =>
    userId != null && mithkaDeveloperUserIds.contains(userId);

/// Overlays [DeveloperBadge] on the bottom-right of a developer's avatar.
///
/// Use [DeveloperAvatarBadge.wrap] at call sites: it returns the avatar
/// untouched for everyone else, so dense lists don't gain a widget per row.
class DeveloperAvatarBadge extends StatelessWidget {
  const DeveloperAvatarBadge({
    super.key,
    required this.userId,
    required this.avatarSize,
    required this.child,
    this.interactive = false,
  });

  final int? userId;
  final double avatarSize;
  final Widget child;

  /// Whether tapping the badge explains it in a bubble. Chat rows leave this
  /// off so the avatar keeps its own tap and long-press behaviour.
  final bool interactive;

  static Widget wrap({
    required int? userId,
    required double avatarSize,
    required Widget child,
    bool interactive = false,
  }) => isMithkaDeveloper(userId)
      ? DeveloperAvatarBadge(
          userId: userId,
          avatarSize: avatarSize,
          interactive: interactive,
          child: child,
        )
      : child;

  static double badgeSizeFor(double avatarSize) =>
      (avatarSize * 0.3).clamp(14.0, 24.0);

  @override
  Widget build(BuildContext context) {
    if (!isMithkaDeveloper(userId)) return child;
    final size = badgeSizeFor(avatarSize);
    final badge = DeveloperBadge(size: size);
    // Centre the badge on the circle's edge at the bottom-right diagonal, so
    // it hugs a round avatar instead of floating off its bounding box corner.
    final inset = math.max(0.0, avatarSize / 2 * (1 - math.sqrt1_2) - size / 2);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: inset,
          bottom: inset,
          child: interactive ? DeveloperBadgeInfoTarget(child: badge) : badge,
        ),
      ],
    );
  }
}

/// A blue disc with a white check, ringed in the surface colour so it reads as
/// cut out of the avatar it overlaps.
class DeveloperBadge extends StatelessWidget {
  const DeveloperBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStringKeys.developerBadgeTitle.l10n(context),
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _DeveloperBadgePainter(ring: context.colors.card),
        ),
      ),
    );
  }
}

class _DeveloperBadgePainter extends CustomPainter {
  const _DeveloperBadgePainter({required this.ring});

  final Color ring;

  static const _top = Color(0xFF4DB5FF);
  static const _bottom = Color(0xFF1484F5);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final radius = side / 2;
    final ringWidth = math.max(1.5, side * 0.1);

    canvas.drawCircle(center, radius, Paint()..color = ring);

    final disc = Rect.fromCircle(center: center, radius: radius - ringWidth);
    canvas.drawCircle(
      center,
      disc.width / 2,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_top, _bottom],
        ).createShader(disc),
    );

    final check = Path()
      ..moveTo(disc.left + disc.width * 0.28, disc.top + disc.height * 0.52)
      ..lineTo(disc.left + disc.width * 0.44, disc.top + disc.height * 0.67)
      ..lineTo(disc.left + disc.width * 0.73, disc.top + disc.height * 0.37);
    canvas.drawPath(
      check,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, disc.width * 0.13)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DeveloperBadgePainter oldDelegate) =>
      oldDelegate.ring != ring;
}

/// Makes [child] tappable and shows the developer explanation in a bubble
/// pointing at it. The bubble closes on a second tap, a tap anywhere else, or
/// after a few seconds.
class DeveloperBadgeInfoTarget extends StatefulWidget {
  const DeveloperBadgeInfoTarget({super.key, required this.child});

  final Widget child;

  static const autoDismissAfter = Duration(seconds: 4);

  @override
  State<DeveloperBadgeInfoTarget> createState() =>
      _DeveloperBadgeInfoTargetState();
}

class _DeveloperBadgeInfoTargetState extends State<DeveloperBadgeInfoTarget> {
  final _controller = OverlayPortalController();
  final Object _tapGroup = Object();
  Timer? _dismissTimer;

  void _toggle() {
    if (_controller.isShowing) {
      _hide();
      return;
    }
    _controller.show();
    _dismissTimer?.cancel();
    _dismissTimer = Timer(DeveloperBadgeInfoTarget.autoDismissAfter, _hide);
  }

  void _hide() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (mounted && _controller.isShowing) _controller.hide();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _controller,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        return TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _hide(),
          child: _DeveloperBadgeBubble(
            anchor: anchor,
            overlaySize: info.overlaySize,
            onTap: _hide,
          ),
        );
      },
      child: TapRegion(
        groupId: _tapGroup,
        child: Semantics(
          button: true,
          child: GestureDetector(
            key: const ValueKey('developerBadgeTapTarget'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _DeveloperBadgeBubble extends StatelessWidget {
  const _DeveloperBadgeBubble({
    required this.anchor,
    required this.overlaySize,
    required this.onTap,
  });

  final Rect anchor;
  final Size overlaySize;
  final VoidCallback onTap;

  static const _fill = Color(0xF2272A2E);
  static const _gap = 4.0;
  static const _arrowWidth = 14.0;
  static const _arrowHeight = 7.0;
  static const _edgeInset = 12.0;
  static const _maxWidth = 280.0;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    // Open upwards like the reference tooltip, unless that would run under
    // the status bar.
    final above = anchor.top - padding.top > 96;
    final arrowTop = above
        ? anchor.top - _gap - _arrowHeight
        : anchor.bottom + _gap;
    final bodyEdge = above ? arrowTop : arrowTop + _arrowHeight;
    final arrowLeft = anchor.center.dx - _arrowWidth / 2;

    final body = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        // Keeps the edge visible when the bubble sits on a dark surface.
        border: Border.all(color: const Color(0x1FFFFFFF), width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStringKeys.developerBadgeTitle.l10n(context),
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppStringKeys.developerBadgeDescription.l10n(context),
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Color(0xE6FFFFFF),
            ),
          ),
        ],
      ),
    );

    return _BubbleEntrance(
      origin:
          Offset(anchor.center.dx, above ? anchor.top : anchor.bottom) -
          overlaySize.center(Offset.zero),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomSingleChildLayout(
            delegate: _BubbleBodyLayout(
              anchorX: anchor.center.dx,
              edge: bodyEdge,
              above: above,
              edgeInset: _edgeInset,
              maxWidth: _maxWidth,
            ),
            child: GestureDetector(
              key: const ValueKey('developerBadgeBubble'),
              onTap: onTap,
              child: body,
            ),
          ),
          Positioned(
            left: arrowLeft,
            top: arrowTop,
            width: _arrowWidth,
            height: _arrowHeight,
            child: CustomPaint(
              painter: _BubbleArrowPainter(color: _fill, pointsDown: above),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centres the bubble body over the badge, keeps it inside the screen, and
/// rests it on (or hangs it from) the arrow.
class _BubbleBodyLayout extends SingleChildLayoutDelegate {
  const _BubbleBodyLayout({
    required this.anchorX,
    required this.edge,
    required this.above,
    required this.edgeInset,
    required this.maxWidth,
  });

  final double anchorX;
  final double edge;
  final bool above;
  final double edgeInset;
  final double maxWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = math.max(0.0, constraints.maxWidth - edgeInset * 2);
    return BoxConstraints(maxWidth: math.min(maxWidth, available));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(
      edgeInset,
      size.width - edgeInset - childSize.width,
    );
    final left = (anchorX - childSize.width / 2).clamp(edgeInset, maxLeft);
    final top = above ? edge - childSize.height : edge;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_BubbleBodyLayout oldDelegate) =>
      oldDelegate.anchorX != anchorX ||
      oldDelegate.edge != edge ||
      oldDelegate.above != above ||
      oldDelegate.edgeInset != edgeInset ||
      oldDelegate.maxWidth != maxWidth;
}

class _BubbleArrowPainter extends CustomPainter {
  const _BubbleArrowPainter({required this.color, required this.pointsDown});

  final Color color;
  final bool pointsDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointsDown
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0))
        : (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointsDown != pointsDown;
}

/// Fades and grows the bubble out of the badge.
class _BubbleEntrance extends StatelessWidget {
  const _BubbleEntrance({required this.origin, required this.child});

  /// The badge edge, relative to the centre of the overlay.
  final Offset origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.duration(context, const Duration(milliseconds: 160)),
      curve: AppMotion.emphasized,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.92 + 0.08 * t,
          origin: origin,
          child: child,
        ),
      ),
    );
  }
}
