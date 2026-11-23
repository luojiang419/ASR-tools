import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/providers/project_detail_provider.dart';
import 'package:asr_tools/services/app_data_service.dart';
import 'package:asr_tools/services/database_service.dart';

void main() {
  late Directory sandboxRoot;
  late Directory executableDir;
  late String databasePath;

  setUp(() async {
    sandboxRoot = await Directory.systemTemp.createTemp(
      'project_detail_provider_test_',
    );
    executableDir = Directory(p.join(sandboxRoot.path, 'runtime'))
      ..createSync(recursive: true);
    AppDataService.debugOverrideDirectories(executableDir: executableDir.path);
    databasePath = p.join(sandboxRoot.path, 'project_detail.sqlite');
    await DatabaseService.init(overridePath: databasePath);
  });

  tearDown(() async {
    await DatabaseService.close();
    AppDataService.debugResetOverrides();
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  test(
    'clearMediaFiles clears video directory but preserves audio directory',
    () async {
      final seed = await _seedProject();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(projectDetailProvider.notifier);
      await notifier.loadProject(seed.id);
      await notifier.clearMediaFiles(MediaType.video);

      final stored = await DatabaseService.getProject(seed.id);
      final videos = await DatabaseService.getMediaFiles(
        seed.id,
        type: MediaType.video,
      );
      final audios = await DatabaseService.getMediaFiles(
        seed.id,
        type: MediaType.audio,
      );

      expect(stored?.videoDirectory, isNull);
      expect(stored?.audioDirectory, seed.audioDirectory);
      expect(videos, isEmpty);
      expect(audios, hasLength(1));
    },
  );

  test(
    'clearMediaFiles clears audio directory but preserves video directory',
    () async {
      final seed = await _seedProject();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(projectDetailProvider.notifier);
      await notifier.loadProject(seed.id);
      await notifier.clearMediaFiles(MediaType.audio);

      final stored = await DatabaseService.getProject(seed.id);
      final videos = await DatabaseService.getMediaFiles(
        seed.id,
        type: MediaType.video,
      );
      final audios = await DatabaseService.getMediaFiles(
        seed.id,
        type: MediaType.audio,
      );

      expect(stored?.videoDirectory, seed.videoDirectory);
      expect(stored?.audioDirectory, isNull);
      expect(videos, hasLength(1));
      expect(audios, isEmpty);
    },
  );

  test(
    'importVideoDirectory scans nested files and skips duplicate paths',
    () async {
      final project = await _seedEmptyProject();
      final videoDir = Directory(p.join(sandboxRoot.path, 'video'))
        ..createSync(recursive: true);
      final nestedDir = Directory(p.join(videoDir.path, 'nested'))
        ..createSync();
      File(p.join(videoDir.path, 'C0001.mp4')).writeAsStringSync('');
      File(p.join(nestedDir.path, 'C0002.mov')).writeAsStringSync('');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(projectDetailProvider.notifier);
      await notifier.loadProject(project.id);
      await notifier.importVideoDirectory(videoDir.path);
      await notifier.importVideoDirectory(videoDir.path);

      final videos = await DatabaseService.getMediaFiles(
        project.id,
        type: MediaType.video,
      );
      final stored = await DatabaseService.getProject(project.id);

      expect(videos.map((file) => p.basename(file.filePath)).toList(), [
        'C0001.mp4',
        'C0002.mov',
      ]);
      expect(stored?.videoDirectory, videoDir.path);
    },
  );
}

Future<AsrProject> _seedProject() async {
  final project = AsrProject(
    id: 'project-1',
    name: '测试工程',
    videoDirectory: r'G:\video',
    audioDirectory: r'G:\audio',
    status: ProjectStatus.recognized,
    createdAt: DateTime(2026, 6, 3, 10),
    updatedAt: DateTime(2026, 6, 3, 10),
  );
  await DatabaseService.insertProject(project);
  await DatabaseService.insertMediaFiles([
    MediaFile(
      id: 'video-1',
      projectId: project.id,
      filePath: r'G:\video\C0001.mp4',
      type: MediaType.video,
      durationMs: 4200,
      createdAt: DateTime(2026, 6, 3, 10),
    ),
    MediaFile(
      id: 'audio-1',
      projectId: project.id,
      filePath: r'G:\audio\A0001.wav',
      type: MediaType.audio,
      durationMs: 4200,
      createdAt: DateTime(2026, 6, 3, 10),
    ),
  ]);
  return project;
}

Future<AsrProject> _seedEmptyProject() async {
  final project = AsrProject(
    id: 'project-empty',
    name: '空工程',
    status: ProjectStatus.created,
    createdAt: DateTime(2026, 6, 4, 10),
    updatedAt: DateTime(2026, 6, 4, 10),
  );
  await DatabaseService.insertProject(project);
  return project;
}
