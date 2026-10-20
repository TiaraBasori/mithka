import 'dart:async';
import 'dart:io';

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A hold on the playback surface plays faster while it lasts and hands the
/// previous rate back on release; a rightward swipe from the left edge leaves
/// the player.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Releasing a surface press leaves the package's double-tap tracker counting
  // down; the harness has to let that 40ms window expire before it ends.
  Future<void> settleGestureTimers(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }

  group('hold to speed up', () {
    test('the held rate doubles the current one up to the ceiling', () {
      expect(videoHeldSpeedRate(1), 2);
      expect(videoHeldSpeedRate(0.5), 1);
      expect(videoHeldSpeedRate(1.5), 3);
      expect(videoHeldSpeedRate(2), 4);
      // A rate above the ceiling holds at the ceiling instead of racing.
      expect(videoHeldSpeedRate(3), 4);
      // A report that never settled reads as normal speed.
      expect(videoHeldSpeedRate(double.nan), 2);
      expect(videoHeldSpeedRate(0), 2);
    });

    test('the badge formats the rate without trailing zeros', () {
      expect(formatVideoPlayerSpeed(2), '2x');
      expect(formatVideoPlayerSpeed(1.5), '1.5x');
      expect(formatVideoPlayerSpeed(1.25), '1.25x');
      expect(formatVideoPlayerSpeed(double.nan), '1x');
    });

    testWidgets('a hold raises the rate and release restores it', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 910, localPath: sourcePath),
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 910),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        final pausesBefore = platform.pauseCalls;

        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('video-held-speed-indicator')),
          findsOneWidget,
        );
        expect(find.text('2x'), findsOneWidget);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 2.0);
        // A hold is an acceleration, not a pause.
        expect(platform.pauseCalls, pausesBefore);

        await hold.up();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('video-held-speed-indicator')),
          findsNothing,
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 1.0);
        // The hold never moved the position.
        expect(platform.seekPositions, isEmpty);

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a hold on a quickened video holds the double and restores', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 911, localPath: sourcePath),
              initialSpeed: 1.5,
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 911),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(find.text('3x'), findsOneWidget);
        expect(platform.playbackSpeeds.last, 3.0);

        await hold.up();
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 1.5);

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  /// Deferred native completions: the reviewer's boundary. A held-rate request
  /// that completes after its press is over must not write anything, and the
  /// final native rate must be the base rate the player displays.
  group('pending speed completions', () {
    Future<_FakeVideoPlatform> pumpPlayer(
      WidgetTester tester, {
      int fileId = 920,
      double initialSpeed = 1,
      VoidCallback? onClose,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: fileId, localPath: sourcePath),
            initialSpeed: initialSpeed,
            onClose: onClose ?? () {},
            streamQuery: _completedVideoQuery(sourcePath, fileId: fileId),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);
      // The package's long-press tracker arms on the next real event loop turn.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      return platform;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    }

    testWidgets('a held rate that completes after release writes nothing', (
      tester,
    ) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester);
      final heldBarrier = Completer<void>();
      final restoreBarrier = Completer<void>();
      platform.playbackSpeedBarriers[2.0] = heldBarrier;
      platform.playbackSpeedBarriers[1.0] = restoreBarrier;
      try {
        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();

        // The rate was issued, the badge is up, and nothing has completed yet.
        expect(platform.playbackSpeeds.last, 2.0);
        expect(find.text('2x'), findsOneWidget);

        // The press ends while its held rate is still on the wire.
        await hold.up();
        await tester.pump();
        expect(find.text('2x'), findsNothing);
        expect(platform.playbackSpeeds.last, 1.0);

        // Release before the held completion lands: nothing may be written.
        heldBarrier.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(debugVideoPlayerBaseSpeed, 1.0);

        // The restore is a second request; it lands on the platform and sets
        // the base rate the player displays.
        restoreBarrier.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(platform.playbackSpeeds.last, 1.0);
        expect(debugVideoPlayerBaseSpeed, 1.0);
        await settle(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        platform.playbackSpeedBarriers.clear();
      }
    });

    testWidgets('a held rate still pending at disposal writes nothing', (
      tester,
    ) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester, fileId: 921);
      final heldBarrier = Completer<void>();
      platform.playbackSpeedBarriers[2.0] = heldBarrier;
      try {
        await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(find.text('2x'), findsOneWidget);

        // Tear the player down with the request pending, then complete it.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
        heldBarrier.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await settle(tester);
      } finally {
        platform.playbackSpeedBarriers.clear();
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        if (!heldBarrier.isCompleted) heldBarrier.complete();
      }
    });
  });

  group('edge swipe leaves the player', () {
    testWidgets('a second finger lifting does not finish the swipe', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 917, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 917),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        // Finger one drives the edge swipe halfway.
        final first = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 4; step++) {
          await first.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
        );

        // A second finger lands and lifts. It does not own the swipe, so the
        // drag keeps its offset and the player stays open.
        final second = await tester.startGesture(const Offset(200, 420));
        await second.up();
        await tester.pump();
        expect(closed, 0);
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
          reason: 'the tracked pointer still owns the swipe',
        );

        // The tracked finger finishes the swipe: the player closes once.
        for (var step = 0; step < 4; step++) {
          await first.moveBy(const Offset(20, 0));
          await tester.pump();
        }
        await first.up();
        await tester.pump();
        expect(closed, 1);

        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a short edge swipe snaps back instead of closing', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 912, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 912),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        final seeksBeforeSwipe = platform.seekPositions.length;

        final drag = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 5; step++) {
          await drag.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
        );
        await drag.up();
        await tester.pump();
        expect(closed, 0);
        expect(find.byKey(const ValueKey('video-dismiss-drag')), findsNothing);
        // An abandoned swipe never commits a seek or a navigation.
        expect(platform.seekPositions, hasLength(seeksBeforeSwipe));

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a deliberate edge swipe closes the player', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 913, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 913),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        final seeksBeforeSwipe = platform.seekPositions.length;

        final drag = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 10; step++) {
          await drag.moveBy(const Offset(14, 0));
          await tester.pump();
        }
        await drag.up();
        await tester.pump();
        expect(closed, 1);
        expect(platform.seekPositions, hasLength(seeksBeforeSwipe));

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // A swipe that starts away from the edge keeps its configured meaning;
    // test/mobile_fullscreen_video_player_widget_test.dart's
    // 'default horizontal swipes navigate previous and next' pins it against
    // the same shell fixtures, so it is not duplicated here.
  });
}

Future<void> _pumpUntilPlayerReady(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (
    var attempt = 0;
    attempt < 40 && find.byType(FVideoPlayer).evaluate().isEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _pumpUntilDisposed(
  WidgetTester tester,
  _FakeVideoPlatform platform, {
  int expectedCalls = 1,
}) async {
  for (
    var attempt = 0;
    attempt < 40 && platform.disposeCalls < expectedCalls;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

TdVideoStreamQuery _completedVideoQuery(String path, {required int fileId}) =>
    (request) async {
      if (request['@type'] != 'getFile') {
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
      }
      final length = await File(path).length();
      return {
        'id': fileId,
        'size': length,
        'expected_size': length,
        'local': {
          'is_downloading_completed': true,
          'downloaded_size': length,
          'path': path,
        },
        'remote': {'is_uploading_completed': true, 'uploaded_size': length},
      };
    };

class _FakeVideoPlatform extends VideoPlayerPlatform {
  static const duration = Duration(minutes: 2);
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 1;
  var pauseCalls = 0;
  var disposeCalls = 0;
  final seekPositions = <Duration>[];
  final playbackSpeeds = <double>[];

  /// When set, every setPlaybackSpeed records its rate and then parks until
  /// the entry is completed, reproducing a native completion that lands after
  /// the press that issued it is already over.
  final playbackSpeedBarriers = <double, Completer<void>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    _events[playerId] = StreamController<VideoEvent>.broadcast();
    _positions[playerId] = Duration.zero;
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // The map owns this controller and dispose() closes it.
    // ignore: close_sinks
    final controller = _events[playerId]!;
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: duration,
            size: const Size(1920, 1080),
          ),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposeCalls++;
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
    seekPositions.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    playbackSpeeds.add(speed);
    final barrier = playbackSpeedBarriers[speed];
    if (barrier != null) await barrier.future;
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('fake-video-surface'));
}
