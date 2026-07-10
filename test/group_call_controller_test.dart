import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/call/group_call_controller.dart';

void main() {
  test('parses Telegram group-call participant video sources', () {
    final participant = GroupCallParticipant.fromTd({
      '@type': 'groupCallParticipant',
      'participant_id': {'@type': 'messageSenderUser', 'user_id': 42},
      'audio_source_id': 1234,
      'order': '9000',
      'is_current_user': false,
      'is_speaking': true,
      'is_muted_for_all_users': false,
      'is_muted_for_current_user': false,
      'video_info': {
        '@type': 'groupCallParticipantVideoInfo',
        'endpoint_id': 'camera-42',
        'is_paused': false,
        'source_groups': [
          {
            '@type': 'groupCallVideoSourceGroup',
            'semantics': 'SIM',
            'source_ids': [101, 102, 103],
          },
          {
            '@type': 'groupCallVideoSourceGroup',
            'semantics': 'FID',
            'source_ids': [101, 104],
          },
        ],
      },
    });

    expect(participant, isNotNull);
    expect(participant!.key, 'u:42');
    expect(participant.audioSourceId, 1234);
    expect(participant.hasVideo, isTrue);
    expect(participant.videoEndpointId, 'camera-42');
    expect(participant.videoSourceGroups, hasLength(2));
    expect(participant.videoSourceGroups.first.semantics, 'SIM');
    expect(participant.videoSourceGroups.first.sourceIds, [101, 102, 103]);
  });

  test('empty Telegram order removes a voice-only participant', () {
    final participant = GroupCallParticipant.fromTd({
      '@type': 'groupCallParticipant',
      'participant_id': {'@type': 'messageSenderChat', 'chat_id': -100123},
      'audio_source_id': 99,
      'order': '',
      'is_current_user': false,
      'is_speaking': false,
      'is_muted_for_all_users': true,
    });

    expect(participant, isNotNull);
    expect(participant!.key, 'c:-100123');
    expect(participant.order, isEmpty);
    expect(participant.hasVideo, isFalse);
    expect(participant.isMuted, isTrue);
  });
}
