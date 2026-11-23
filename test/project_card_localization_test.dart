import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/l10n/app_localizations.dart';
import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/widgets/project_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('project card popup menu and dialogs use Chinese text', (
    tester,
  ) async {
    await tester.pumpWidget(_buildProjectCardApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('打开工程'), findsOneWidget);
    expect(find.text('删除工程'), findsOneWidget);

    await tester.tap(find.text('重命名').last);
    await tester.pumpAndSettle();

    expect(find.text('重命名工程'), findsOneWidget);
    expect(find.text('请输入新的工程名称'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除工程').last);
    await tester.pumpAndSettle();

    expect(find.text('确认删除'), findsOneWidget);
    expect(find.text('确定要删除工程「测试工程」吗？此操作不可恢复。'), findsOneWidget);
  });
}

Widget _buildProjectCardApp() {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            height: 180,
            child: ProjectCard(
              project: AsrProject(
                id: 'project-1',
                name: '测试工程',
                createdAt: DateTime(2026, 5, 20, 10),
                updatedAt: DateTime(2026, 5, 20, 10),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
