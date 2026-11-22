import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/l10n/app_localizations.dart';
import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/models/subtitle_file.dart';
import 'package:asr_tools/models/timeline_data.dart';
import 'package:asr_tools/providers/asr_process_provider.dart';
import 'package:asr_tools/providers/match_provider.dart';
import 'package:asr_tools/providers/project_detail_provider.dart';
import 'package:asr_tools/providers/settings_provider.dart';
import 'package:asr_tools/providers/timeline_provider.dart';
import 'package:asr_tools/screens/project_screen.dart';
import 'package:asr_tools/widgets/app_bottom_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'project screen keeps only one import status group in menu style',
    (tester) async {
      _testSettings = const AppSettings(projectNavigationStyle: 'menu');
      _testProjectDetailState = _buildProjectDetailState(activeSectionIndex: 0);
      _testTimelineState = const TimelineState();
      _testMatchState = const MatchState();

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      await tester.pumpWidget(_buildProjectScreen());
      await tester.pumpAndSettle();

      expect(find.text('字幕准备'), findsNothing);
      expect(find.text('反解字幕并建立索引'), findsOneWidget);
      expect(find.text('进入下一步'), findsOneWidget);
      expect(find.text('字幕反解与补录'), findsOneWidget);
      expect(find.text('视频 1'), findsOneWidget);
      expect(find.text('音频 1 / 1组'), findsOneWidget);

      final prepareX = tester.getTopLeft(find.text('反解字幕并建立索引')).dx;
      final nextX = tester.getTopLeft(find.text('进入下一步')).dx;
      expect(prepareX, lessThan(nextX));
    },
  );

  testWidgets(
    'dock mode shows separate project button, module dock, and import actions',
    (tester) async {
      _testSettings = const AppSettings(projectNavigationStyle: 'dock');
      _testProjectDetailState = _buildProjectDetailState(activeSectionIndex: 0);
      _testTimelineState = const TimelineState();
      _testMatchState = const MatchState();

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      await tester.pumpWidget(_buildProjectScreen());
      await tester.pumpAndSettle();

      expect(find.byType(AppDockButton), findsNWidgets(4));
      expect(find.text('工程'), findsOneWidget);
      expect(find.text('反解字幕并建立索引'), findsOneWidget);
      expect(find.text('进入下一步'), findsOneWidget);

      final projectX = tester.getTopLeft(find.text('工程')).dx;
      final dockX = tester.getTopLeft(find.text('时间线与导出')).dx;
      final nextX = tester.getTopLeft(find.text('进入下一步')).dx;
      expect(projectX, lessThan(dockX));
      expect(dockX, lessThan(nextX));
    },
  );

  testWidgets('dock mode shows match action buttons on match page', (
    tester,
  ) async {
    _testSettings = const AppSettings(projectNavigationStyle: 'dock');
    _testProjectDetailState = _buildProjectDetailState(activeSectionIndex: 1);
    _testTimelineState = const TimelineState();
    _testMatchState = const MatchState();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    await tester.pumpWidget(_buildProjectScreen());
    await tester.pumpAndSettle();

    expect(find.byType(AppDockButton), findsNWidgets(4));
    expect(find.text('工程'), findsOneWidget);
    expect(find.text('一键合板'), findsAtLeastNWidgets(2));
    expect(find.text('进入下一步'), findsOneWidget);
  });

  testWidgets(
    'dock mode keeps timeline export tools in page and not in bottom action area',
    (tester) async {
      _testSettings = const AppSettings(projectNavigationStyle: 'dock');
      _testProjectDetailState = _buildProjectDetailState(activeSectionIndex: 2);
      _testTimelineState = TimelineState(timelineList: [_sampleTimelineData]);
      _testMatchState = const MatchState();

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      await tester.pumpWidget(_buildProjectScreen());
      await tester.pumpAndSettle();

      expect(find.byType(AppDockButton), findsNWidgets(4));
      expect(find.text('导出精简版 XML'), findsOneWidget);
      expect(find.text('反解字幕并建立索引'), findsNothing);
      expect(find.text('取消合板'), findsNothing);
      expect(find.text('完成工程'), findsOneWidget);
    },
  );
}

Widget _buildProjectScreen() {
  return ProviderScope(
    overrides: [
      projectDetailProvider.overrideWith(TestProjectDetailNotifier.new),
      settingsProvider.overrideWith(TestSettingsNotifier.new),
      matchProvider.overrideWith(TestMatchNotifier.new),
      timelineProvider.overrideWith(TestTimelineNotifier.new),
      asrProcessProvider.overrideWith(TestAsrProcessNotifier.new),
    ],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ProjectScreen(projectId: 'project-1'),
    ),
  );
}

ProjectDetailState _buildProjectDetailState({required int activeSectionIndex}) {
  return ProjectDetailState(
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
    activeSectionIndex: activeSectionIndex,
  );
}

const _sampleTimelineData = TimelineData(
  syncResultId: 'sync-1',
  videoFileId: 'video-1',
  audioFileId: 'audio-1',
  videoFileName: 'C0001.mp4',
  audioFileName: 'A0001.wav',
  videoEndMs: 4200,
  timelineEndMs: 4200,
  audioOriginalDurationMs: 4200,
  audioTrimEndMs: 4200,
);

late ProjectDetailState _testProjectDetailState;
late AppSettings _testSettings;
late TimelineState _testTimelineState;
late MatchState _testMatchState;

class TestProjectDetailNotifier extends ProjectDetailNotifier {
  @override
  ProjectDetailState build() => _testProjectDetailState;

  @override
  Future<void> loadProject(String projectId) async {}
}

class TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => _testSettings;

  @override
  Future<void> toggleProjectNavigationStyle() async {}

  @override
  Future<void> toggleThemeMode() async {}
}

class TestMatchNotifier extends MatchNotifier {
  @override
  MatchState build() => _testMatchState;
}

class TestTimelineNotifier extends TimelineNotifier {
  @override
  TimelineState build() => _testTimelineState;
}

class TestAsrProcessNotifier extends AsrProcessNotifier {
  @override
  AsrProcessState build() => const AsrProcessState();
}
