import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/services/asr_batch_service.dart';
import 'package:asr_tools/widgets/asr_progress_panel.dart';

void main() {
  testWidgets('completed progress shows lightweight segment count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsrProgressPanel(
            progress: const AsrFileProgress(
              mediaFileId: 'audio-1',
              fileName: 'A0001.wav',
              status: AsrFileStatus.completed,
              progress: 1.0,
              segmentCount: 12,
            ),
          ),
        ),
      ),
    );

    expect(find.text('识别到 12 个段落'), findsOneWidget);
  });

  testWidgets('non-completed progress hides segment count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsrProgressPanel(
            progress: const AsrFileProgress(
              mediaFileId: 'audio-1',
              fileName: 'A0001.wav',
              status: AsrFileStatus.recognizing,
              progress: 0.6,
              segmentCount: 12,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('识别到 '), findsNothing);
  });
}
