import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/sync_result.dart';
import 'package:asr_tools/services/database_service.dart';
import 'package:asr_tools/services/subtitle_match_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'subtitle-match-multitrack-',
    );
    await DatabaseService.init(
      overridePath: p.join(tempDir.path, 'subtitle-match-multitrack.db'),
    );
  });

  tearDown(() async {
    await DatabaseService.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'getUnmatchedAudios returns one representative per multitrack group',
    () async {
      final now = DateTime(2026, 6, 2, 12, 0);
      final project = AsrProject(
        id: 'project-1',
        name: '多轨测试',
        createdAt: now,
        updatedAt: now,
      );
      await DatabaseService.insertProject(project);
      await DatabaseService.insertMediaFiles([
        MediaFile(
          id: 'audio-lr',
          projectId: project.id,
          filePath: r'G:\audio\ZOOM0147_LR.wav',
          type: MediaType.audio,
          durationMs: 6000,
          createdAt: now,
        ),
        MediaFile(
          id: 'audio-tr1',
          projectId: project.id,
          filePath: r'G:\audio\ZOOM0147_Tr1.wav',
          type: MediaType.audio,
          durationMs: 5800,
          createdAt: now,
        ),
      ]);

      final unmatched = await SubtitleMatchService.getUnmatchedAudios(
        project.id,
      );

      expect(unmatched, hasLength(1));
    },
  );

  test(
    'matched representative hides the whole multitrack group from unmatched list',
    () async {
      final now = DateTime(2026, 6, 2, 12, 30);
      final project = AsrProject(
        id: 'project-2',
        name: '多轨测试2',
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
          createdAt: now,
        ),
        MediaFile(
          id: 'audio-lr',
          projectId: project.id,
          filePath: r'G:\audio\ZOOM0147_LR.wav',
          type: MediaType.audio,
          durationMs: 6000,
          createdAt: now,
        ),
        MediaFile(
          id: 'audio-tr1',
          projectId: project.id,
          filePath: r'G:\audio\ZOOM0147_Tr1.wav',
          type: MediaType.audio,
          durationMs: 5800,
          createdAt: now,
        ),
      ]);
      await DatabaseService.replaceSyncResults(project.id, [
        SyncResult(
          id: 'sync-1',
          projectId: project.id,
          videoFileId: 'video-1',
          audioFileId: 'audio-lr',
          videoDurationMs: 4000,
          timelineStartMs: 0,
          timelineEndMs: 4000,
          audioSourceInMs: 300,
          audioSourceOutMs: 4300,
          confidence: 0.95,
          status: SyncStatus.autoAccepted,
          method: SyncMethod.subtitleOnly,
          createdAt: now,
        ),
      ]);

      final unmatched = await SubtitleMatchService.getUnmatchedAudios(
        project.id,
      );

      expect(unmatched, isEmpty);
    },
  );
}
