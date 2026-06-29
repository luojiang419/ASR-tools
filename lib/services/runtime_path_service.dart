import 'dart:io';

import 'package:path/path.dart' as p;

class RuntimePathService {
  RuntimePathService._();

  static const _legacyWindowsFfmpeg = r'G:\data\app\DIT\ffmpeg';
  static const _legacyWindowsSherpa = r'G:\data\app\DIT\sherpa-onnx';
  static const _defaultProxyAddress = '127.0.0.1:7890';

  static String get defaultProxyAddress => _defaultProxyAddress;

  static String get defaultFfmpegDir {
    final bundled = _findBundledFfmpegDir();
    if (bundled != null) return bundled;

    if (Platform.isMacOS) {
      for (final dir in const [
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/bin',
      ]) {
        if (_isUsableFfmpegDir(dir)) {
          return dir;
        }
      }
      return '';
    }

    if (Platform.isWindows) {
      return _legacyWindowsFfmpeg;
    }

    for (final dir in const ['/usr/local/bin', '/usr/bin', '/bin']) {
      if (_isUsableFfmpegDir(dir)) {
        return dir;
      }
    }

    return '';
  }

  static String get defaultSherpaOnnxDir {
    final bundled = _findBundledSherpaOnnxDir();
    if (bundled != null) return bundled;

    if (Platform.isWindows) {
      return _legacyWindowsSherpa;
    }

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '';
    }

    if (Platform.isMacOS) {
      return p.join(
        home,
        'Library',
        'Application Support',
        'asr_tools',
        'runtime',
        'sherpa-onnx',
      );
    }

    return p.join(
      home,
      '.local',
      'share',
      'asr_tools',
      'runtime',
      'sherpa-onnx',
    );
  }

  static String normalizeFfmpegDir(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty &&
        !_shouldReplaceLegacyWindowsPath(trimmed) &&
        _isUsableFfmpegDir(trimmed)) {
      return trimmed;
    }
    return defaultFfmpegDir;
  }

  static String normalizeSherpaOnnxDir(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty &&
        !_shouldReplaceLegacyWindowsPath(trimmed) &&
        _isUsableSherpaOnnxDir(trimmed)) {
      return trimmed;
    }
    return defaultSherpaOnnxDir;
  }

  static String normalizeProxyAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return defaultProxyAddress;
    if (trimmed == '192.168.0.211:7890') return defaultProxyAddress;
    return trimmed;
  }

  static bool _shouldReplaceLegacyWindowsPath(String value) {
    if (Platform.isWindows) return false;
    return value == _legacyWindowsFfmpeg ||
        value == _legacyWindowsSherpa ||
        RegExp(r'^[A-Za-z]:\\').hasMatch(value);
  }

  static String? _findBundledFfmpegDir() {
    for (final base in _bundleBaseDirs()) {
      final candidate = p.join(base, 'runtime', 'ffmpeg', 'bin');
      if (_isUsableFfmpegDir(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static String? _findBundledSherpaOnnxDir() {
    for (final base in _bundleBaseDirs()) {
      final candidate = p.join(base, 'runtime', 'sherpa-onnx');
      if (_isUsableSherpaOnnxDir(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static Iterable<String> _bundleBaseDirs() sync* {
    final executableCandidates = <String>{
      Platform.resolvedExecutable,
      Platform.executable,
    };

    for (final executablePath in executableCandidates) {
      if (executablePath.isEmpty) continue;

      final executableDir = p.dirname(executablePath);
      yield p.normalize(p.join(executableDir, '..', 'Resources'));
      yield p.normalize(p.join(executableDir, '..', '..', '..'));
    }
  }

  static bool _isUsableFfmpegDir(String dir) {
    final ffmpeg = File(p.join(dir, _binaryName('ffmpeg')));
    final ffprobe = File(p.join(dir, _binaryName('ffprobe')));
    return ffmpeg.existsSync() && ffprobe.existsSync();
  }

  static bool _isUsableSherpaOnnxDir(String dir) {
    return File(
      p.join(dir, 'bin', _binaryName('sherpa-onnx-offline')),
    ).existsSync();
  }

  static String _binaryName(String name) =>
      Platform.isWindows ? '$name.exe' : name;
}
