import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Veil strength for the native glass in each palette.
///
/// The veil is the tint component of the material, so its alpha has to carry
/// real coverage: the light palette's bar surface is the same white as the
/// rows the glass floats over, which makes a mid-range alpha a veil that
/// changes no pixel, and the dark palette's near-black surface needs a
/// stronger veil to separate the bar from the near-black content underneath.
/// The light value is the weakest veil that still reads over the bar's own
/// surface and content alike; the dark value is heavier because the material
/// is darker and the surrounding content is darker too.
const double _tintVeilLight = 0.56;
const double _tintVeilDark = 0.72;

/// The veil colour handed to the native glass host, as 32-bit ARGB.
///
/// The value only tints: [AppColors.navBar] is the bar's own surface colour,
/// so the alpha (not the RGB) is what makes the material perceivable. It must
/// stay strictly inside (0, 1) — 0 leaves the material untinted, 1 replaces it
/// with a flat fill — and grow with the palette ([dark] tells which), since
/// darker content needs more veil to keep the bar legible.
int nativeGlassTintVeil(AppColors colors, {required bool dark}) {
  return colors.navBar
      .withValues(alpha: dark ? _tintVeilDark : _tintVeilLight)
      .toARGB32();
}

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
    final colors = context.colors;
    final dark = colors.background.computeLuminance() < 0.5;
    return {
      'tint': nativeGlassTintVeil(colors, dark: dark),
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
