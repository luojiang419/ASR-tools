import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/models/media_file.dart';
import 'package:asr_tools/services/media_scan_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media-scan-service-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('scans nested video files without following symlink loops', () async {
    final nestedDir = Directory('${tempDir.path}/nested')..createSync();
    File('${tempDir.path}/a.mp4').writeAsStringSync('');
    File('${tempDir.path}/c.m4v').writeAsStringSync('');
    File('${nestedDir.path}/b.mov').writeAsStringSync('');
    Link('${nestedDir.path}/loop').createSync(tempDir.path);

    final results = await MediaScanService.scanDirectory(
      tempDir.path,
      MediaType.video,
    );

    expect(results.map((file) => file.name).toList(), [
      'a.mp4',
      'b.mov',
      'c.m4v',
    ]);
  });
}
