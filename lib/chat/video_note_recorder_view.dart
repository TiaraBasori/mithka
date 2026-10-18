import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../media/media_metadata.dart';
import '../theme/app_theme.dart';

class VideoNoteCaptureResult {
  const VideoNoteCaptureResult({required this.path, required this.duration});

  final String path;
  final int duration;
}

enum VideoNoteRecordGesture { continueRecording, lock, cancel }

VideoNoteRecordGesture videoNoteRecordGestureForDelta({
  required double dx,
  required double dy,
}) {
  if (dx < -90) return VideoNoteRecordGesture.cancel;
  if (dy < -70) return VideoNoteRecordGesture.lock;
  return VideoNoteRecordGesture.continueRecording;
}

/// The box a live video-message preview is laid out in before it is scaled to
/// cover the recorder's available area.
@immutable
class VideoNotePreviewFootprint {
  const VideoNotePreviewFootprint({
    required this.size,
    required this.coverCropped,
  });

  /// Sensor size with its axes turned to the current screen axis. The long
  /// side follows the viewport's long side, so the box always shares the
  /// viewport's orientation.
  final Size size;

  /// Whether [size] and the viewport have different aspect ratios, so a
  /// cover fit crops instead of filling exactly.
  final bool coverCropped;

  @override
  String toString() =>
      'VideoNotePreviewFootprint(size: $size, coverCropped: $coverCropped)';
}

/// Ratios closer than this count as equal; sensor sizes are integers, so a
/// sub-thousandth difference is float noise rather than a real mismatch.
const double _previewRatioTolerance = 0.001;

bool _hasPreviewArea(Size size) =>
    size.isFinite && size.width > 0 && size.height > 0;

/// Decides how the live video-message preview fills [viewport].
///
/// The camera package sizes its preview from the sensor ratio turned to the
/// camera's applicable orientation, which can disagree with the window's axis
/// on iPad Stage Manager, in split view, or whenever the sensor reports an
/// orientation the screen does not share. The footprint therefore follows
/// [aspectRatio] - the ratio the preview box itself uses, from
/// [videoNotePreviewAspectRatio] - and only the cover fit below looks at
/// [viewport]: contributing a window-derived orientation here is what forced a
/// portrait texture into a landscape-sized box whenever the two disagreed.
///
/// The footprint is then cover-fitted, never letterboxed, because a recorder
/// must fill its window with live pixels. The footprint's `coverCropped` flag
/// reports whether that fit crops the sensor frame.
///
/// A zero or non-finite [previewSize] (camera still warming up) falls back to
/// [viewport] itself, and an unmeasurable [viewport] falls back to the sensor
/// box, so the returned size is always finite and non-negative.
VideoNotePreviewFootprint videoNotePreviewFootprint({
  required Size previewSize,
  required Size viewport,
  required double aspectRatio,
}) {
  final hasViewport = _hasPreviewArea(viewport);
  if (!_hasPreviewArea(previewSize)) {
    return VideoNotePreviewFootprint(
      size: hasViewport ? viewport : Size.zero,
      coverCropped: false,
    );
  }
  final longSide = previewSize.longestSide;
  final shortSide = previewSize.shortestSide;
  // The frames the package's own box can occupy at [aspectRatio]: landscape
  // (long side across) when the ratio is at least 1, portrait otherwise.
  final oriented = aspectRatio >= 1
      ? Size(longSide, shortSide)
      : Size(shortSide, longSide);
  if (!hasViewport) {
    return VideoNotePreviewFootprint(size: oriented, coverCropped: false);
  }
  final ratioDelta = (oriented.aspectRatio - viewport.aspectRatio).abs();
  return VideoNotePreviewFootprint(
    size: oriented,
    coverCropped: ratioDelta > _previewRatioTolerance,
  );
}

/// The aspect ratio [CameraPreview] puts on its own [AspectRatio] box.
///
/// The camera package derives it from the camera's APPLICABLE orientation -
/// the recording orientation while recording, otherwise a paused preview, a
/// locked capture orientation, or the device orientation - never from the
/// window's dimensions. Android additionally rotates its texture inside that
/// box, so the box's ratio is the sensor ratio narrowed when the applicable
/// orientation is a landscape one.
///
/// [sensorIsPortrait] stands in for the preview size while the camera has not
/// reported one yet. Never throws: the package's own ratio getter force-unwraps
/// the preview size.
double videoNotePreviewAspectRatio(
  CameraValue value, {
  required bool sensorIsPortrait,
}) {
  final orientation = value.isRecordingVideo
      ? value.recordingOrientation
      : (value.previewPauseOrientation ??
            value.lockedCaptureOrientation ??
            value.deviceOrientation);
  final landscape =
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
  final preview = value.previewSize;
  final portrait = preview == null
      ? sensorIsPortrait
      : preview.height >= preview.width;
  final sensorRatio = preview == null ? 1.0 : preview.width / preview.height;
  return landscape == portrait ? 1 / sensorRatio : sensorRatio;
}

/// An owned video-message camera with Telegram-style hold, cancel, lock and
/// pause controls. Keeping capture inside the app also lets users switch the
/// active lens before recording instead of being sent to the system camera.
///
/// Camera-route chrome over the black preview (concrete values, no shortcuts):
///  * the round control surfaces are white at 16% (`0x29FFFFFF`) with a 25%
///    white outline (`0x40FFFFFF`) — a translucent light film over the live
///    preview, not an opaque mid-gray pill;
///  * a disabled control drops to white at 8% (`0x14FFFFFF`) with a 12%
///    outline (`0x1FFFFFFF`) and 40% icon opacity;
///  * the shutter disc keeps the full-strength red `0xFFE53935` while it is
///    the record affordance, and turns into the brand-accent square while a
///    locked recording is waiting to be stopped.
class VideoNoteRecorderView extends StatefulWidget {
  const VideoNoteRecorderView({super.key});

  @override
  State<VideoNoteRecorderView> createState() => _VideoNoteRecorderViewState();
}

class _VideoNoteRecorderViewState extends State<VideoNoteRecorderView>
    with WidgetsBindingObserver {
  static const _maximumDuration = Duration(seconds: 60);

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _recording = false;
  bool _paused = false;
  bool _locked = false;
  bool _finishing = false;
  double _pressStartX = 0;
  double _pressStartY = 0;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCameras());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_recording) {
        unawaited(_cancelRecording());
      } else {
        unawaited(_disposeController());
      }
    } else if (state == AppLifecycleState.resumed && !_recording) {
      unawaited(_initializeCamera(_cameraIndex));
    }
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) throw StateError('No camera is available.');
      _cameras = cameras;
      final front = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = front >= 0 ? front : 0;
      await _initializeCamera(_cameraIndex);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _initializeCamera(int index) async {
    if (_cameras.isEmpty || index < 0 || index >= _cameras.length) return;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }
    await _disposeController();
    final controller = CameraController(_cameras[index], ResolutionPreset.high);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.prepareForVideoRecording();
      if (!mounted || !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraIndex = index;
        _initializing = false;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.description ?? error.code;
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) await controller.dispose();
  }

  Future<void> _switchCamera() async {
    if (_finishing || _recording || _cameras.length < 2) return;
    var next = (_cameraIndex + 1) % _cameras.length;
    final currentDirection = _cameras[_cameraIndex].lensDirection;
    for (var offset = 1; offset <= _cameras.length; offset++) {
      final candidate = (_cameraIndex + offset) % _cameras.length;
      if (_cameras[candidate].lensDirection != currentDirection) {
        next = candidate;
        break;
      }
    }
    await _initializeCamera(next);
  }

  Future<void> _startRecording({bool locked = false}) async {
    final controller = _controller;
    if (_recording ||
        _finishing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _paused = false;
        _locked = locked;
        _elapsed = Duration.zero;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || _paused) return;
        setState(() => _elapsed += const Duration(milliseconds: 100));
        if (_elapsed >= _maximumDuration) unawaited(_finishRecording());
      });
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    }
  }

  Future<void> _togglePause() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    try {
      if (_paused) {
        await controller.resumeVideoRecording();
      } else {
        await controller.pauseVideoRecording();
      }
      if (mounted) setState(() => _paused = !_paused);
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    }
  }

  Future<void> _finishRecording() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    _finishing = true;
    _timer?.cancel();
    try {
      final video = await controller.stopVideoRecording();
      final seconds =
          (_elapsed.inMilliseconds < 1000
                  ? 1
                  : (_elapsed.inMilliseconds / 1000).ceil().clamp(1, 60))
              .toInt();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(VideoNoteCaptureResult(path: video.path, duration: seconds));
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.description ?? error.code;
          _recording = false;
          _paused = false;
          _locked = false;
        });
      }
    } finally {
      _finishing = false;
    }
  }

  Future<void> _cancelRecording() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    _finishing = true;
    _timer?.cancel();
    try {
      final video = await controller.stopVideoRecording();
      try {
        final file = File(video.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The temporary camera file is reclaimed by the platform cache.
      }
    } catch (_) {
      // The recording may already have been stopped by the lifecycle.
    } finally {
      _finishing = false;
      if (mounted) {
        setState(() {
          _recording = false;
          _paused = false;
          _locked = false;
          _elapsed = Duration.zero;
        });
      }
    }
  }

  String get _elapsedLabel =>
      formatMediaDuration(_elapsed.inSeconds.clamp(0, 60));

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              _preview(controller)
            else if (_initializing)
              const Center(child: AppActivityIndicator(color: Colors.white))
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error ?? 'Camera unavailable',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              top: 8,
              child: _roundButton(
                icon: HeroAppIcons.xmark,
                label: AppStrings.t(AppStringKeys.videoNoteRecorderCloseCamera),
                onTap: _recording
                    ? () => unawaited(_cancelRecording())
                    : () => Navigator.of(context).pop(),
              ),
            ),
            if (_recording)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Text(
                      _paused ? 'Paused · $_elapsedLabel' : _elapsedLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(left: 18, right: 18, bottom: 22, child: _controls()),
          ],
        ),
      ),
    );
  }

  /// Fills the recorder with the live preview without distorting it.
  ///
  /// [CameraPreview] already wraps its texture in an [AspectRatio] sized from
  /// the camera's applicable orientation (see [videoNotePreviewAspectRatio]),
  /// so a second ratio here applied the ratio twice and letterboxed whenever
  /// the device orientation disagreed with the window. The box is instead
  /// constrained to that same ratio - which therefore never stretches the
  /// texture, whatever the window shape - and scaled to cover the window.
  Widget _preview(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = constraints.biggest;
        final viewport = measured.isFinite && !measured.isEmpty
            ? measured
            : MediaQuery.sizeOf(context);
        final sensor = controller.description.sensorOrientation;
        final ratio = videoNotePreviewAspectRatio(
          controller.value,
          sensorIsPortrait: sensor == 0 || sensor == 180,
        );
        final footprint = videoNotePreviewFootprint(
          previewSize: controller.value.previewSize ?? Size.zero,
          viewport: viewport,
          aspectRatio: ratio,
        );
        if (footprint.size.isEmpty) return const SizedBox.expand();
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: footprint.coverCropped ? Clip.hardEdge : Clip.none,
            child: SizedBox(
              width: footprint.size.width,
              height: footprint.size.height,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _controls() {
    if (_recording && _locked) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: HeroAppIcons.trash,
            label: AppStrings.t(AppStringKeys.videoNoteRecorderCancelRecording),
            onTap: () => unawaited(_cancelRecording()),
          ),
          _roundButton(
            icon: _paused ? HeroAppIcons.play : HeroAppIcons.pause,
            label: _paused ? 'Resume recording' : 'Pause recording',
            onTap: () => unawaited(_togglePause()),
          ),
          _recordButton(
            locked: true,
            onTap: () => unawaited(_finishRecording()),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const SizedBox(width: 48),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_startRecording(locked: true)),
          onLongPressStart: (details) {
            _pressStartX = details.globalPosition.dx;
            _pressStartY = details.globalPosition.dy;
            unawaited(_startRecording());
          },
          onLongPressMoveUpdate: (details) {
            if (!_recording || _locked) return;
            final dx = details.globalPosition.dx - _pressStartX;
            final dy = details.globalPosition.dy - _pressStartY;
            switch (videoNoteRecordGestureForDelta(dx: dx, dy: dy)) {
              case VideoNoteRecordGesture.cancel:
                unawaited(_cancelRecording());
                break;
              case VideoNoteRecordGesture.lock:
                setState(() => _locked = true);
                break;
              case VideoNoteRecordGesture.continueRecording:
                break;
            }
          },
          onLongPressEnd: (_) {
            if (_recording && !_locked) unawaited(_finishRecording());
          },
          child: _recordButton(),
        ),
        _roundButton(
          icon: HeroAppIcons.arrowsRotate,
          label: AppStrings.t(AppStringKeys.videoNoteRecorderSwitchCamera),
          onTap: _cameras.length > 1 ? () => unawaited(_switchCamera()) : null,
        ),
      ],
    );
  }

  Widget _recordButton({bool locked = false, VoidCallback? onTap}) {
    final button = Semantics(
      button: true,
      label: locked
          ? 'Stop video message'
          : 'Hold to record, slide up to lock, left to cancel',
      child: Container(
        key: const ValueKey('videoNoteRecordButton'),
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: AnimatedContainer(
          key: const ValueKey('videoNoteRecordButtonDisc'),
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            // Full-strength red while the disc is the record affordance; the
            // accent square replaces it once the recording is locked and the
            // press becomes "stop".
            color: locked ? AppTheme.brand : const Color(0xFFE53935),
            shape: locked ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: locked
                ? BorderRadius.circular(AppRadius.control)
                : null,
          ),
        ),
      ),
    );
    return onTap == null
        ? button
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: button,
          );
  }

  Widget _roundButton({
    required AppIconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: ValueKey('videoNoteRecorderRoundButton-$label'),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // A uniform light film over the black preview rather than an
            // opaque mid-gray slab; disabled controls fade out instead of
            // keeping a solid plate.
            color: onTap == null
                ? const Color(0x14FFFFFF)
                : const Color(0x29FFFFFF),
            shape: BoxShape.circle,
            border: Border.all(
              color: onTap == null
                  ? const Color(0x1FFFFFFF)
                  : const Color(0x40FFFFFF),
              width: 0.5,
            ),
          ),
          child: AppIcon(
            icon,
            size: 22,
            color: Colors.white.withValues(alpha: onTap == null ? 0.4 : 1),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }
}
