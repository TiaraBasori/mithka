import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/native_tab_bar.dart';
import 'package:mithka/components/app_icons.dart';

import 'helpers/native_tab_bar_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final family = entry['family'] as String;
      if (!family.startsWith('packages/heroicons_flutter/')) continue;
      final loader = FontLoader(family);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  // The variant restores the override before the binding checks foundation
  // invariants; package:test tearDown runs too late for that check.
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('owned outline/filled PNGs keep DPR and use a shared cache', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final first = NativeTabIconRasterizer.png(
        HeroAppIcons.hashtag.data,
        3,
        TextDirection.ltr,
      );
      final repeated = NativeTabIconRasterizer.png(
        HeroAppIcons.hashtag.data,
        3,
        TextDirection.ltr,
      );
      expect(identical(first, repeated), isTrue);
      final normal = await first;
      final filled = await NativeTabIconRasterizer.png(
        HeroAppIcons.solidHashtag.data,
        3,
        TextDirection.ltr,
      );
      expect(listEquals(normal, filled), isFalse);
      final codec = await ui.instantiateImageCodec(normal);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 75);
      expect(frame.image.height, 75);
      frame.image.dispose();
      codec.dispose();
      final rtl = NativeTabIconRasterizer.png(
        HeroAppIcons.hashtag.data,
        3,
        TextDirection.rtl,
      );
      expect(identical(first, rtl), isFalse);
      await rtl;
    });
  }, variant: iOS);

  testWidgets(
    'native contract owns controls and forwards current/other tab taps',
    (tester) async {
      final mock = NativeTabBarMock(tester.binding.defaultBinaryMessenger)
        ..install();
      addTearDown(mock.dispose);
      final selections = <int>[];
      await _pump(tester, onSelect: selections.add, unread: 123456);
      await _pumpConfiguration(tester);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.byType(AppIcon), findsNothing);
      expect(find.text('Messages'), findsNothing);
      expect(
        find.byKey(const ValueKey('liquid-glass-selection')),
        findsNothing,
      );
      final config = mock.latest;
      final items = config['items'] as List;
      expect(items.map((item) => item['id']), [0, 2]);
      expect(items.first['label'], 'Messages');
      expect(items.first['unread'], 123456);
      expect(items.first['image'], isA<Uint8List>());
      expect(items.first['selectedImage'], isA<Uint8List>());
      expect(items.first['imageScale'], 2);
      expect(config.containsKey('selectionInset'), isFalse);
      expect(config.containsKey('height'), isFalse);
      await mock.send('select', {'id': 0});
      await mock.send('select', {'id': 0});
      await mock.send('select', {'id': 2});
      await mock.send('select', {'id': 1}); // disabled ID
      expect(selections, [0, 0, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: iOS,
  );

  testWidgets(
    'native metrics reflow naturally and compact/split insets differ',
    (tester) async {
      final mock = NativeTabBarMock(tester.binding.defaultBinaryMessenger)
        ..install();
      addTearDown(mock.dispose);
      await _pump(tester, bottom: 34);
      await _pumpConfiguration(tester);
      expect(mock.latest['bottomInset'], 34);
      await mock.send('metrics', {
        'height': 91.25,
      }); // contract value, NOT measured UIKit
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('native-tab-bar'))).height,
        91.25,
      );
      await mock.send('metrics', {'height': double.nan});
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('native-tab-bar'))).height,
        91.25,
      );
      await _pump(
        tester,
        bottom: 34,
        reserve: false,
        dark: true,
        direction: TextDirection.rtl,
      );
      await _pumpConfiguration(tester);
      expect(mock.latest['bottomInset'], 0);
      expect(mock.latest['dark'], isTrue);
      expect(mock.latest['rtl'], isTrue);
      expect(mock.created, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: iOS,
  );

  testWidgets(
    'hidden badge read action is explicit and stale account/route tokens fail closed',
    (tester) async {
      final mock = NativeTabBarMock(tester.binding.defaultBinaryMessenger)
        ..install();
      addTearDown(mock.dispose);
      var reads = 0;
      final selections = <int>[];
      await _pump(tester, onRead: () => reads++, onSelect: selections.add);
      await _pumpConfiguration(tester);
      final oldEpoch = mock.latest['actionEpoch'];
      expect((mock.latest['items'] as List).first['canMarkAllRead'], isTrue);
      expect((mock.latest['items'] as List).last['canMarkAllRead'], isFalse);
      expect(mock.latest['markAllReadLabel'], 'Mark all as read');
      expect(reads, 0); // configuration/open/cancel is not a read
      await mock.send('markAllRead', {'id': 2, 'actionEpoch': oldEpoch});
      expect(reads, 0); // no Contacts callback
      await _pump(
        tester,
        scope: 'replacement-account:other-route',
        onRead: () => reads++,
      );
      await _pumpConfiguration(tester);
      await mock.send('markAllRead', {'id': 0, 'actionEpoch': oldEpoch});
      expect(reads, 0);
      await mock.send('markAllRead', {
        'id': 0,
        'actionEpoch': mock.latest['actionEpoch'],
      });
      expect(reads, 1);
      expect(selections, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: iOS,
  );

  testWidgets('pre-26 availability keeps existing fallback only', (
    tester,
  ) async {
    final mock = NativeTabBarMock(
      tester.binding.defaultBinaryMessenger,
      supported: false,
    )..install();
    addTearDown(mock.dispose);
    await _pump(tester);
    await tester.pump();
    expect(find.text('legacy fallback'), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
    expect(mock.created, isEmpty);
  }, variant: iOS);

  testWidgets('disposal is safe with cached RTL artwork', (tester) async {
    // This checks a mounted platform view's disposal, not a deterministically
    // pending engine rasterization. The rasterizer has no completion test hook.
    final mock = NativeTabBarMock(tester.binding.defaultBinaryMessenger)
      ..install();
    addTearDown(mock.dispose);
    await _pump(tester, direction: TextDirection.rtl);
    await _pumpConfiguration(tester);
    expect(find.byType(UiKitView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpConfiguration(tester);
    expect(tester.takeException(), isNull);
  }, variant: iOS);
}

Future<void> _pump(
  WidgetTester tester, {
  int unread = 0,
  double bottom = 0,
  bool reserve = true,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
  String scope = 'account:route',
  ValueChanged<int>? onSelect,
  VoidCallback? onRead,
}) async {
  expect(defaultTargetPlatform, TargetPlatform.iOS);
  // Create AND complete each exact cache key in runAsync before mounting (or
  // updating RTL). Awaiting a fake-zone engine future from runAsync deadlocks.
  await _prewarmIcons(tester, direction: direction);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        devicePixelRatio: 2,
        viewPadding: EdgeInsets.only(bottom: bottom),
      ),
      child: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: NativeTabBar(
            items: [
              NativeTabBarItem(
                id: 0,
                label: 'Messages',
                icon: HeroAppIcons.message,
                selectedIcon: HeroAppIcons.solidMessage,
                unread: unread,
                onMarkAllRead: onRead ?? () {},
              ),
              const NativeTabBarItem(
                id: 2,
                label: 'Contacts',
                icon: HeroAppIcons.users,
                selectedIcon: HeroAppIcons.solidUsers,
              ),
            ],
            selectedId: 0,
            onSelect: onSelect ?? (_) {},
            reserveBottomInset: reserve,
            dark: dark,
            tint: const Color(0xFF007AFF),
            fallback: const Text('legacy fallback'),
            markAllReadLabel: 'Mark all as read',
            actionScope: scope,
          ),
        ),
      ),
    ),
  );
}

Future<void> _prewarmIcons(
  WidgetTester tester, {
  required TextDirection direction,
}) async {
  await tester.runAsync(() async {
    await Future.wait([
      for (final icon in [
        HeroAppIcons.message,
        HeroAppIcons.solidMessage,
        HeroAppIcons.users,
        HeroAppIcons.solidUsers,
        HeroAppIcons.circleCheck,
      ])
        NativeTabIconRasterizer.png(icon.data, 2, direction),
    ]);
  });
}

Future<void> _pumpConfiguration(WidgetTester tester) async {
  // PNGs are already complete, but their cached Futures belong to runAsync's
  // real zone. Their listeners still need real microtask turns between fake
  // pumps: item artwork, then the read-action artwork, then the view handshake.
  for (var phase = 0; phase < 3; phase++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}
