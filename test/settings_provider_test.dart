import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asr_tools/providers/settings_provider.dart';
import 'package:asr_tools/services/runtime_path_service.dart';

void main() {
  test('AppSettings defaults to dock navigation style', () {
    const settings = AppSettings();

    expect(settings.projectNavigationStyle, 'dock');
  });

  test('AppSettings.fromMap uses dock when navigation style is missing', () {
    final settings = AppSettings.fromMap(const {});

    expect(settings.projectNavigationStyle, 'dock');
  });

  test(
    'AppSettings.fromMap uses normalized runtime defaults when paths are missing',
    () {
      final settings = AppSettings.fromMap(const {});

      expect(settings.ffmpegPath, RuntimePathService.defaultFfmpegDir);
      expect(settings.sherpaOnnxPath, RuntimePathService.defaultSherpaOnnxDir);
      expect(settings.proxyAddress, RuntimePathService.defaultProxyAddress);
    },
  );

  test(
    'AppSettings.fromMap replaces legacy Windows placeholders on non-Windows',
    () {
      final settings = AppSettings.fromMap(const {
        'ffmpeg_path': r'G:\data\app\DIT\ffmpeg',
        'sherpa_onnx_path': r'G:\data\app\DIT\sherpa-onnx',
        'proxy_address': '192.168.0.211:7890',
      });

      if (Platform.isWindows) {
        expect(settings.ffmpegPath, r'G:\data\app\DIT\ffmpeg');
        expect(settings.sherpaOnnxPath, r'G:\data\app\DIT\sherpa-onnx');
      } else {
        expect(settings.ffmpegPath, RuntimePathService.defaultFfmpegDir);
        expect(
          settings.sherpaOnnxPath,
          RuntimePathService.defaultSherpaOnnxDir,
        );
      }
      expect(settings.proxyAddress, RuntimePathService.defaultProxyAddress);
    },
  );

  test('AppSettings.fromMap keeps explicit menu navigation style', () {
    final settings = AppSettings.fromMap(const {
      'project_navigation_style': 'menu',
    });

    expect(settings.projectNavigationStyle, 'menu');
  });

  test('AppSettings.fromMap keeps explicit dock navigation style', () {
    final settings = AppSettings.fromMap(const {
      'project_navigation_style': 'dock',
    });

    expect(settings.projectNavigationStyle, 'dock');
  });
}
