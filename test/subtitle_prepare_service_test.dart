import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/subtitle_file.dart';
import 'package:asr_tools/services/database_service.dart';
import 'package:asr_tools/services/subtitle_prepare_service.dart';

void main() {
  late Directory sandboxRoot;
  late String databasePath;

  setUp(() async {
    sandboxRoot = await Directory.systemTemp.createTemp(
      'subtitle_prepare_service_test_',
    );
    databasePath = p.join(sandboxRoot.path, 'subtitle_prepare.sqlite');
    await DatabaseService.init(overridePath: databasePath);
  });

  tearDown(() async {
    await DatabaseService.close();
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  test('low-value short phrase gets strong penalty', () {
    final normalized = SubtitlePrepareService.normalizeTextForMatching('嗯');
    final multiplier = SubtitlePrepareService.lowValuePhraseMultiplier(
      normalized,
    );

    expect(normalized, '嗯');
    expect(multiplier, 0.25);
  });

  test('low-value short sentence gets moderate penalty', () {
    final normalized = SubtitlePrepareService.normalizeTextForMatching('好 啊');
    final multiplier = SubtitlePrepareService.lowValuePhraseMultiplier(
      normalized,
    );

    expect(multiplier, 0.4);
  });

  test('normal sentence keeps default weight', () {
    final normalized = SubtitlePrepareService.normalizeTextForMatching(
      '我们今天从船尾进去',
    );
    final multiplier = SubtitlePrepareService.lowValuePhraseMultiplier(
      normalized,
    );

    expect(multiplier, 1.0);
  });

  test(
    'prepareProject builds audio windows incrementally without changing weights',
    () async {
      final project = AsrProject(
        id: 'project-1',
        name: '字幕准备测试',
        status: ProjectStatus.imported,
        createdAt: DateTime(2026, 6, 30, 12),
        updatedAt: DateTime(2026, 6, 30, 12),
      );
      await DatabaseService.insertProject(project);

      final createdAt = DateTime(2026, 6, 30, 12);
      await DatabaseService.insertMediaFiles([
        MediaFile(
          id: 'audio-1',
          projectId: project.id,
          filePath: p.join(sandboxRoot.path, 'A001.wav'),
          type: MediaType.audio,
          durationMs: 3000,
          createdAt: createdAt,
        ),
        MediaFile(
          id: 'audio-2',
          projectId: project.id,
          filePath: p.join(sandboxRoot.path, 'A002.wav'),
          type: MediaType.audio,
          durationMs: 3000,
          createdAt: createdAt,
        ),
      ]);

      final subtitle1 = File(p.join(sandboxRoot.path, 'A001.srt'));
      final subtitle2 = File(p.join(sandboxRoot.path, 'A002.srt'));
      await subtitle1.writeAsString(_samplePerClipSrt);
      await subtitle2.writeAsString(_samplePerClipSrt);

      await DatabaseService.insertSubtitleFile(
        SubtitleFile(
          id: 'subtitle-1',
          projectId: project.id,
          filePath: subtitle1.path,
          mediaType: MediaType.audio,
          sourceType: SubtitleSourceType.perClip,
          createdAt: createdAt,
        ),
      );
      await DatabaseService.insertSubtitleFile(
        SubtitleFile(
          id: 'subtitle-2',
          projectId: project.id,
          filePath: subtitle2.path,
          mediaType: MediaType.audio,
          sourceType: SubtitleSourceType.perClip,
          createdAt: createdAt,
        ),
      );

      final summary = await SubtitlePrepareService.prepareProject(project.id);
      final windows = await DatabaseService.getSubtitleWindows(
        project.id,
        mediaType: MediaType.audio,
      );
      final byNormalized = <String, List<double>>{};
      for (final window in windows) {
        byNormalized
            .putIfAbsent(window.normalizedText, () => [])
            .add(window.uniquenessWeight);
      }

      expect(summary.preparedAudios, 2);
      expect(summary.generatedSubtitleClips, 6);
      expect(summary.generatedWindows, 8);
      expect(windows, hasLength(8));
      expect(byNormalized['你好'], everyElement(closeTo(0.5, 0.0001)));
      expect(byNormalized['世界'], everyElement(closeTo(0.5, 0.0001)));
      expect(byNormalized['测试'], everyElement(closeTo(0.5, 0.0001)));
      expect(byNormalized['你好 世界 测试'], everyElement(closeTo(0.5, 0.0001)));
    },
  );
}

const _samplePerClipSrt = '''
1
00:00:00,000 --> 00:00:00,800
你好

2
00:00:01,000 --> 00:00:01,800
世界

3
00:00:02,000 --> 00:00:02,800
测试
''';
