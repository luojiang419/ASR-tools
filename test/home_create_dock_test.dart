import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:asr_tools/l10n/app_localizations.dart';
import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/providers/project_list_provider.dart';
import 'package:asr_tools/screens/create_project_screen.dart';
import 'package:asr_tools/screens/home_screen.dart';
import 'package:asr_tools/widgets/app_bottom_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home screen shows global dock and opens create project page', (
    tester,
  ) async {
    _testProjectListState = const ProjectListState(
      projects: [],
      isLoading: false,
    );
    _createdProject = _sampleProject;
    _lastCreatedName = null;

    await tester.pumpWidget(_buildHomeCreateApp(initialLocation: '/'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDockButton), findsNWidgets(2));
    expect(find.text('工程'), findsOneWidget);
    expect(find.text('新建工程'), findsOneWidget);

    await tester.tap(find.text('新建工程'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateProjectScreen), findsOneWidget);
    expect(find.byType(AppDockButton), findsNWidgets(2));
  });

  testWidgets('create project page submits and navigates to new project', (
    tester,
  ) async {
    _testProjectListState = const ProjectListState(
      projects: [],
      isLoading: false,
    );
    _createdProject = _sampleProject;
    _lastCreatedName = null;

    await tester.pumpWidget(
      _buildHomeCreateApp(initialLocation: '/project/new'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '新的工程');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(_lastCreatedName, '新的工程');
    expect(find.text('opened:project-created'), findsOneWidget);
  });
}

Widget _buildHomeCreateApp({required String initialLocation}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/project/new',
        builder: (context, state) => const CreateProjectScreen(),
      ),
      GoRoute(
        path: '/project/:id',
        builder: (context, state) =>
            Text('opened:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [projectListProvider.overrideWith(TestProjectListNotifier.new)],
    child: MaterialApp.router(
      locale: const Locale('zh', 'CN'),
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

final _sampleProject = AsrProject(
  id: 'project-created',
  name: '创建后的工程',
  createdAt: DateTime(2026, 5, 20, 12),
  updatedAt: DateTime(2026, 5, 20, 12),
);

late ProjectListState _testProjectListState;
AsrProject _createdProject = _sampleProject;
String? _lastCreatedName;

class TestProjectListNotifier extends ProjectListNotifier {
  @override
  ProjectListState build() => _testProjectListState;

  @override
  Future<void> loadProjects() async {}

  @override
  Future<AsrProject> createProject(String name) async {
    _lastCreatedName = name;
    return _createdProject.copyWith(name: name);
  }
}
