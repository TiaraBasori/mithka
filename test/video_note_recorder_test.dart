import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

/// Mirrors how the recorder calls the rule: the ratio the preview box itself
/// uses decides the footprint, and the window is only what that box covers.
VideoNotePreviewFootprint footprintFor({
  required Size previewSize,
  required Size viewport,
  required double aspectRatio,
}) {
  return videoNotePreviewFootprint(
    previewSize: previewSize,
    viewport: viewport,
    aspectRatio: aspectRatio,
  );
}

void main() {
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  test('video-note recording gesture distinguishes lock and cancel', () {
    expect(
      videoNoteRecordGestureForDelta(dx: 0, dy: -71),
      VideoNoteRecordGesture.lock,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -91, dy: -100),
      VideoNoteRecordGesture.cancel,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -40, dy: -30),
      VideoNoteRecordGesture.continueRecording,
    );
  });

  testWidgets('recorder chrome is a light film over the black preview', (
    tester,
  ) async {
    // No camera plugin handler in a widget test, so the preview reports its
    // unavailable state; the control chrome is what the camera route paints
    // over the black surface in every state.
    await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
    await tester.pump();

    // The route still reads as camera chrome: a black surface behind the
    // preview, not a raised gray slab.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
      findsWidgets,
    );

    final recordButton = find.byKey(const ValueKey('videoNoteRecordButton'));
    expect(recordButton, findsOneWidget);
    final recordDecoration =
        tester.widget<Container>(recordButton).decoration! as BoxDecoration;
    expect(recordDecoration.shape, BoxShape.circle);
    expect(recordDecoration.border!.top.color, Colors.white);
    expect(recordDecoration.border!.top.width, 3);

    // The shutter disc keeps the full-strength red record affordance.
    final disc = find.byKey(const ValueKey('videoNoteRecordButtonDisc'));
    expect(disc, findsOneWidget);
    expect(
      (tester.widget<AnimatedContainer>(disc).decoration! as BoxDecoration)
          .color,
      const Color(0xFFE53935),
    );

    // An enabled round control: white at 16% with a 25% white outline.
    final closeButton = _roundButton('Close camera');
    expect(closeButton, findsOneWidget);
    final closeDecoration =
        tester.widget<Container>(closeButton).decoration! as BoxDecoration;
    expect(closeDecoration.color, const Color(0x29FFFFFF));
    expect(closeDecoration.border!.top.color, const Color(0x40FFFFFF));
    expect(recordDecoration.color, isNot(const Color(0x29FFFFFF)));

    // A disabled round control (the camera switch without a second lens)
    // fades to white at 8% instead of keeping a solid dark plate.
    final switchButton = _roundButton('Switch camera');
    expect(switchButton, findsOneWidget);
    final switchDecoration =
        tester.widget<Container>(switchButton).decoration! as BoxDecoration;
    expect(switchDecoration.color, const Color(0x14FFFFFF));
    expect(switchDecoration.border!.top.color, const Color(0x1FFFFFFF));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('landscape sensor in a portrait iPad viewport is cover-cropped', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(834, 1194),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

  test('landscape sensor in a landscape iPad viewport keeps 16:9', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(1194, 834),
      aspectRatio: 16 / 9,
    );

    expect(footprint.size.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

  test('portrait sensor in a portrait viewport stays upright', () {
    final footprint = footprintFor(
      previewSize: const Size(720, 1280),
      viewport: const Size(834, 1194),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

  test('a square sensor fills a square viewport and crops elsewhere', () {
    final exact = footprintFor(
      previewSize: const Size(720, 720),
      viewport: const Size(1024, 1024),
      aspectRatio: 1,
    );
    final portrait = footprintFor(
      previewSize: const Size(720, 720),
      viewport: const Size(834, 1194),
      aspectRatio: 1,
    );
    final landscape = footprintFor(
      previewSize: const Size(720, 720),
      viewport: const Size(1194, 834),
      aspectRatio: 1,
    );

    expect(exact.size.aspectRatio, closeTo(1, 1e-9));
    expect(exact.coverCropped, isFalse);
    expect(portrait.size.aspectRatio, closeTo(1, 1e-9));
    expect(portrait.coverCropped, isTrue);
    expect(landscape.size.aspectRatio, closeTo(1, 1e-9));
    expect(landscape.coverCropped, isTrue);
  });

  test('an unknown preview size falls back to the viewport', () {
    final footprint = footprintFor(
      previewSize: Size.zero,
      viewport: const Size(834, 1194),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size.aspectRatio, closeTo(834 / 1194, 1e-9));
    expect(footprint.coverCropped, isFalse);
  });

  test('large iPad viewports cover-fit in both orientations', () {
    final portrait = footprintFor(
      previewSize: const Size(1920, 1080),
      viewport: const Size(1024, 1366),
      aspectRatio: 9 / 16,
    );
    final landscape = footprintFor(
      previewSize: const Size(1920, 1080),
      viewport: const Size(1366, 1024),
      aspectRatio: 16 / 9,
    );

    expect(portrait.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(portrait.coverCropped, isTrue);
    expect(landscape.size.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(landscape.coverCropped, isTrue);
  });

  test('a viewport that already matches the sensor ratio needs no crop', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(720, 1280),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isFalse);
  });

  test('a phone portrait viewport cover-fills instead of letterboxing', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(390, 844),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

  group('videoNotePreviewAspectRatio', () {
    // A portrait phone's back camera: the package reports aspectRatio 0.5625
    // and @ 720x1280.
    CameraValue value({
      Size? previewSize = const Size(720, 1280),
      DeviceOrientation device = DeviceOrientation.portraitUp,
      DeviceOrientation? locked,
      DeviceOrientation? recording,
      bool isRecording = false,
    }) {
      return CameraValue(
        isInitialized: true,
        isRecordingVideo: isRecording,
        isTakingPicture: false,
        isStreamingImages: false,
        isRecordingPaused: false,
        flashMode: FlashMode.auto,
        exposureMode: ExposureMode.auto,
        focusMode: FocusMode.auto,
        exposurePointSupported: false,
        focusPointSupported: false,
        description: const CameraDescription(
          name: 'back',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        previewSize: previewSize,
        deviceOrientation: device,
        lockedCaptureOrientation: locked,
        recordingOrientation: recording,
      );
    }

    test('derives the box from the camera orientation, not the window', () {
      // Portrait camera in a landscape Stage Manager window: the texture
      // stays portrait, so the box keeps the portrait ratio.
      expect(
        videoNotePreviewAspectRatio(value(), sensorIsPortrait: false),
        closeTo(9 / 16, 1e-9),
      );
      // The device turned landscape: the texture turns with it.
      expect(
        videoNotePreviewAspectRatio(
          value(device: DeviceOrientation.landscapeLeft),
          sensorIsPortrait: false,
        ),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('locked and recording orientations win over the device one', () {
      expect(
        videoNotePreviewAspectRatio(
          value(
            device: DeviceOrientation.landscapeLeft,
            locked: DeviceOrientation.portraitUp,
          ),
          sensorIsPortrait: false,
        ),
        closeTo(9 / 16, 1e-9),
      );
      expect(
        videoNotePreviewAspectRatio(
          value(
            locked: DeviceOrientation.portraitUp,
            recording: DeviceOrientation.landscapeRight,
            isRecording: true,
          ),
          sensorIsPortrait: false,
        ),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('a landscape sensor mirrors the package ratio arithmetic', () {
      // A 1280x720 sensor reports aspectRatio 1.7778 (landscape shape). The
      // package's portrait branch is 1 / aspectRatio, which is the portrait
      // shape of that same sensor: 9:16.
      final landscapeValue = value(previewSize: const Size(1280, 720));
      expect(
        videoNotePreviewAspectRatio(landscapeValue, sensorIsPortrait: true),
        closeTo(9 / 16, 1e-9),
      );
      // In a landscape device the package returns aspectRatio itself.
      expect(
        videoNotePreviewAspectRatio(
          landscapeValue.copyWith(
            deviceOrientation: DeviceOrientation.landscapeLeft,
          ),
          sensorIsPortrait: true,
        ),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('a camera without a preview size yet reads as square, not a throw', () {
      // The package's own `aspectRatio` getter force-unwraps the preview size.
      expect(
        videoNotePreviewAspectRatio(
          value(previewSize: null),
          sensorIsPortrait: false,
        ),
        closeTo(1, 1e-9),
      );
    });

    test('a portrait camera in a landscape window keeps its full frame', () {
      final ratio = videoNotePreviewAspectRatio(
        value(),
        sensorIsPortrait: false,
      );
      final footprint = footprintFor(
        previewSize: const Size(720, 1280),
        viewport: const Size(1194, 834),
        aspectRatio: ratio,
      );

      // The box is portrait, so no single axis is scaled by the window's
      // landscape ratio: the frame keeps 9:16 and is cover-cropped instead of
      // stretched.
      expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
      expect(footprint.coverCropped, isTrue);
    });
  });
}

Finder _roundButton(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.key == ValueKey('videoNoteRecorderRoundButton-$label'),
);
