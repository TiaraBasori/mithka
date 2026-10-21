import 'dart:async';
import 'dart:io';

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_queue.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A tap on the playback surface toggles the chrome. Two recognizer details
/// used to turn that tap into a seek instead: the pan wins the arena at
/// [kTouchSlop], and holding in a side band steps the position immediately.
void main() {
  group('a tap is never a seek', () {
    test('a pan below the deliberate-drag distance does not engage', () {
      // Gestures the platform still reports as a tap: no movement, the slop
      // distance itself, and the roll left by lifting a thumb.
      expect(videoPlaybackPanEngages(Offset.zero), isFalse);
      expect(videoPlaybackPanEngages(const Offset(6, 0)), isFalse);
      expect(videoPlaybackPanEngages(const Offset(0, 12)), isFalse);
      expect(videoPlaybackPanEngages(const Offset(kTouchSlop, 0)), isFalse);
      expect(
        videoPlaybackPanEngages(const Offset(0, kTouchSlop * 1.5)),
        isFalse,
      );
      expect(videoPlaybackPanEngages(const Offset(20, -14)), isFalse);
    });

    test('a deliberate drag engages on either axis', () {
      expect(videoPlaybackPanEngages(const Offset(kTouchSlop * 2, 0)), isTrue);
      expect(videoPlaybackPanEngages(const Offset(0, kTouchSlop * 2)), isTrue);
      expect(videoPlaybackPanEngages(const Offset(-80, 4)), isTrue);
    });

    test('the threshold sits above the platform drag slop', () {
      // If these ever collapse into each other, every tap that rolls a little
      // becomes a seek again.
      expect(videoPlaybackPanEngages(const Offset(kTouchSlop + 1, 0)), isFalse);
    });

    test('a hold speeds playback up and leaves the position alone', () {
      // The hold used to step the position on a timer; it now only changes
      // the rate, and the rate is a multiple of the one playback had.
      expect(videoHeldSpeedRate(1), 2);
      expect(videoHeldSpeedRate(2), 4);
    });
  });

  group('the player wires those rules into its gestures', () {
    final source = File('lib/chat/video_player_view.dart').readAsStringSync();

    String bodyOf(String signature) {
      final start = source.indexOf(signature);
      expect(start, isNot(-1), reason: 'missing $signature');
      final end = source.indexOf('\n  }', start);
      expect(end, isNot(-1), reason: 'unterminated $signature');
      return source.substring(start, end);
    }

    test('the pan path classifies movement with the engage rule', () {
      expect(
        bodyOf('void _updatePlaybackGesture('),
        contains('videoPlaybackPanEngages(delta)'),
      );
    });

    test('a pan that never engaged finishes as a tap', () {
      // The surface pan shares its pointer with the package's tap, so it is
      // the one that has to decide the release: a rolled press toggles the
      // chrome, and only a deliberate horizontal drag reaches the gesture
      // finish at all.
      final finish = bodyOf('void _finishSurfacePanGesture(');
      final tapAt = finish.indexOf('videoSurfacePanReplacesTap(');
      final toggleAt = finish.indexOf('toggleControls()');
      final gestureAt = finish.indexOf('_finishPlaybackGesture(');
      expect(tapAt, isNot(-1));
      expect(toggleAt, isNot(-1));
      expect(gestureAt, isNot(-1));
      expect(
        tapAt < toggleAt && toggleAt < gestureAt,
        isTrue,
        reason: 'the displaced tap is finished before any gesture commits',
      );
      expect(finish, contains('_cancelPlaybackGesture()'));
    });

    test('winning the arena no longer shows the chrome by itself', () {
      expect(
        bodyOf('void _startSurfacePanGesture('),
        isNot(contains('showControls()')),
      );
      expect(
        bodyOf('void _startPlaybackGesture('),
        isNot(contains('showControls()')),
      );
    });

    test('the hold is armed through the rate serializer', () {
      // The press only moves the desired rate; the pump is the one writer,
      // so a release or a newer hold cannot overtake a request on the wire.
      expect(bodyOf('void _startHeldSpeed('), contains('videoHeldSpeedRate('));
      expect(
        bodyOf('void _startHeldSpeed('),
        contains('_pumpHeldSpeedWrites()'),
      );
      expect(
        bodyOf('void _stopHeldSpeed('),
        contains('_pumpHeldSpeedWrites()'),
      );
      expect(
        bodyOf('Future<void> _pumpHeldSpeedWrites('),
        contains('await controller.setPlaybackSpeed(rate)'),
      );
    });
  });

  group('the widget path classifies a tap as a tap', () {
    testWidgets(
      'a pan under the engage distance finishes as a tap, never a seek',
      (tester) async {
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
                video: TdFileRef(id: 914, localPath: sourcePath),
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 914),
              ),
            ),
          );
          await _pumpUntilPlayerReady(tester);
          // The package's long-press tracker arms on the next real event loop
          // turn; give the harness one before driving the gesture.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );

          // The reported roll: a single 30px move, far enough to win the pan
          // arena but under the deliberate-drag distance.
          final pan = await tester.startGesture(const Offset(195, 420));
          await tester.pump();
          await pan.moveBy(const Offset(30, 0));
          await tester.pump(const Duration(milliseconds: 16));
          await pan.up();
          await tester.pump(const Duration(milliseconds: 400));

          expect(
            platform.seekPositions,
            isEmpty,
            reason: 'an unengaged pan must not seek',
          );
          // The tap lands: exactly one toggle takes the chrome down. The old
          // path engaged at 12px, showed the chrome and committed a seek.
          expect(_chromeOpacity(tester), 0);
          expect(find.byType(FVideoPlayer), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 6));
        } finally {
          VideoPlayerPlatform.instance = previousPlatform;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    for (final roll in const [20.0, 30.0, 45.0]) {
      testWidgets(
        'a tap that rolls ${roll.toInt()}px keeps the chrome and never seeks',
        (tester) async {
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
                  video: TdFileRef(id: 917, localPath: sourcePath),
                  onClose: () {},
                  streamQuery: _completedVideoQuery(sourcePath, fileId: 917),
                ),
              ),
            );
            await _pumpUntilPlayerReady(tester);
            final surface = tester.getRect(find.byType(FVideoPlayer));

            // A tap that rolls is reported as a pan by the platform. Every
            // roll past the drag slop used to let the pan win the arena, so
            // the package's tap never fired and the press read as an inert
            // gesture instead of a tap that takes the chrome down.
            final tap = await tester.startGesture(surface.center);
            await tester.pump();
            await tap.moveBy(Offset(roll, 0));
            await tester.pump(const Duration(milliseconds: 16));
            await tap.up();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));

            expect(
              platform.seekPositions,
              isEmpty,
              reason: 'a rolled tap must not move playback',
            );
            expect(
              _chromeOpacity(tester),
              0,
              reason: 'a rolled tap must still toggle the chrome',
            );

            // A clean tap brings the chrome back, so the swallowed tap did not
            // leave the counters doubled or the surface inert.
            await tester.tapAt(const Offset(12, 12));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(_chromeOpacity(tester), 1);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 6));
          } finally {
            VideoPlayerPlatform.instance = previousPlatform;
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }

    testWidgets(
      'a horizontal drag past the engage distance stays a queue swipe',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final previousPlatform = VideoPlayerPlatform.instance;
        final platform = _FakeVideoPlatform();
        VideoPlayerPlatform.instance = platform;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final navigation = <int>[];
        try {
          SharedPreferences.setMockInitialValues(const {});
          final sourcePath = File('pubspec.yaml').absolute.path;
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [AppLocalizations.delegate],
              supportedLocales: AppLocalizations.supportedLocales,
              home: VideoPlayerView(
                video: TdFileRef(id: 918, localPath: sourcePath),
                previousVideo: VideoPlaybackItem(video: TdFileRef(id: 917)),
                nextVideo: VideoPlaybackItem(video: TdFileRef(id: 919)),
                onNavigate: navigation.add,
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 918),
              ),
            ),
          );
          await _pumpUntilPlayerReady(tester);
          final surface = tester.getRect(find.byType(FVideoPlayer));

          // 160px is a deliberate drag, not a tap that rolled. The pan owns it
          // and must not also finish it as a tap, which would leave the chrome
          // hidden while the queue moved.
          final swipe = await tester.startGesture(surface.center);
          await tester.pump();
          // A real finger reports a drag over several frames; one jump of
          // 160px only crosses the slop and never delivers an update.
          for (var step = 0; step < 8; step++) {
            await swipe.moveBy(const Offset(-20, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await swipe.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          // A leftward swipe moves to the next video, and the pan must have
          // committed exactly that one navigation.
          expect(navigation, [1]);
          expect(
            platform.seekPositions,
            isEmpty,
            reason: 'a queue swipe must not seek under changeVideo',
          );
          expect(
            _chromeOpacity(tester),
            1,
            reason: 'a deliberate drag keeps the chrome a gesture shows',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 6));
        } finally {
          VideoPlayerPlatform.instance = previousPlatform;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('a tap that outlasts long press never seeks and leaves no '
        'rate behind', (tester) async {
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
              video: TdFileRef(id: 915, localPath: sourcePath),
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 915),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        // A press in the side band that outlasts long press and lifts: the
        // press was a tap, so it must neither seek nor leave a rate behind.
        final press = await tester.startGesture(const Offset(30, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        await press.up();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(seconds: 2));

        expect(
          platform.seekPositions,
          isEmpty,
          reason: 'a tap that outlasted long press must not move playback',
        );
        // Long press recognition alone may flash the hold, but the release
        // has to put the rate it replaced back: a slow tap must not leave
        // playback faster than it found it.
        expect(
          platform.playbackSpeeds.last,
          1.0,
          reason: 'a slow tap must not leave a held rate behind',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a deliberate hold speeds up and restores on release', (
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
              video: TdFileRef(id: 916, localPath: sourcePath),
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 916),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(
          platform.playbackSpeeds.last,
          2.0,
          reason: 'a deliberate hold must still speed playback up',
        );
        await hold.up();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(
          platform.playbackSpeeds.last,
          1.0,
          reason: 'release must restore the rate the press replaced',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final finish in ['cancel', 'dispose']) {
      testWidgets('$finish restores the rate a hold replaced', (tester) async {
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
          final fileId = finish == 'dispose' ? 942 : 941;
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [AppLocalizations.delegate],
              supportedLocales: AppLocalizations.supportedLocales,
              home: VideoPlayerView(
                video: TdFileRef(id: fileId, localPath: sourcePath),
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: fileId),
              ),
            ),
          );
          await _pumpUntilPlayerReady(tester);
          expect(find.byType(FVideoPlayer), findsOneWidget);

          final hold = await tester.startGesture(const Offset(195, 420));
          await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 60),
          );
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          expect(platform.playbackSpeeds.last, 2.0);

          if (finish == 'dispose') {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 6));
            await hold.cancel();
          } else {
            await hold.cancel();
            await tester.pump();
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (finish == 'cancel') {
            expect(
              platform.playbackSpeeds.last,
              1.0,
              reason: 'a cancelled press must leave the base rate behind',
            );
          }
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 6));
        } finally {
          VideoPlayerPlatform.instance = previousPlatform;
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });
}

/// The player is ready once the package's own player widget is mounted.
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
  // The package's gesture trackers arm on the next real event loop turn.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
}

double _chromeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.byKey(const ValueKey('mithka-video-player-chrome')),
    )
    .opacity;

TdVideoStreamQuery _completedVideoQuery(String path, {required int fileId}) =>
    (request) async {
      if (request['@type'] != 'getFile') {
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
      }
      final length = await File(path).length();
      return <String, dynamic>{
        '@type': 'file',
        'id': fileId,
        'size': length,
        'expected_size': length,
        'local': {
          '@type': 'localFile',
          'path': path,
          'download_offset': 0,
          'downloaded_prefix_size': length,
          'downloaded_size': length,
          'is_downloading_active': false,
          'is_downloading_completed': true,
        },
      };
    };

class _FakeVideoPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 1;
  final seekPositions = <Duration>[];
  final playbackSpeeds = <double>[];

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
            duration: const Duration(minutes: 2),
            size: const Size(1920, 1080),
          ),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

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
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}
