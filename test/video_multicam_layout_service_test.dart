import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/subtitle_clip.dart';
import 'package:asr_tools/services/database_service.dart';
import 'package:asr_tools/services/video_multicam_layout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video-multicam-layout-');
    await DatabaseService.init(
      overridePath: p.join(tempDir.path, 'video-multicam-layout.db'),
    );
  });

  tearDown(() async {
    await DatabaseService.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('places shorter matching camera above the longest camera', () async {
    final now = DateTime(2026, 7, 8, 10);
    final project = await _seedProject('project-1', now);
    final longVideo = _video(
      id: 'video-long',
      projectId: project.id,
      sortIndex: 0,
      durationMs: 10000,
    );
    final shortVideo = _video(
      id: 'video-short',
      projectId: project.id,
      sortIndex: 1,
      durationMs: 6000,
    );
    await DatabaseService.insertMediaFiles([longVideo, shortVideo]);
    await DatabaseService.insertSubtitleClips([
      ..._clips('video-long', const [2000, 4000, 7000]),
      ..._clips('video-short', const [0, 2000, 5000]),
    ]);

    final result = await VideoMulticamLayoutService.refreshVideoLayouts(
      project.id,
      [longVideo, shortVideo],
      allowAudioAssist: false,
    );
    final videos = {for (final video in result.updatedVideos) video.id: video};
    final longInfo = result.infoByMediaId['video-long']!;
    final shortInfo = result.infoByMediaId['video-short']!;
    final layouts = await DatabaseService.getSourceLayouts(
      project.id,
      mediaType: MediaType.video,
    );

    expect(videos['video-long']!.layoutStartMs, 0);
    expect(videos['video-long']!.layoutEndMs, 10000);
    expect(videos['video-short']!.layoutStartMs, 2000);
    expect(videos['video-short']!.layoutEndMs, 8000);
    expect(longInfo.role, MulticamRole.primary);
    expect(longInfo.videoTrackIndex, 0);
    expect(shortInfo.role, MulticamRole.angle);
    expect(shortInfo.videoTrackIndex, 1);
    expect(layouts, hasLength(2));
  });

  test(
    'shifts group right when an upper camera starts before primary',
    () async {
      final now = DateTime(2026, 7, 8, 11);
      final project = await _seedProject('project-2', now);
      final longVideo = _video(
        id: 'video-long',
        projectId: project.id,
        sortIndex: 0,
        durationMs: 10000,
      );
      final earlyShortVideo = _video(
        id: 'video-early-short',
        projectId: project.id,
        sortIndex: 1,
        durationMs: 6000,
      );
      await DatabaseService.insertMediaFiles([longVideo, earlyShortVideo]);
      await DatabaseService.insertSubtitleClips([
        ..._clips('video-long', const [2000, 4000, 7000]),
        ..._clips('video-early-short', const [5000, 7000, 10000]),
      ]);

      final result = await VideoMulticamLayoutService.refreshVideoLayouts(
        project.id,
        [longVideo, earlyShortVideo],
        allowAudioAssist: false,
      );
      final videos = {
        for (final video in result.updatedVideos) video.id: video,
      };
      final info = result.infoByMediaId['video-long']!;

      expect(videos['video-early-short']!.layoutStartMs, 0);
      expect(videos['video-early-short']!.layoutEndMs, 6000);
      expect(videos['video-long']!.layoutStartMs, 3000);
      expect(videos['video-long']!.layoutEndMs, 13000);
      expect(info.role, MulticamRole.primary);
      expect(info.note, contains('整体右移'));
    },
  );

  test('keeps unrelated videos sequential', () async {
    final now = DateTime(2026, 7, 8, 12);
    final project = await _seedProject('project-3', now);
    final first = _video(
      id: 'video-1',
      projectId: project.id,
      sortIndex: 0,
      durationMs: 4000,
    );
    final second = _video(
      id: 'video-2',
      projectId: project.id,
      sortIndex: 1,
      durationMs: 5000,
    );
    await DatabaseService.insertMediaFiles([first, second]);
    await DatabaseService.insertSubtitleClips([
      ..._clips('video-1', const [0, 1000, 2000]),
      ..._clips(
        'video-2',
        const [0, 1000, 2000],
        texts: const ['另一段内容', '完全不同对白', '不应该成组'],
      ),
    ]);

    final result = await VideoMulticamLayoutService.refreshVideoLayouts(
      project.id,
      [first, second],
      allowAudioAssist: false,
    );
    final videos = {for (final video in result.updatedVideos) video.id: video};

    expect(videos['video-1']!.layoutStartMs, 0);
    expect(videos['video-1']!.layoutEndMs, 4000);
    expect(videos['video-2']!.layoutStartMs, 4000);
    expect(videos['video-2']!.layoutEndMs, 9000);
    expect(result.infoByMediaId['video-1']!.role, MulticamRole.single);
    expect(result.infoByMediaId['video-2']!.role, MulticamRole.single);
  });
}

Future<AsrProject> _seedProject(String id, DateTime now) async {
  final project = AsrProject(
    id: id,
    name: '多机位测试',
    createdAt: now,
    updatedAt: now,
  );
  await DatabaseService.insertProject(project);
  return project;
}

MediaFile _video({
  required String id,
  required String projectId,
  required int sortIndex,
  required int durationMs,
}) {
  return MediaFile(
    id: id,
    projectId: projectId,
    filePath: 'G:\\video\\$id.mp4',
    type: MediaType.video,
    durationMs: durationMs,
    sortIndex: sortIndex,
    createdAt: DateTime(2026, 7, 8, 10),
  );
}

List<SubtitleClip> _clips(
  String mediaFileId,
  List<int> starts, {
  List<String> texts = const ['第一句准备开始', '第二句继续拍摄', '第三句结束动作'],
}) {
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
