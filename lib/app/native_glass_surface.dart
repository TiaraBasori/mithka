import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The tint the native glass host installs, as 32-bit ARGB.
///
/// Telegram iOS's liquid-glass surfaces tint `UIGlassEffect` with plain white
/// at 0.10 in light mode and 0.025 in dark (GlassBackgroundComponent's
/// `TintColor.nativeEffect`). The tint must stay a whisper: a tint derived
/// from the bar's own surface colour is invisible by construction in this
/// app's light palette (`navBar == background == 0xFFFFFF`), and pushing that
/// alpha high enough to see turns the tint into a fill that hides the
/// material's refraction — the bar reads as a flat translucent slab, which is
/// exactly the "no glass at all" report. White at Telegram's alpha leaves the
/// material visible while giving it the faint brightening the system glass
/// expects; the capsule's visible edge comes from the Flutter-drawn hairline
/// contour and shadow, not from the tint.
int nativeGlassTint(bool dark) =>
    const Color(0xFFFFFFFF).withValues(alpha: dark ? 0.025 : 0.10).toARGB32();

/// A native Liquid Glass surface behind app-owned tab content: the UIKit view
/// draws only the glass (public `UIGlassEffect` on iOS 26+, a system material
/// `UIBlurEffect` before), while Flutter draws the tabs, the selection pill,
/// and the badges on top and owns every gesture, so one surface serves the
/// phone bottom bar and the tablet sidebar column alike — there are no system
/// slot metrics to fight.
///
/// The platform view is transparent to the widget tree: the child paints above
/// it and wins hit testing, while the view's own opaque hit region keeps the
/// scrollable underneath from receiving touches through the glass.
///
/// Because `UIGlassEffect` resolves its tint when the material is built, a
/// theme change installs a fresh effect instead of mutating the current one
/// (which is a no-op assignment).
class NativeGlassSurface extends StatefulWidget {
  const NativeGlassSurface({super.key, required this.child});

  /// The app-owned tab row drawn above the glass.
  final Widget child;

  @override
  State<NativeGlassSurface> createState() => _NativeGlassSurfaceState();
}

class _NativeGlassSurfaceState extends State<NativeGlassSurface> {
  MethodChannel? _channel;

  Map<String, Object> _configuration() {
    final dark = context.colors.background.computeLuminance() < 0.5;
    return {
      'tint': nativeGlassTint(dark),
      'dark': dark,
      'radius': AppRadius.pill,
      'rtl': Directionality.of(context) == TextDirection.rtl,
    };
  }

  @override
  void didUpdateWidget(NativeGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  void _update() {
    final channel = _channel;
    if (channel != null) {
      unawaited(channel.invokeMethod<void>('update', _configuration()));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey('native-glass-surface'),
    textDirection: Directionality.of(context),
    children: [
      Positioned.fill(
        child: UiKitView(
          viewType: 'mithka/native_glass',
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: _configuration(),
          onPlatformViewCreated: (id) {
            final channel = MethodChannel('mithka/native_glass/$id');
            _channel = channel;
            _update();
          },
        ),
      ),
      widget.child,
    ],
  );
}
