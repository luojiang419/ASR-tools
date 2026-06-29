import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:asr_tools/services/ffmpeg_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ffmpeg-service-test-');
  });

  tearDown(() async {
    FfmpegService.setFfmpegDir('');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'detects ffmpeg binaries from selected directory on current platform',
    () {
      final ffmpegName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final ffprobeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';

      File(p.join(tempDir.path, ffmpegName)).writeAsStringSync('');
      File(p.join(tempDir.path, ffprobeName)).writeAsStringSync('');

      FfmpegService.setFfmpegDir(tempDir.path);

      expect(FfmpegService.ffmpegPath, p.join(tempDir.path, ffmpegName));
      expect(FfmpegService.ffprobePath, p.join(tempDir.path, ffprobeName));
      expect(FfmpegService.isConfigured, isTrue);
      expect(FfmpegService.canProbeMedia, isTrue);
    },
  );

  test('detects ffmpeg binaries from bin subdirectory on current platform', () {
    final ffmpegName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final ffprobeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    final binDir = Directory(p.join(tempDir.path, 'bin'))..createSync();

    File(p.join(binDir.path, ffmpegName)).writeAsStringSync('');
    File(p.join(binDir.path, ffprobeName)).writeAsStringSync('');

    FfmpegService.setFfmpegDir(tempDir.path);

    expect(FfmpegService.ffmpegPath, p.join(binDir.path, ffmpegName));
    expect(FfmpegService.ffprobePath, p.join(binDir.path, ffprobeName));
    expect(FfmpegService.isConfigured, isTrue);
    expect(FfmpegService.canProbeMedia, isTrue);
  });
}
