import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video controls use the owned slider renderer', () {
    final appSource = File(
      'lib/chat/video_player_view.dart',
    ).readAsStringSync();
    final storySource = File(
      'lib/moments/story_viewer_view.dart',
    ).readAsStringSync();
    final videoNoteSource = File(
      'lib/chat/video_note_preview_view.dart',
    ).readAsStringSync();
    final source = File(
      'packages/mithka_video_player/lib/src/video_slider.dart',
    ).readAsStringSync();

    expect(appSource, contains('MithkaVideoSlider('));
    expect(storySource, contains("ValueKey('storyVolumeSlider')"));
    expect(storySource, contains('MithkaVideoSlider('));
    expect(videoNoteSource, contains("ValueKey('videoNoteVolumeSlider')"));
    expect(videoNoteSource, contains('MithkaVideoSlider('));
    expect(<String>[
      storySource,
      videoNoteSource,
    ], everyElement(isNot(matches(RegExp(r'\b(?:Icons|CupertinoIcons)\.')))));
    expect(source, contains('class MithkaVideoSlider'));
    expect(source, contains('CustomPaint('));
    expect(source, isNot(contains('SliderTheme(')));
    expect(source, isNot(contains('child: Slider(')));
  });
}
