import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/subtitle_file.dart';
import 'package:asr_tools/models/sync_result.dart';
import 'package:asr_tools/providers/project_detail_provider.dart';
import 'package:asr_tools/widgets/common/video_thumbnail_view.dart';
import 'package:asr_tools/widgets/match_result_tile.dart';
import 'package:asr_tools/widgets/step_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video-thumb-ui-');
    final imageFile = File('${tempDir.path}/thumb.png');
    await imageFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2WZp0AAAAASUVORK5CYII=',
      ),
    );
    imagePath = imageFile.path;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('video thumbnail view renders image and placeholder states', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: VideoThumbnailView(thumbnailPath: null)),
      ),
    );

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoThumbnailView(thumbnailPath: imagePath)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('step import renders thumbnail for video materials', (
    tester,
  ) async {
    _testProjectDetailState = ProjectDetailState(
      project: AsrProject(
        id: 'project-1',
        name: '测试工程',
        createdAt: DateTime(2026, 5, 20, 10),
        updatedAt: DateTime(2026, 5, 20, 10),
      ),
      videoFiles: [
        MediaFile(
          id: 'video-1',
          projectId: 'project-1',
          filePath: r'G:\video\C0001.mp4',
          type: MediaType.video,
          thumbnailPath: imagePath,
          durationMs: 4200,
          createdAt: DateTime(2026, 5, 20, 10),
        ),
      ],
      audioFiles: [
        MediaFile(
          id: 'audio-1',
          projectId: 'project-1',
          filePath: r'G:\audio\A0001.wav',
          type: MediaType.audio,
          durationMs: 4200,
          createdAt: DateTime(2026, 5, 20, 10),
        ),
      ],
      videoSubtitleFiles: const [],
      audioSubtitleFiles: const [],
    );

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectDetailProvider.overrideWith(TestProjectDetailNotifier.new),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StepImport(projectId: 'project-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VideoThumbnailView), findsOneWidget);
    expect(find.text('C0001.mp4'), findsOneWidget);
    expect(find.text('素材导入'), findsNothing);
    expect(
      find.text('按四个区域分别导入视频、音频、视频字幕和音频字幕。素材顺序就是后续总字幕反解的平铺顺序。'),
      findsNothing,
    );
  });

  testWidgets(
    'step import shows prepared subtitle count for recognized videos',
    (tester) async {
      _testProjectDetailState = ProjectDetailState(
        project: AsrProject(
          id: 'project-1',
          name: '测试工程',
          status: ProjectStatus.recognized,
          createdAt: DateTime(2026, 5, 20, 10),
          updatedAt: DateTime(2026, 5, 20, 10),
        ),
        videoFiles: [
          MediaFile(
            id: 'video-1',
            projectId: 'project-1',
            filePath: r'G:\video\C0001.mp4',
            type: MediaType.video,
            thumbnailPath: imagePath,
            durationMs: 4200,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        audioFiles: [
          MediaFile(
            id: 'audio-1',
            projectId: 'project-1',
            filePath: r'G:\audio\A0001.wav',
            type: MediaType.audio,
            durationMs: 4200,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        videoSubtitleFiles: [
          SubtitleFile(
            id: 'vs-1',
            projectId: 'project-1',
            filePath: r'G:\subs\video.srt',
            mediaType: MediaType.video,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        audioSubtitleFiles: [
          SubtitleFile(
            id: 'as-1',
            projectId: 'project-1',
            filePath: r'G:\subs\audio.srt',
            mediaType: MediaType.audio,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        preparedSubtitleCountByMediaId: const {'video-1': 3},
      );

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectDetailProvider.overrideWith(TestProjectDetailNotifier.new),
          ],
          child: const MaterialApp(
            home: Scaffold(body: StepImport(projectId: 'project-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('字幕 3'), findsOneWidget);
    },
  );

  testWidgets(
    'step import shows zero subtitle count when recognized video has no clips',
    (tester) async {
      _testProjectDetailState = ProjectDetailState(
        project: AsrProject(
          id: 'project-1',
          name: '测试工程',
          status: ProjectStatus.recognized,
          createdAt: DateTime(2026, 5, 20, 10),
          updatedAt: DateTime(2026, 5, 20, 10),
        ),
        videoFiles: [
          MediaFile(
            id: 'video-1',
            projectId: 'project-1',
            filePath: r'G:\video\C0001.mp4',
            type: MediaType.video,
            thumbnailPath: imagePath,
            durationMs: 4200,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        audioFiles: [
          MediaFile(
            id: 'audio-1',
            projectId: 'project-1',
            filePath: r'G:\audio\A0001.wav',
            type: MediaType.audio,
            durationMs: 4200,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        videoSubtitleFiles: [
          SubtitleFile(
            id: 'vs-1',
            projectId: 'project-1',
            filePath: r'G:\subs\video.srt',
            mediaType: MediaType.video,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
        audioSubtitleFiles: [
          SubtitleFile(
            id: 'as-1',
            projectId: 'project-1',
            filePath: r'G:\subs\audio.srt',
            mediaType: MediaType.audio,
            createdAt: DateTime(2026, 5, 20, 10),
          ),
        ],
      );

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectDetailProvider.overrideWith(TestProjectDetailNotifier.new),
          ],
          child: const MaterialApp(
            home: Scaffold(body: StepImport(projectId: 'project-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('字幕 0'), findsOneWidget);
    },
  );

  testWidgets('step import disables clear button when media list is empty', (
    tester,
  ) async {
    _testProjectDetailState = ProjectDetailState(
      project: AsrProject(
        id: 'project-1',
        name: '测试工程',
        createdAt: DateTime(2026, 5, 20, 10),
        updatedAt: DateTime(2026, 5, 20, 10),
      ),
    );
    _lastClearedType = null;

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectDetailProvider.overrideWith(ClearMediaTestNotifier.new),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StepImport(projectId: 'project-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clearButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '清空').first,
    );
    expect(clearButton.onPressed, isNull);
    expect(_lastClearedType, isNull);
  });

  testWidgets('step import clears selected video media after confirmation', (
    tester,
  ) async {
    _testProjectDetailState = ProjectDetailState(
      project: AsrProject(
        id: 'project-1',
        name: '测试工程',
        createdAt: DateTime(2026, 5, 20, 10),
        updatedAt: DateTime(2026, 5, 20, 10),
      ),
      videoFiles: [
        MediaFile(
          id: 'video-1',
          projectId: 'project-1',
          filePath: r'G:\video\C0001.mp4',
          type: MediaType.video,
          thumbnailPath: imagePath,
          durationMs: 4200,
          createdAt: DateTime(2026, 5, 20, 10),
        ),
      ],
      audioFiles: [
        MediaFile(
          id: 'audio-1',
          projectId: 'project-1',
          filePath: r'G:\audio\A0001.wav',
          type: MediaType.audio,
          durationMs: 4200,
          createdAt: DateTime(2026, 5, 20, 10),
        ),
      ],
    );
    _lastClearedType = null;

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectDetailProvider.overrideWith(ClearMediaTestNotifier.new),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StepImport(projectId: 'project-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '清空').first);
    await tester.pumpAndSettle();

    expect(find.text('清空视频素材'), findsOneWidget);
    expect(find.text('确认清空当前已导入的视频素材吗？共 1 个文件。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认清空'));
    await tester.pumpAndSettle();

    expect(_lastClearedType, MediaType.video);
    expect(find.text('视频素材已清空'), findsOneWidget);
  });

  testWidgets(
    'step import header wraps actions on compact width without overflow',
    (tester) async {
      _testProjectDetailState = ProjectDetailState(
        project: AsrProject(
          id: 'project-1',
          name: '测试工程',
          createdAt: DateTime(2026, 5, 20, 10),
          updatedAt: DateTime(2026, 5, 20, 10),
        ),
      );

      await tester.binding.setSurfaceSize(const Size(900, 960));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectDetailProvider.overrideWith(TestProjectDetailNotifier.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 500,
                  child: StepImport(projectId: 'project-1'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '清空'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('match result tile renders video thumbnail', (tester) async {
    final result = SyncResult(
      id: 'sync-1',
      projectId: 'project-1',
      videoFileId: 'video-1',
      audioFileId: 'audio-1',
      videoDurationMs: 4000,
      timelineStartMs: 0,
      timelineEndMs: 4000,
      audioSourceInMs: 0,
      audioSourceOutMs: 4000,
      confidence: 0.92,
      anchorCount: 2,
      status: SyncStatus.autoAccepted,
      method: SyncMethod.subtitleOnly,
      createdAt: DateTime(2026, 5, 20, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchResultTile(
            result: result,
            videoFile: MediaFile(
              id: 'video-1',
              projectId: 'project-1',
              filePath: r'G:\video\C0001.mp4',
              type: MediaType.video,
              thumbnailPath: imagePath,
              createdAt: DateTime(2026, 5, 20, 10),
            ),
            audioFile: MediaFile(
              id: 'audio-1',
              projectId: 'project-1',
              filePath: r'G:\audio\A0001.wav',
              type: MediaType.audio,
              createdAt: DateTime(2026, 5, 20, 10),
            ),
            onOpenDetail: () {},
            onSecondaryAction: () {},
            secondaryTooltip: '标记移除',
            secondaryIcon: Icons.remove_circle_outline,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VideoThumbnailView), findsOneWidget);
    expect(find.text('C0001.mp4'), findsOneWidget);
  });
}

late ProjectDetailState _testProjectDetailState;
MediaType? _lastClearedType;

class TestProjectDetailNotifier extends ProjectDetailNotifier {
  @override
  ProjectDetailState build() => _testProjectDetailState;
}

class ClearMediaTestNotifier extends TestProjectDetailNotifier {
  @override
  Future<void> clearMediaFiles(MediaType type) async {
    _lastClearedType = type;
  }
}
