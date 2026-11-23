import 'dart:io';
import 'dart:math' as math;

import '../models/media_file.dart';
import 'ffmpeg_service.dart';

enum AudioOffsetAssistStatus {
  skipped('未启用'),
  supported('支持字幕偏移'),
  unsupported('不支持字幕偏移'),
  inconclusive('无法判断');

  final String label;
  const AudioOffsetAssistStatus(this.label);
}

class AudioOffsetAssistResult {
  final AudioOffsetAssistStatus status;
  final int? bestOffsetMs;
  final double score;
  final String note;

  const AudioOffsetAssistResult({
    required this.status,
    this.bestOffsetMs,
    this.score = 0,
    this.note = '',
  });

  static const skipped = AudioOffsetAssistResult(
    status: AudioOffsetAssistStatus.skipped,
    note: 'FFmpeg 不可用或素材缺少音频，已跳过音频辅助',
  );
}

class AudioOffsetAssistService {
  AudioOffsetAssistService._();

  static const int _sampleRate = 8000;
  static const int _frameMs = 100;
  static const int _searchRadiusMs = 5000;
  static const int _windowMs = 90000;
  static const int _minComparableFrames = 50;
  static const double _supportScore = 0.34;
  static const int _supportToleranceMs = 900;
  static const int _conflictToleranceMs = 1800;

  static Future<AudioOffsetAssistResult> confirmOffset({
    required MediaFile reference,
    required MediaFile target,
    required int expectedOffsetMs,
  }) async {
    if (!FfmpegService.isConfigured) {
      return AudioOffsetAssistResult.skipped;
    }
    if (!reference.hasEmbeddedAudio || !target.hasEmbeddedAudio) {
      return const AudioOffsetAssistResult(
        status: AudioOffsetAssistStatus.skipped,
        note: '素材没有可用内嵌音频，已跳过音频辅助',
      );
    }
    if (!File(reference.filePath).existsSync() ||
        !File(target.filePath).existsSync()) {
      return const AudioOffsetAssistResult(
        status: AudioOffsetAssistStatus.skipped,
        note: '素材文件不存在，已跳过音频辅助',
      );
    }

    final referenceDuration = reference.durationMs ?? 0;
    final targetDuration = target.durationMs ?? 0;
    if (referenceDuration <= 0 || targetDuration <= 0) {
      return const AudioOffsetAssistResult(
        status: AudioOffsetAssistStatus.inconclusive,
        note: '素材时长未知，无法进行音频辅助确认',
      );
    }

    final referenceOverlapStart = math.max(expectedOffsetMs, 0);
    final targetOverlapStart = math.max(-expectedOffsetMs, 0);
    final referenceStart = math.max(0, referenceOverlapStart - _searchRadiusMs);
    final targetStart = math.max(0, targetOverlapStart - _searchRadiusMs);
    final extractDuration = [
      _windowMs + _searchRadiusMs * 2,
      referenceDuration - referenceStart,
      targetDuration - targetStart,
    ].reduce(math.min);

    if (extractDuration < _minComparableFrames * _frameMs) {
      return const AudioOffsetAssistResult(
        status: AudioOffsetAssistStatus.inconclusive,
        note: '重叠音频过短，无法进行音频辅助确认',
      );
    }

    try {
      final referenceSamples = await _extractPcmSegment(
        reference.filePath,
        startMs: referenceStart,
        durationMs: extractDuration,
      );
      final targetSamples = await _extractPcmSegment(
        target.filePath,
        startMs: targetStart,
        durationMs: extractDuration,
      );
      final referenceFeatures = _buildFeatures(referenceSamples);
      final targetFeatures = _buildFeatures(targetSamples);
      if (referenceFeatures.length < _minComparableFrames ||
          targetFeatures.length < _minComparableFrames) {
        return const AudioOffsetAssistResult(
          status: AudioOffsetAssistStatus.inconclusive,
          note: '可比较音频特征过少',
        );
      }

      final localExpectedOffsetMs =
          expectedOffsetMs + targetStart - referenceStart;
      final best = _findBestOffset(
        referenceFeatures,
        targetFeatures,
        expectedOffsetMs: localExpectedOffsetMs,
      );
      if (best == null || best.score < _supportScore) {
        return AudioOffsetAssistResult(
          status: AudioOffsetAssistStatus.inconclusive,
          bestOffsetMs: best?.offsetMs,
          score: best?.score ?? 0,
          note: '音频相关峰不明显',
        );
      }

      final absoluteBestOffset = best.offsetMs - targetStart + referenceStart;
      final diff = (absoluteBestOffset - expectedOffsetMs).abs();
      if (diff <= _supportToleranceMs) {
        return AudioOffsetAssistResult(
          status: AudioOffsetAssistStatus.supported,
          bestOffsetMs: absoluteBestOffset,
          score: best.score,
          note: '音频相关峰支持字幕偏移',
        );
      }
      if (diff >= _conflictToleranceMs) {
        return AudioOffsetAssistResult(
          status: AudioOffsetAssistStatus.unsupported,
          bestOffsetMs: absoluteBestOffset,
          score: best.score,
          note: '音频相关峰与字幕偏移不一致',
        );
      }

      return AudioOffsetAssistResult(
        status: AudioOffsetAssistStatus.inconclusive,
        bestOffsetMs: absoluteBestOffset,
        score: best.score,
        note: '音频偏移接近但不足以确认',
      );
    } catch (error) {
      return AudioOffsetAssistResult(
        status: AudioOffsetAssistStatus.inconclusive,
        note: '音频辅助执行失败: $error',
      );
    }
  }

  static Future<List<int>> _extractPcmSegment(
    String filePath, {
    required int startMs,
    required int durationMs,
  }) async {
    final result = await Process.run(
      FfmpegService.ffmpegPath,
      [
        '-ss',
        _formatTime(startMs),
        '-t',
        _formatTime(durationMs),
        '-i',
        filePath,
        '-vn',
        '-ar',
        '$_sampleRate',
        '-ac',
        '1',
        '-f',
        's16le',
        '-',
      ],
      environment: FfmpegService.environmentFor(FfmpegService.ffmpegPath),
      stdoutEncoding: null,
      stderrEncoding: const SystemEncoding(),
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr);
    }
    final bytes = (result.stdout as List<int>?) ?? const <int>[];
    final samples = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      var sample = bytes[index] | (bytes[index + 1] << 8);
      if (sample >= 0x8000) {
        sample -= 0x10000;
      }
      samples.add(sample);
    }
    return samples;
  }

  static List<double> _buildFeatures(List<int> samples) {
    final frameSize = (_sampleRate * _frameMs / 1000).round();
    if (samples.length < frameSize) return const [];

    final energy = <double>[];
    final zcr = <double>[];
    for (
      var start = 0;
      start + frameSize <= samples.length;
      start += frameSize
    ) {
      var sumSquares = 0.0;
      var zeroCrossings = 0;
      var previous = samples[start];
      for (var index = start; index < start + frameSize; index++) {
        final sample = samples[index] / 32768.0;
        sumSquares += sample * sample;
        final current = samples[index];
        if ((previous < 0 && current >= 0) || (previous >= 0 && current < 0)) {
          zeroCrossings++;
        }
        previous = current;
      }
      energy.add(math.log(math.sqrt(sumSquares / frameSize) + 1e-9));
      zcr.add(zeroCrossings / frameSize);
    }

    final normalizedEnergy = _zNormalize(energy);
    final normalizedZcr = _zNormalize(zcr);
    return List.generate(normalizedEnergy.length, (index) {
      final previousEnergy = index == 0 ? 0.0 : normalizedEnergy[index - 1];
      final flux = (normalizedEnergy[index] - previousEnergy).abs();
      return normalizedEnergy[index] + normalizedZcr[index] * 0.2 + flux * 0.15;
    });
  }

  static List<double> _zNormalize(List<double> values) {
    if (values.isEmpty) return const [];
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) {
              final diff = value - mean;
              return diff * diff;
            })
            .reduce((a, b) => a + b) /
        values.length;
    final std = math.sqrt(variance);
    if (std <= 1e-9) {
      return List<double>.filled(values.length, 0);
    }
    return values.map((value) => (value - mean) / std).toList(growable: false);
  }

  static _OffsetScore? _findBestOffset(
    List<double> reference,
    List<double> target, {
    required int expectedOffsetMs,
  }) {
    final expectedFrame = (expectedOffsetMs / _frameMs).round();
    final radiusFrames = (_searchRadiusMs / _frameMs).round();
    _OffsetScore? best;

    for (
      var offsetFrame = expectedFrame - radiusFrames;
      offsetFrame <= expectedFrame + radiusFrames;
      offsetFrame++
    ) {
      final score = _correlationScore(reference, target, offsetFrame);
      if (score == null) continue;
      if (best == null || score > best.score) {
        best = _OffsetScore(offsetMs: offsetFrame * _frameMs, score: score);
      }
    }
    return best;
  }

  static double? _correlationScore(
    List<double> reference,
    List<double> target,
    int offsetFrame,
  ) {
    final targetStart = math.max(0, -offsetFrame);
    final targetEnd = math.min(target.length, reference.length - offsetFrame);
    final count = targetEnd - targetStart;
    if (count < _minComparableFrames) return null;

    var sum = 0.0;
    var refNorm = 0.0;
    var targetNorm = 0.0;
    for (
      var targetIndex = targetStart;
      targetIndex < targetEnd;
      targetIndex++
    ) {
      final referenceIndex = targetIndex + offsetFrame;
      final refValue = reference[referenceIndex];
      final targetValue = target[targetIndex];
      sum += refValue * targetValue;
      refNorm += refValue * refValue;
      targetNorm += targetValue * targetValue;
    }
    if (refNorm <= 1e-9 || targetNorm <= 1e-9) return null;
    return sum / math.sqrt(refNorm * targetNorm);
  }

  static String _formatTime(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }
}

class _OffsetScore {
  final int offsetMs;
  final double score;

  const _OffsetScore({required this.offsetMs, required this.score});
}
