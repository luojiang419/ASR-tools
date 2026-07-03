import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/subtitle_clip.dart';
import 'package:asr_tools/providers/asr_process_provider.dart';
import 'package:asr_tools/services/database_service.dart';

void main() {
  late Directory sandboxRoot;
  late String databasePath;

  setUp(() async {
    sandboxRoot = await Directory.systemTemp.createTemp(
      'asr_process_provider_test_',
    );
    databasePath = p.join(sandboxRoot.path, 'asr_process.sqlite');
    await DatabaseService.init(overridePath: databasePath);
  });

  tearDown(() async {
    await DatabaseService.close();
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  test(
    'hasUnrecognizedFiles returns true when any media has no prepared clips',
    () async {
      final project = await _seedProject();
      await DatabaseService.insertSubtitleClips([
        const SubtitleClip(
          id: 'clip-1',
          mediaFileId: 'audio-1',
          startMs: 0,
          endMs: 500,
          text: '你好',
          normalizedText: '你好',
          sortOrder: 0,
        ),
      ]);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(asrProcessProvider.notifier);
      final hasUnrecognized = await notifier.hasUnrecognizedFiles(project.id);

      expect(hasUnrecognized, isTrue);
    },
  );

  test(
    'hasUnrecognizedFiles returns false when every media has prepared clips',
    () async {
      final project = await _seedProject();
      await DatabaseService.insertSubtitleClips([
        const SubtitleClip(
          id: 'clip-1',
          mediaFileId: 'audio-1',
          startMs: 0,
          endMs: 500,
          text: '你好',
          normalizedText: '你好',
          sortOrder: 0,
        ),
        const SubtitleClip(
          id: 'clip-2',
          mediaFileId: 'video-1',
          startMs: 0,
          endMs: 500,
          text: '世界',
          normalizedText: '世界',
          sortOrder: 0,
        ),
      ]);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(asrProcessProvider.notifier);
      final hasUnrecognized = await notifier.hasUnrecognizedFiles(project.id);

      expect(hasUnrecognized, isFalse);
    },
  );
}

Future<AsrProject> _seedProject() async {
  final project = AsrProject(
    id: 'project-1',
    name: '批量识别测试',
    status: ProjectStatus.imported,
    createdAt: DateTime(2026, 6, 30, 18),
    updatedAt: DateTime(2026, 6, 30, 18),
  );
  await DatabaseService.insertProject(project);
  await DatabaseService.insertMediaFiles([
    MediaFile(
      id: 'video-1',
      projectId: project.id,
      filePath: r'/tmp/C0001.mp4',
      type: MediaType.video,
      durationMs: 1000,
      createdAt: DateTime(2026, 6, 30, 18),
    ),
    MediaFile(
      id: 'audio-1',
      projectId: project.id,
      filePath: r'/tmp/A0001.wav',
      type: MediaType.audio,
      durationMs: 1000,
      createdAt: DateTime(2026, 6, 30, 18),
    ),
  ]);
  return project;
}
