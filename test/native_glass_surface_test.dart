//
//  native_glass_surface_test.dart
//
//  The native glass surface hosts the real Liquid Glass as a background only:
//  the app-owned tab row stays in Flutter, above the platform view, and keeps
//  every gesture. The channel contract mirrors the Swift side
//  (ios/Runner/NativeGlassSurface.swift): creation params configure the glass,
//  theme changes re-send them as 'update', and no item data ever crosses.
//
//  The veil the params carry is what makes the material perceivable at all:
//  the bar's own surface is the same white as the rows behind the light bar
//  and near-black in the dark palette, so the tests pin an alpha that stays
//  strictly visible in both palettes and a native host that applies it on both
//  of its paths (glass tint on iOS 26+, a veil view over the system material
//  before it).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/native_glass_surface.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  /// The veil as the platform channel carries it: 32-bit ARGB. Values with the
  /// sign bit set round-trip through the codec as their signed form, so both
  /// sides of a comparison normalize through this.
  int veilValue(int argb) => argb.toSigned(32);

  test('the veil stays visible in both palettes and grows with them', () {
    double alphaOf(int argb) => ((argb >> 24) & 255) / 255;
    int rgbOf(int argb) => argb & 0x00FFFFFF;

    final light = nativeGlassTintVeil(AppColors.light, dark: false);
    final dark = nativeGlassTintVeil(AppColors.dark, dark: true);

    for (final veil in [light, dark]) {
      // Strictly inside (0, 1): 0 leaves the material untinted, 1 would
      // replace it with a flat fill.
      expect(alphaOf(veil), greaterThan(0));
      expect(alphaOf(veil), lessThan(1));
      // Real coverage, not a film: the light bar's own surface is the same
      // white as the content behind it, so a mid-range alpha changes no pixel.
      expect(alphaOf(veil), greaterThanOrEqualTo(0.5));
    }
    // Monotone with the theme: the dark veil carries more coverage.
    expect(alphaOf(light), lessThan(alphaOf(dark)));

    // Only the alpha changes; the veil keeps the palette's bar colour so the
    // material still reads as the app's own bar surface.
    expect(rgbOf(light), AppColors.light.navBar.toARGB32() & 0x00FFFFFF);
    expect(rgbOf(dark), AppColors.dark.navBar.toARGB32() & 0x00FFFFFF);

    // An unknown palette cannot produce a weaker veil: a bar surface that is
    // already dark gets the dark treatment.
    expect(
      alphaOf(nativeGlassTintVeil(AppColors.light, dark: true)),
      alphaOf(dark),
    );
  });

  test('the native host applies the veil on both of its glass paths', () {
    final source = File(
      'ios/Runner/NativeGlassSurface.swift',
    ).readAsStringSync();
    // iOS 26+: the veil is the glass effect's own tint.
    expect(source, contains('glass.tintColor = tint'));
    // The tint is resolved when the material is built, so the effect has to be
    // re-installed for a theme change to repaint.
    expect(source, contains('effectView.effect = glass'));
    // Legacy: a UIBlurEffect takes no tint, so the same veil rides above the
    // material inside the effect view's content view.
    expect(source, contains('veilView.backgroundColor = tint'));
    expect(source, contains('effectView.contentView.addSubview(veilView)'));
    // Public APIs only: no runtime class lookups or method swizzling.
    expect(source, isNot(contains('NSClassFromString')));
    expect(source, isNot(contains('method_setImplementation')));
  });

  testWidgets('glass surface stays behind the app row and follows the theme', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    final createdParams = <Map<Object?, Object?>>[];
    final updates = <MethodCall>[];
    var id = -1;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map;
        id = arguments['id'] as int;
        createdParams.add(
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(arguments['params'] as Uint8List),
              )
              as Map<Object?, Object?>,
        );
        messenger.setMockMethodCallHandler(
          MethodChannel('mithka/native_glass/$id'),
          (call) async {
            updates.add(call);
            return null;
          },
        );
      }
      return null;
    });
    try {
      const tabKey = ValueKey('bottom-tab-0');
      var taps = 0;
      final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
      addTearDown(themeMode.dispose);

      Widget appRow(AppColors colors) => SizedBox(
        height: 62,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                key: tabKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: ColoredBox(
                  color: colors.linkBlue.withValues(alpha: 0.08),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      );

      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, _) => MaterialApp(
            themeMode: mode,
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: [AppColors.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              extensions: [AppColors.dark],
            ),
            home: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomCenter,
                child: NativeGlassSurface(child: appRow(context.colors)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceContext = tester.element(find.byType(NativeGlassSurface));
      final colors = surfaceContext.colors;
      expect(id, greaterThanOrEqualTo(0));
      expect(createdParams, hasLength(1));
      final initial = createdParams.single;
      expect(initial['dark'], isFalse);
      expect(initial['radius'], AppRadius.pill);
      expect(initial['rtl'], isFalse);
      expect(
        (initial['tint'] as int).toSigned(32),
        veilValue(nativeGlassTintVeil(colors, dark: false)),
      );

      // The glass never receives item data: no labels, no icons, no selection.
      for (final params in createdParams) {
        expect(params.containsKey('items'), isFalse);
        expect(params.containsKey('selection'), isFalse);
      }

      // The app row paints above the platform view and keeps its taps.
      final surface = find.byKey(const ValueKey('native-glass-surface'));
      expect(surface, findsOneWidget);
      expect(
        tester.getRect(find.byType(UiKitView)).bottom,
        tester.getRect(surface).bottom,
      );
      await tester.tap(find.byKey(tabKey), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1);

      // An explicitly light app theme while the OS reports dark must keep the
      // surface light: `dark` derives from the effective app palette only.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(
        () => tester.platformDispatcher.clearPlatformBrightnessTestValue(),
      );
      themeMode.value = ThemeMode.light;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('native-glass-surface')),
        findsOneWidget,
      );
      expect(createdParams, hasLength(1));
      final lightUpdate =
          updates.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(lightUpdate['dark'], isFalse);
      expect(
        (lightUpdate['tint'] as int).toSigned(32),
        veilValue(nativeGlassTintVeil(colors, dark: false)),
      );

      // Flipping the live theme re-sends the configuration through the
      // existing platform view's channel via didChangeDependencies without
      // recreating the UiKitView.
      themeMode.value = ThemeMode.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('native-glass-surface')),
        findsOneWidget,
      );
      final darkColors = tester.element(find.byType(NativeGlassSurface)).colors;
      expect(createdParams, hasLength(1));
      expect(updates.map((call) => call.method), contains('update'));
      final update =
          updates.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(update['dark'], isTrue);
      expect(
        (update['tint'] as int).toSigned(32),
        veilValue(nativeGlassTintVeil(darkColors, dark: true)),
      );

      // The opposite disagreement: an explicitly dark app theme while the OS
      // reports light must keep the surface dark.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      themeMode.value = ThemeMode.light;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      themeMode.value = ThemeMode.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(createdParams, hasLength(1));
      final darkUpdate =
          updates.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(darkUpdate['dark'], isTrue);
      expect(
        (darkUpdate['tint'] as int).toSigned(32),
        veilValue(nativeGlassTintVeil(darkColors, dark: true)),
      );

      // The light palette never borrows the light veil from the OS: switching
      // back re-sends the light veil.
      themeMode.value = ThemeMode.light;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final backToLight =
          updates.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(backToLight['dark'], isFalse);
      expect(
        (backToLight['tint'] as int).toSigned(32),
        veilValue(
          nativeGlassTintVeil(
            tester.element(find.byType(NativeGlassSurface)).colors,
            dark: false,
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      if (id >= 0) {
        messenger.setMockMethodCallHandler(
          MethodChannel('mithka/native_glass/$id'),
          null,
        );
      }
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
