import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/services/audio_grouping_service.dart';

void main() {
  final now = DateTime(2026, 6, 2, 10, 0);

  MediaFile buildAudio(String id, String filePath, {int durationMs = 5000}) {
    return MediaFile(
      id: id,
      projectId: 'project-1',
      filePath: filePath,
      type: MediaType.audio,
      durationMs: durationMs,
      createdAt: now,
    );
  }

  test('ZOOM LR and Tr track are grouped and LR becomes import primary', () {
    final files = AudioGroupingService.applyImportGrouping([
      buildAudio('audio-1', r'G:\audio\ZOOM0147_LR.mp3'),
      buildAudio('audio-2', r'G:\audio\ZOOM0147_Tr1.mp3'),
    ]);

    expect(files[0].audioGroupLabel, 'ZOOM0147');
    expect(files[1].audioGroupLabel, 'ZOOM0147');
    expect(files[0].audioTrackKind, AudioTrackKind.lr);
    expect(files[1].audioTrackKind, AudioTrackKind.track);
    expect(files[0].audioIsPrimary, isTrue);
    expect(files[1].audioIsPrimary, isFalse);
  });

  test(
    'representative track falls back to subtitle richest track when LR has no subtitles',
    () {
      final files = AudioGroupingService.applyImportGrouping([
        buildAudio('audio-1', r'G:\audio\ZOOM0147_LR.mp3', durationMs: 5000),
        buildAudio('audio-2', r'G:\audio\ZOOM0147_Tr1.mp3', durationMs: 4800),
      ]);

      final representative = AudioGroupingService.selectRepresentativeTrack(
        files,
        subtitleCountByMediaId: const {'audio-1': 0, 'audio-2': 16},
      );

      expect(representative.id, 'audio-2');
    },
  );

  test('non ZOOM suffix file stays as single track group', () {
    final files = AudioGroupingService.applyImportGrouping([
      buildAudio('audio-1', r'G:\audio\采访单轨.wav'),
    ]);

    expect(files.single.audioTrackKind, AudioTrackKind.single);
    expect(files.single.audioGroupLabel, '采访单轨');
    expect(files.single.audioIsPrimary, isTrue);
  });
}
