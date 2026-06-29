import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/extensions.dart';
import '../models/media_file.dart';
import '../models/subtitle_clip.dart';
import '../models/timeline_data.dart';
import '../models/sync_result.dart';
import 'audio_grouping_service.dart';
import 'database_service.dart';
import 'ffmpeg_service.dart';

class TimelineTrimResult {
  final String primaryOutputPath;
  final Map<String, String> trackOutputByMediaId;

  const TimelineTrimResult({
    this.primaryOutputPath = '',
    this.trackOutputByMediaId = const {},
  });
}

class AudioAlignService {
  AudioAlignService._();

  static Future<List<TimelineData>> buildTimeline(String projectId) async {
    final syncResults = await DatabaseService.getSyncResults(projectId);
    final allAudioFiles = await DatabaseService.getMediaFiles(
      projectId,
      type: MediaType.audio,
    );
    final timelines = <TimelineData>[];

    for (final syncResult in syncResults.where((item) => !item.isRejected)) {
      final timeline = await _buildSingleTimeline(syncResult, allAudioFiles);
      if (timeline != null) {
        timelines.add(timeline);
      }
    }

    return timelines;
  }

  static Future<TimelineData?> _buildSingleTimeline(
    SyncResult syncResult,
    List<MediaFile> allAudioFiles,
  ) async {
    final videoFile = await DatabaseService.getMediaFileById(
      syncResult.videoFileId,
    );
    if (videoFile == null) return null;
    final audioFile = syncResult.audioFileId == null
        ? null
        : await DatabaseService.getMediaFileById(syncResult.audioFileId!);

    final videoSubtitles = await DatabaseService.getSubtitleClips(videoFile.id);
    final audioSubtitles = audioFile == null
        ? const <SubtitleClip>[]
        : await DatabaseService.getSubtitleClips(audioFile.id);
    final siblingTracks = audioFile == null
        ? const <MediaFile>[]
        : AudioGroupingService.siblingTracksFor(allAudioFiles, audioFile);

    final audioTrimStartMs = syncResult.audioSourceInMs ?? 0;
    final audioTrimEndMs = syncResult.audioSourceOutMs ?? 0;
    final externalAudioTracks = _buildExternalAudioTracks(
      siblingTracks,
      primaryAudioId: audioFile?.id,
      trimStartMs: audioTrimStartMs,
      trimEndMs: audioTrimEndMs,
    );

    return TimelineData(
      syncResultId: syncResult.id,
      videoFileId: syncResult.videoFileId,
      audioFileId: syncResult.audioFileId,
      videoFileName: _fileName(videoFile.filePath),
      audioFileName: audioFile == null
          ? '未匹配音频'
          : _fileName(audioFile.filePath),
      videoFilePath: videoFile.filePath,
      audioFilePath: audioFile?.filePath ?? '',
      videoHasEmbeddedAudio: videoFile.hasEmbeddedAudio,
      videoStartMs: 0,
      videoEndMs: syncResult.videoDurationMs,
      timelineStartMs: syncResult.timelineStartMs,
      timelineEndMs: syncResult.timelineEndMs,
      audioOriginalDurationMs: audioFile?.durationMs ?? 0,
      audioTrimStartMs: audioTrimStartMs,
      audioTrimEndMs: audioTrimEndMs,
      offsetMs: audioTrimStartMs,
      confidence: syncResult.confidence,
      status: syncResult.status.label,
      method: syncResult.method.name,
      markerText: _buildMarkerText(syncResult, audioFile?.filePath ?? ''),
      anchorCount: syncResult.anchorCount,
      sourceClamped: syncResult.sourceClamped,
      audioTooShort: syncResult.audioTooShort,
      reviewStatus: syncResult.reviewStatus,
      reviewedAtMs: syncResult.reviewedAtMs,
      reviewNote: syncResult.reviewNote,
      externalAudioTracks: externalAudioTracks,
      videoSubtitles: videoSubtitles,
      audioSubtitles: _mapAudioSubtitlesToTimeline(
        audioSubtitles,
        videoTimelineStartMs: syncResult.timelineStartMs,
        audioSourceInMs: syncResult.audioSourceInMs ?? 0,
      ),
    );
  }

  static List<SubtitleClip> _mapAudioSubtitlesToTimeline(
    List<SubtitleClip> clips, {
    required int videoTimelineStartMs,
    required int audioSourceInMs,
  }) {
    return clips
        .where((clip) {
          final localEnd = clip.localEndMs ?? clip.endMs;
          return localEnd >= audioSourceInMs;
        })
        .map((clip) {
          final localStart = clip.localStartMs ?? clip.startMs;
          final localEnd = clip.localEndMs ?? clip.endMs;
          final mappedStart =
              videoTimelineStartMs + (localStart - audioSourceInMs);
          final mappedEnd = videoTimelineStartMs + (localEnd - audioSourceInMs);
          return SubtitleClip(
            id: clip.id,
            subtitleFileId: clip.subtitleFileId,
            mediaFileId: clip.mediaFileId,
            sourceKind: clip.sourceKind,
            startMs: mappedStart,
            endMs: mappedEnd,
            globalStartMs: clip.globalStartMs,
            globalEndMs: clip.globalEndMs,
            localStartMs: mappedStart,
            localEndMs: mappedEnd,
            text: clip.text,
            normalizedText: clip.normalizedText,
            sortOrder: clip.sortOrder,
          );
        })
        .where((clip) => clip.endMs > clip.startMs)
        .toList();
  }

  static List<ExternalAudioTrackData> _buildExternalAudioTracks(
    List<MediaFile> siblingTracks, {
    required String? primaryAudioId,
    required int trimStartMs,
    required int trimEndMs,
  }) {
    return siblingTracks
        .map((file) {
          final durationMs = file.durationMs ?? 0;
          var nextTrimEndMs = trimEndMs;
          var wasClamped = false;
          if (durationMs > 0 && nextTrimEndMs > durationMs) {
            nextTrimEndMs = durationMs;
            wasClamped = true;
          }
          if (nextTrimEndMs < trimStartMs) {
            nextTrimEndMs = trimStartMs;
          }
          return ExternalAudioTrackData(
            mediaFileId: file.id,
            fileName: _fileName(file.filePath),
            filePath: file.filePath,
            isPrimary: file.id == primaryAudioId,
            audioOriginalDurationMs: durationMs,
            trimStartMs: trimStartMs,
            trimEndMs: nextTrimEndMs,
            wasClamped: wasClamped,
          );
        })
        .where((track) => track.durationMs > 0)
        .toList(growable: false);
  }

  static Future<List<TimelineTrimResult>> batchTrimAudio(
    List<TimelineData> timelineList,
    String outputDir, {
    required void Function(int current, int total, String fileName) onProgress,
  }) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final results = <TimelineTrimResult>[];
    final total = timelineList.fold<int>(
      0,
      (sum, timeline) => sum + timeline.externalAudioTracks.length,
    );
    var processed = 0;

    for (final timeline in timelineList) {
      if (timeline.externalAudioTracks.isEmpty) {
        results.add(const TimelineTrimResult());
        continue;
      }

      final outputByTrack = <String, String>{};
      for (final track in timeline.externalAudioTracks) {
        processed += 1;
        onProgress(processed, total, track.fileName);
        final outputFileName =
            '${_removeExtension(timeline.videoFileName)}_${_removeExtension(track.fileName)}_aligned.wav';
        final outputPath = p.join(outputDir, outputFileName);

        try {
          await FfmpegService.trimAndConvert(
            inputPath: track.filePath,
            outputPath: outputPath,
            startMs: track.trimStartMs,
            endMs: track.trimEndMs,
          );
          outputByTrack[track.mediaFileId] = outputPath;
        } catch (_) {}
      }

      ExternalAudioTrackData? primaryTrack;
      for (final track in timeline.externalAudioTracks) {
        if (track.isPrimary) {
          primaryTrack = track;
          break;
        }
      }
      final primaryOutputPath = primaryTrack == null
          ? ''
          : (outputByTrack[primaryTrack.mediaFileId] ?? '');
      results.add(
        TimelineTrimResult(
          primaryOutputPath: primaryOutputPath,
          trackOutputByMediaId: outputByTrack,
        ),
      );
    }

    return results;
  }

  static String _buildMarkerText(SyncResult syncResult, String audioPath) {
    final fileName = audioPath.isEmpty ? '无音频' : _fileName(audioPath);
    final sourceIn = syncResult.audioSourceInMs == null
        ? '--'
        : _formatTime(syncResult.audioSourceInMs!);
    final sourceOut = syncResult.audioSourceOutMs == null
        ? '--'
        : _formatTime(syncResult.audioSourceOutMs!);
    return '${syncResult.status.label} ${(syncResult.confidence * 100).toStringAsFixed(0)}% | '
        '$fileName | $sourceIn - $sourceOut | anchors=${syncResult.anchorCount}';
  }

  static String _fileName(String path) => path.fileName;

  static String _removeExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) return fileName.substring(0, dotIndex);
    return fileName;
  }

  static String _formatTime(int ms) {
    final h = (ms ~/ 3600000).toString().padLeft(2, '0');
    final m = ((ms % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
