import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/models/asr_project.dart';
import 'package:asr_tools/providers/project_detail_provider.dart';
import 'package:asr_tools/widgets/step_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('step import shows snackbar when directory picker throws', (
    tester,
  ) async {
    FilePicker.platform = _ThrowingFilePicker('ENTITLEMENT_NOT_FOUND');
    await tester.binding.setSurfaceSize(const Size(1440, 960));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectDetailProvider.overrideWith(
            StepImportPickerErrorProjectDetailNotifier.new,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StepImport(projectId: 'project-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '目录').first);
    await tester.pump();

    expect(find.textContaining('选择视频目录失败'), findsOneWidget);
    expect(find.textContaining('ENTITLEMENT_NOT_FOUND'), findsOneWidget);
  });

  testWidgets('step import shows snackbar when subtitle picker throws', (
    tester,
  ) async {
    FilePicker.platform = _ThrowingFilePicker('ENTITLEMENT_NOT_FOUND');
    await tester.binding.setSurfaceSize(const Size(1440, 960));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectDetailProvider.overrideWith(
            StepImportPickerErrorProjectDetailNotifier.new,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StepImport(projectId: 'project-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '导入 SRT').first);
    await tester.pump();

    expect(find.textContaining('选择视频字幕失败'), findsOneWidget);
    expect(find.textContaining('ENTITLEMENT_NOT_FOUND'), findsOneWidget);
  });
}

class StepImportPickerErrorProjectDetailNotifier extends ProjectDetailNotifier {
  @override
  ProjectDetailState build() {
    return ProjectDetailState(
      project: AsrProject(
        id: 'project-1',
        name: '测试工程',
        createdAt: DateTime(2026, 5, 31, 10),
        updatedAt: DateTime(2026, 5, 31, 10),
      ),
      activeSectionIndex: 0,
    );
  }

  @override
  Future<void> loadProject(String projectId) async {}
}

class _ThrowingFilePicker extends FilePicker {
  _ThrowingFilePicker(this.message);

  final String message;

  @override
  Future<bool?> clearTemporaryFiles() async => true;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    throw Exception(message);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus p1)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    throw Exception(message);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic bytes,
    bool lockParentWindow = false,
  }) async {
    throw Exception(message);
  }
}
