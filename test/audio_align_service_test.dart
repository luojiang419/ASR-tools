import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/subtitle_clip.dart';
import 'package:asr_tools/models/sync_result.dart';
import 'package:asr_tools/services/audio_align_service.dart';
import 'package:asr_tools/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio-align-test-');
    await DatabaseService.init(
      overridePath: p.join(tempDir.path, 'audio-align-test.db'),
    );
  });

  tearDown(() async {
    await DatabaseService.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'buildTimeline carries embedded audio visibility from source video',
    () async {
      final now = DateTime(2026, 5, 20, 10);
      final project = AsrProject(
        id: 'project-1',
        name: '测试工程',
        createdAt: now,
        updatedAt: now,
      );
      await DatabaseService.insertProject(project);
      await DatabaseService.insertMediaFiles([
        MediaFile(
          id: 'video-1',
          projectId: project.id,
          filePath: r'G:\video\C0001.mp4',
          type: MediaType.video,
          durationMs: 4000,
          hasEmbeddedAudio: true,
          createdAt: now,
        ),
        MediaFile(
          id: 'audio-1',
          projectId: project.id,
          filePath: r'G:\audio\ZOOM0147_LR.wav',
          type: MediaType.audio,
          durationMs: 5000,
          audioGroupKey: r'g:\audio|zoom0147',
          audioGroupLabel: 'ZOOM0147',
          audioTrackKind: AudioTrackKind.lr,
          audioIsPrimary: true,
          createdAt: now,
        ),
        MediaFile(
          id: 'audio-2',
          projectId: project.id,
          filePath: r'G:\audio\ZOOM0147_Tr1.wav',
          type: MediaType.audio,
          durationMs: 4800,
          audioGroupKey: r'g:\audio|zoom0147',
          audioGroupLabel: 'ZOOM0147',
          audioTrackKind: AudioTrackKind.track,
          audioTrackIndex: 1,
          createdAt: now,
        ),
      ]);
      await DatabaseService.replaceSyncResults(project.id, [
        SyncResult(
          id: 'sync-1',
          projectId: project.id,
          videoFileId: 'video-1',
          audioFileId: 'audio-1',
          videoDurationMs: 4000,
          timelineStartMs: 0,
          timelineEndMs: 4000,
          audioSourceInMs: 300,
          audioSourceOutMs: 4300,
          confidence: 0.9,
          status: SyncStatus.autoAccepted,
          method: SyncMethod.subtitleOnly,
          createdAt: now,
        ),
      ]);

      final timelineList = await AudioAlignService.buildTimeline(project.id);

      expect(timelineList, hasLength(1));
      expect(timelineList.first.videoHasEmbeddedAudio, isTrue);
      expect(timelineList.first.audioFilePath, r'G:\audio\ZOOM0147_LR.wav');
      expect(timelineList.first.externalAudioTracks, hasLength(2));
      expect(
        timelineList.first.externalAudioTracks.first.fileName,
        'ZOOM0147_LR.wav',
      );
      expect(
        timelineList.first.externalAudioTracks.last.fileName,
        'ZOOM0147_Tr1.wav',
      );
    },
  );

  test('buildTimeline annotates multicam video tracks from layout', () async {
    final now = DateTime(2026, 7, 8, 13);
    final project = AsrProject(
      id: 'project-multicam',
      name: '多机位时间线',
      createdAt: now,
      updatedAt: now,
    );
    await DatabaseService.insertProject(project);
    await DatabaseService.insertMediaFiles([
      MediaFile(
        id: 'video-long',
        projectId: project.id,
        filePath: r'G:\video\C0001.mp4',
        type: MediaType.video,
        durationMs: 10000,
        layoutStartMs: 0,
        layoutEndMs: 10000,
        createdAt: now,
      ),
      MediaFile(
        id: 'video-short',
        projectId: project.id,
        filePath: r'G:\video\C0002.mp4',
        type: MediaType.video,
        durationMs: 6000,
        layoutStartMs: 2000,
        layoutEndMs: 8000,
        createdAt: now,
      ),
    ]);
    await DatabaseService.insertSubtitleClips([
      ..._clips('video-long', const [2000, 4000, 7000]),
      ..._clips('video-short', const [0, 2000, 5000]),
    ]);
    await DatabaseService.replaceSyncResults(project.id, [
      _sync(
        id: 'sync-long',
        projectId: project.id,
        videoFileId: 'video-long',
        durationMs: 10000,
        timelineStartMs: 0,
        timelineEndMs: 10000,
        now: now,
      ),
      _sync(
        id: 'sync-short',
        projectId: project.id,
        videoFileId: 'video-short',
        durationMs: 6000,
        timelineStartMs: 2000,
        timelineEndMs: 8000,
        now: now,
      ),
    ]);

    final timelineList = await AudioAlignService.buildTimeline(project.id);
    final byVideoId = {
      for (final timeline in timelineList) timeline.videoFileId: timeline,
    };

    expect(byVideoId['video-long']!.videoTrackIndex, 0);
    expect(byVideoId['video-long']!.multicamRole, '基准机位');
    expect(byVideoId['video-short']!.videoTrackIndex, 1);
    expect(byVideoId['video-short']!.multicamRole, '上方机位');
    expect(
      byVideoId['video-short']!.multicamAnchorCount,
      greaterThanOrEqualTo(3),
    );
  });
}

SyncResult _sync({
  required String id,
  required String projectId,
  required String videoFileId,
  required int durationMs,
  required int timelineStartMs,
  required int timelineEndMs,
  required DateTime now,
}) {
  return SyncResult(
    id: id,
    projectId: projectId,
    videoFileId: videoFileId,
    audioFileId: null,
    videoDurationMs: durationMs,
    timelineStartMs: timelineStartMs,
    timelineEndMs: timelineEndMs,
    confidence: 0.95,
    status: SyncStatus.autoAccepted,
    method: SyncMethod.subtitleOnly,
    reviewStatus: SyncReviewStatus.notRequired,
    createdAt: now,
  );
}

List<SubtitleClip> _clips(String mediaFileId, List<int> starts) {
  const texts = ['第一句准备开始', '第二句继续拍摄', '第三句结束动作'];
  return List.generate(starts.length, (index) {
    final text = texts[index];
    return SubtitleClip(
      id: '$mediaFileId-clip-$index',
      mediaFileId: mediaFileId,
      sourceKind: 'local',
      startMs: starts[index],
      endMs: starts[index] + 700,
      localStartMs: starts[index],
      localEndMs: starts[index] + 700,
      text: text,
      normalizedText: text,
      sortOrder: index,
    );
  });
}
