import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:asr_tools/models/timeline_data.dart';
import 'package:asr_tools/services/export_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export-service-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'sanitize export base name trims and replaces Windows invalid chars',
    () {
      final sanitized = ExportService.sanitizeExportBaseName(
        '  工程:测试?版本*1  ',
        fallbackName: '备用名称',
      );

      expect(sanitized, '工程_测试_版本_1');
    },
  );

  test('sanitize export base name falls back when input becomes empty', () {
    final sanitized = ExportService.sanitizeExportBaseName(
      '   ',
      fallbackName: '默认工程名',
    );

    expect(sanitized, '默认工程名');
  });

  test(
    'sanitize export base name falls back to ASR Timeline as last resort',
    () {
      final sanitized = ExportService.sanitizeExportBaseName(
        '///',
        fallbackName: ':::',
      );

      expect(sanitized, 'ASR Timeline');
    },
  );

  test(
    'xmeml keeps embedded audio and external audio on separate tracks',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline.xml');
      final timeline = _buildTimelineData(
        videoHasEmbeddedAudio: true,
        audioFileId: 'audio-1',
        audioFileName: 'A0001.wav',
        audioFilePath: r'G:\audio\A0001.wav',
        audioOriginalDurationMs: 6000,
        audioTrimStartMs: 300,
        audioTrimEndMs: 4300,
      );

      await ExportService.exportXmeml([timeline], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final sequence = document.findAllElements('sequence').first;
      final timelineAudio = sequence
          .findElements('media')
          .first
          .findElements('audio')
          .first;
      final videoClip = sequence
          .findAllElements('video')
          .first
          .findElements('track')
          .first
          .findElements('clipitem')
          .first;
      final videoFileId = videoClip
          .findElements('file')
          .first
          .getAttribute('id');
      final audioTracks = timelineAudio.findElements('track').toList();

      expect(audioTracks.length, 2);

      final embeddedClip = audioTracks[0].findElements('clipitem').first;
      expect(
        embeddedClip.findElements('file').first.getAttribute('id'),
        videoFileId,
      );
      expect(
        embeddedClip
            .findElements('sourcetrack')
            .first
            .findElements('mediatype')
            .first
            .innerText,
        'audio',
      );

      final externalClip = audioTracks[1].findElements('clipitem').first;
      expect(
        externalClip
            .findElements('file')
            .first
            .findElements('pathurl')
            .first
            .innerText,
        contains('A0001.wav'),
      );
    },
  );

  test(
    'xmeml skips embedded audio track when video has no embedded audio',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline-no-embedded.xml');
      final timeline = _buildTimelineData(
        videoHasEmbeddedAudio: false,
        audioFileId: 'audio-1',
        audioFileName: 'A0001.wav',
        audioFilePath: r'G:\audio\A0001.wav',
        audioOriginalDurationMs: 6000,
        audioTrimStartMs: 300,
        audioTrimEndMs: 4300,
      );

      await ExportService.exportXmeml([timeline], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final sequence = document.findAllElements('sequence').first;
      final audioTracks = sequence
          .findElements('media')
          .first
          .findElements('audio')
          .first
          .findElements('track')
          .toList();

      expect(audioTracks.length, 1);
      expect(
        audioTracks.first
            .findElements('clipitem')
            .first
            .findElements('name')
            .first
            .innerText,
        'A0001.wav',
      );
    },
  );

  test(
    'xmeml skips external audio track when match has no external audio',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline-no-external.xml');
      final timeline = _buildTimelineData(videoHasEmbeddedAudio: true);

      await ExportService.exportXmeml([timeline], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final sequence = document.findAllElements('sequence').first;
      final timelineAudio = sequence
          .findElements('media')
          .first
          .findElements('audio')
          .first;
      final videoClip = sequence
          .findAllElements('video')
          .first
          .findElements('track')
          .first
          .findElements('clipitem')
          .first;
      final videoFileId = videoClip
          .findElements('file')
          .first
          .getAttribute('id');
      final audioTracks = timelineAudio.findElements('track').toList();

      expect(audioTracks.length, 1);
      expect(
        audioTracks.first
            .findElements('clipitem')
            .first
            .findElements('file')
            .first
            .getAttribute('id'),
        videoFileId,
      );
    },
  );

  test(
    'fcpxml exports embedded and external audio as separate sequence audio lanes',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline.fcpxml');
      final timeline = _buildTimelineData(
        videoHasEmbeddedAudio: true,
        audioFileId: 'audio-1',
        audioFileName: 'A0001.wav',
        audioFilePath: r'G:\audio\A0001.wav',
        audioOriginalDurationMs: 6000,
        audioTrimStartMs: 300,
        audioTrimEndMs: 4300,
      );

      await ExportService.exportFcpxml([timeline], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final sequence = document.findAllElements('sequence').first;
      final audioElements = sequence.findElements('audio').toList();

      expect(audioElements.length, 2);
      expect(audioElements[0].getAttribute('ref'), 'a_video-1');
      expect(audioElements[0].getAttribute('lane'), '-1');
      expect(audioElements[1].getAttribute('ref'), 'a_audio-1');
      expect(audioElements[1].getAttribute('lane'), '-2');
    },
  );

  test(
    'fcpxml skips missing embedded audio lane and keeps external lane',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline-external-only.fcpxml');
      final timeline = _buildTimelineData(
        videoHasEmbeddedAudio: false,
        audioFileId: 'audio-1',
        audioFileName: 'A0001.wav',
        audioFilePath: r'G:\audio\A0001.wav',
        audioOriginalDurationMs: 6000,
        audioTrimStartMs: 300,
        audioTrimEndMs: 4300,
      );

      await ExportService.exportFcpxml([timeline], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final audioElements = document
          .findAllElements('sequence')
          .first
          .findElements('audio')
          .toList();

      expect(audioElements.length, 1);
      expect(audioElements.first.getAttribute('ref'), 'a_audio-1');
      expect(audioElements.first.getAttribute('lane'), '-2');
    },
  );

  test(
    'xmeml exports sibling tracks onto separate external audio lanes',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline-multitrack.xml');
      final timeline =
          _buildTimelineData(
            videoHasEmbeddedAudio: false,
            audioFileId: 'audio-lr',
            audioFileName: 'ZOOM0147_LR.wav',
            audioFilePath: r'G:\audio\ZOOM0147_LR.wav',
            audioOriginalDurationMs: 6000,
            audioTrimStartMs: 300,
            audioTrimEndMs: 4300,
          ).copyWith(
            externalAudioTracks: const [
              ExternalAudioTrackData(
                mediaFileId: 'audio-lr',
                fileName: 'ZOOM0147_LR.wav',
                filePath: r'G:\audio\ZOOM0147_LR.wav',
                isPrimary: true,
                audioOriginalDurationMs: 6000,
                trimStartMs: 300,
                trimEndMs: 4300,
              ),
              ExternalAudioTrackData(
                mediaFileId: 'audio-tr1',
                fileName: 'ZOOM0147_Tr1.wav',
                filePath: r'G:\audio\ZOOM0147_Tr1.wav',
                audioOriginalDurationMs: 5800,
                trimStartMs: 300,
                trimEndMs: 4200,
                wasClamped: true,
              ),
            ],
          );

      await ExportService.exportXmeml([timeline], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final audioTracks = document
          .findAllElements('sequence')
          .first
          .findElements('media')
          .first
          .findElements('audio')
          .first
          .findElements('track')
          .toList();

      expect(audioTracks.length, 2);
      expect(
        audioTracks[0]
            .findElements('clipitem')
            .first
            .findElements('name')
            .first
            .innerText,
        'ZOOM0147_LR.wav',
      );
      expect(
        audioTracks[1]
            .findElements('clipitem')
            .first
            .findElements('name')
            .first
            .innerText,
        'ZOOM0147_Tr1.wav',
      );
    },
  );

  test('fcpxml exports sibling tracks onto separate external lanes', () async {
    final outputPath = p.join(tempDir.path, 'timeline-multitrack.fcpxml');
    final timeline =
        _buildTimelineData(
          videoHasEmbeddedAudio: false,
          audioFileId: 'audio-lr',
          audioFileName: 'ZOOM0147_LR.wav',
          audioFilePath: r'G:\audio\ZOOM0147_LR.wav',
          audioOriginalDurationMs: 6000,
          audioTrimStartMs: 300,
          audioTrimEndMs: 4300,
        ).copyWith(
          externalAudioTracks: const [
            ExternalAudioTrackData(
              mediaFileId: 'audio-lr',
              fileName: 'ZOOM0147_LR.wav',
              filePath: r'G:\audio\ZOOM0147_LR.wav',
              isPrimary: true,
              audioOriginalDurationMs: 6000,
              trimStartMs: 300,
              trimEndMs: 4300,
            ),
            ExternalAudioTrackData(
              mediaFileId: 'audio-tr1',
              fileName: 'ZOOM0147_Tr1.wav',
              filePath: r'G:\audio\ZOOM0147_Tr1.wav',
              audioOriginalDurationMs: 5800,
              trimStartMs: 300,
              trimEndMs: 4200,
            ),
          ],
        );

    await ExportService.exportFcpxml([timeline], outputPath);
    final document = XmlDocument.parse(await File(outputPath).readAsString());
    final audioElements = document
        .findAllElements('sequence')
        .first
        .findElements('audio')
        .toList();

    expect(audioElements.length, 2);
    expect(audioElements[0].getAttribute('ref'), 'a_audio-lr');
    expect(audioElements[0].getAttribute('lane'), '-2');
    expect(audioElements[1].getAttribute('ref'), 'a_audio-tr1');
    expect(audioElements[1].getAttribute('lane'), '-3');
  });

  test(
    'xmeml exports overlapping multicam videos on separate tracks',
    () async {
      final outputPath = p.join(tempDir.path, 'timeline-multicam.xml');
      final primary = _buildTimelineData(
        videoHasEmbeddedAudio: false,
        videoFileId: 'video-primary',
        videoFileName: 'C0001.mp4',
        videoFilePath: r'G:\video\C0001.mp4',
        videoEndMs: 10000,
        timelineStartMs: 0,
        timelineEndMs: 10000,
        videoTrackIndex: 0,
      );
      final angle = _buildTimelineData(
        videoHasEmbeddedAudio: false,
        videoFileId: 'video-angle',
        videoFileName: 'C0002.mp4',
        videoFilePath: r'G:\video\C0002.mp4',
        videoEndMs: 6000,
        timelineStartMs: 2000,
        timelineEndMs: 8000,
        videoTrackIndex: 1,
      );

      await ExportService.exportXmeml([primary, angle], outputPath);
      final document = XmlDocument.parse(await File(outputPath).readAsString());
      final sequence = document.findAllElements('sequence').first;
      final videoTracks = sequence
          .findElements('media')
          .first
          .findElements('video')
          .first
          .findElements('track')
          .toList();

      expect(sequence.findElements('duration').first.innerText, '240');
      expect(videoTracks.length, 2);
      expect(
        videoTracks[0]
            .findElements('clipitem')
            .first
            .findElements('start')
            .first
            .innerText,
        '0',
      );
      expect(
        videoTracks[1]
            .findElements('clipitem')
            .first
            .findElements('start')
            .first
            .innerText,
        '48',
      );
    },
  );

  test('fcpxml exports upper multicam videos as video lanes', () async {
    final outputPath = p.join(tempDir.path, 'timeline-multicam.fcpxml');
    final primary = _buildTimelineData(
      videoHasEmbeddedAudio: false,
      videoFileId: 'video-primary',
      videoFileName: 'C0001.mp4',
      videoFilePath: r'G:\video\C0001.mp4',
      videoEndMs: 10000,
      timelineStartMs: 0,
      timelineEndMs: 10000,
      videoTrackIndex: 0,
    );
    final angle = _buildTimelineData(
      videoHasEmbeddedAudio: false,
      videoFileId: 'video-angle',
      videoFileName: 'C0002.mp4',
      videoFilePath: r'G:\video\C0002.mp4',
      videoEndMs: 6000,
      timelineStartMs: 2000,
      timelineEndMs: 8000,
      videoTrackIndex: 1,
    );

    await ExportService.exportFcpxml([primary, angle], outputPath);
    final document = XmlDocument.parse(await File(outputPath).readAsString());
    final sequence = document.findAllElements('sequence').first;
    final clips = sequence.findAllElements('asset-clip').toList();

    expect(sequence.getAttribute('duration'), '24000/2400s');
    expect(clips.length, 2);
    expect(clips[0].getAttribute('offset'), '0/2400s');
    expect(clips[0].getAttribute('lane'), isNull);
    expect(clips[1].getAttribute('offset'), '4800/2400s');
    expect(clips[1].getAttribute('lane'), '1');
  });
}

TimelineData _buildTimelineData({
  required bool videoHasEmbeddedAudio,
  String videoFileId = 'video-1',
  String videoFileName = 'C0001.mp4',
  String videoFilePath = r'G:\video\C0001.mp4',
  String? audioFileId,
  String audioFileName = '',
  String audioFilePath = '',
  int videoEndMs = 4000,
  int timelineStartMs = 0,
  int timelineEndMs = 4000,
  int videoTrackIndex = 0,
  int audioOriginalDurationMs = 0,
  int audioTrimStartMs = 0,
  int audioTrimEndMs = 0,
}) {
  return TimelineData(
    syncResultId: 'sync-1',
    videoFileId: videoFileId,
    audioFileId: audioFileId,
    videoFileName: videoFileName,
    audioFileName: audioFileName,
    videoFilePath: videoFilePath,
    audioFilePath: audioFilePath,
    videoHasEmbeddedAudio: videoHasEmbeddedAudio,
    videoEndMs: videoEndMs,
    timelineStartMs: timelineStartMs,
    timelineEndMs: timelineEndMs,
    videoTrackIndex: videoTrackIndex,
    audioOriginalDurationMs: audioOriginalDurationMs,
    audioTrimStartMs: audioTrimStartMs,
    audioTrimEndMs: audioTrimEndMs,
    offsetMs: audioTrimStartMs,
    confidence: 0.92,
    status: '已通过',
    method: 'subtitleOnly',
    externalAudioTracks: audioFileId == null
        ? const []
        : [
            ExternalAudioTrackData(
              mediaFileId: audioFileId,
              fileName: audioFileName,
              filePath: audioFilePath,
              isPrimary: true,
              audioOriginalDurationMs: audioOriginalDurationMs,
              trimStartMs: audioTrimStartMs,
              trimEndMs: audioTrimEndMs,
            ),
          ],
  );
}
