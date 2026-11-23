import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/media_file.dart';
import '../models/source_layout_item.dart';
import '../models/subtitle_clip.dart';
import 'audio_offset_assist_service.dart';
import 'database_service.dart';

enum MulticamRole {
  single('普通素材'),
  primary('基准机位'),
  angle('上方机位');

  final String label;
  const MulticamRole(this.label);
}

class MulticamLayoutInfo {
  final String mediaFileId;
  final String groupId;
  final MulticamRole role;
  final int videoTrackIndex;
  final int relativeStartMs;
  final double confidence;
  final int anchorCount;
  final AudioOffsetAssistStatus audioAssistStatus;
  final String note;

  const MulticamLayoutInfo({
    required this.mediaFileId,
    required this.groupId,
    required this.role,
    required this.videoTrackIndex,
    required this.relativeStartMs,
    this.confidence = 0,
    this.anchorCount = 0,
    this.audioAssistStatus = AudioOffsetAssistStatus.skipped,
    this.note = '',
  });

  bool get isMulticam => role != MulticamRole.single;
}

class MulticamLayoutResult {
  final List<MediaFile> updatedVideos;
  final Map<String, MulticamLayoutInfo> infoByMediaId;

  const MulticamLayoutResult({
    required this.updatedVideos,
    required this.infoByMediaId,
  });
}

class VideoMulticamLayoutService {
  VideoMulticamLayoutService._();

  static const _uuid = Uuid();
  static const int _minAnchorCount = 3;
  static const double _acceptConfidence = 0.78;
  static const double _audioAssistConfidence = 0.62;
  static const double _minStabilityScore = 0.5;
  static const int _offsetClusterToleranceMs = 5000;
  static const double _clipSimilarityThreshold = 0.82;
  static const double _maxLengthDiffRatio = 0.45;

  static Future<MulticamLayoutResult> refreshVideoLayouts(
    String projectId,
    List<MediaFile> videos, {
    bool allowAudioAssist = true,
  }) async {
    final result = await buildLayout(
      projectId,
      videos,
      allowAudioAssist: allowAudioAssist,
    );
    await DatabaseService.updateMediaFiles(result.updatedVideos);
    await DatabaseService.replaceSourceLayouts(
      projectId,
      MediaType.video,
      _toSourceLayouts(projectId, result.updatedVideos),
    );
    return result;
  }

  static Future<MulticamLayoutResult> buildLayout(
    String projectId,
    List<MediaFile> videos, {
    bool allowAudioAssist = false,
  }) async {
    final sorted = [...videos]..sort(_compareByImportOrder);
    if (sorted.isEmpty) {
      return const MulticamLayoutResult(updatedVideos: [], infoByMediaId: {});
    }

    final clipsByMediaId = <String, List<_ComparableClip>>{};
    for (final video in sorted) {
      final clips = await DatabaseService.getSubtitleClips(video.id);
      clipsByMediaId[video.id] = _toComparableClips(clips);
    }

    final candidates = <_PairCandidate>[];
    for (var leftIndex = 0; leftIndex < sorted.length; leftIndex++) {
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < sorted.length;
        rightIndex++
      ) {
        final candidate = _comparePair(
          sorted[leftIndex],
          sorted[rightIndex],
          clipsByMediaId[sorted[leftIndex].id] ?? const [],
          clipsByMediaId[sorted[rightIndex].id] ?? const [],
        );
        if (candidate == null) continue;

        var adjusted = candidate;
        if (allowAudioAssist && candidate.shouldUseAudioAssist) {
          final audio = await AudioOffsetAssistService.confirmOffset(
            reference: sorted[leftIndex],
            target: sorted[rightIndex],
            expectedOffsetMs: candidate.rightStartRelativeToLeftMs,
          );
          adjusted = candidate.withAudioAssist(audio);
        }
        if (adjusted.isAccepted) {
          candidates.add(adjusted);
        }
      }
    }

    final groups = _buildGroups(sorted, candidates);
    return _applyGroups(projectId, sorted, groups);
  }

  static MulticamLayoutResult inferFromExistingLayouts(List<MediaFile> videos) {
    final sorted = [...videos]
      ..sort((a, b) {
        final startCompare = a.layoutStartMs.compareTo(b.layoutStartMs);
        if (startCompare != 0) return startCompare;
        return _compareByImportOrder(a, b);
      });
    if (sorted.isEmpty) {
      return const MulticamLayoutResult(updatedVideos: [], infoByMediaId: {});
    }

    final groups = <List<MediaFile>>[];
    var current = <MediaFile>[];
    var currentEnd = -1;
    for (final video in sorted) {
      if (current.isEmpty || video.layoutStartMs < currentEnd) {
        current.add(video);
        currentEnd = math.max(currentEnd, video.layoutEndMs);
      } else {
        groups.add(current);
        current = [video];
        currentEnd = video.layoutEndMs;
      }
    }
    if (current.isNotEmpty) {
      groups.add(current);
    }

    final infoByMediaId = <String, MulticamLayoutInfo>{};
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      if (group.length <= 1) {
        final video = group.first;
        infoByMediaId[video.id] = MulticamLayoutInfo(
          mediaFileId: video.id,
          groupId: 'single-${video.id}',
          role: MulticamRole.single,
          videoTrackIndex: 0,
          relativeStartMs: 0,
        );
        continue;
      }

      final ordered = [...group]..sort(_compareGroupTrackOrder);
      final primary = ordered.first;
      for (var index = 0; index < ordered.length; index++) {
        final video = ordered[index];
        infoByMediaId[video.id] = MulticamLayoutInfo(
          mediaFileId: video.id,
          groupId: 'multicam-existing-$groupIndex',
          role: video.id == primary.id
              ? MulticamRole.primary
              : MulticamRole.angle,
          videoTrackIndex: index,
          relativeStartMs: video.layoutStartMs - primary.layoutStartMs,
          note: video.id == primary.id ? '现有重叠布局中的最长机位' : '现有重叠布局中的上方机位',
        );
      }
    }

    return MulticamLayoutResult(
      updatedVideos: sorted,
      infoByMediaId: infoByMediaId,
    );
  }

  static _PairCandidate? _comparePair(
    MediaFile left,
    MediaFile right,
    List<_ComparableClip> leftClips,
    List<_ComparableClip> rightClips,
  ) {
    if (leftClips.length < 2 || rightClips.length < 2) {
      return null;
    }

    final anchors = <_TextAnchor>[];
    final usedLeftIds = <String>{};
    for (final rightClip in rightClips) {
      _ComparableClip? bestLeft;
      var bestScore = 0.0;
      for (final leftClip in leftClips) {
        if (usedLeftIds.contains(leftClip.id)) continue;
        final score = _textSimilarity(
          leftClip.normalizedText,
          rightClip.normalizedText,
        );
        if (score > bestScore) {
          bestScore = score;
          bestLeft = leftClip;
        }
      }
      if (bestLeft == null || bestScore < _clipSimilarityThreshold) {
        continue;
      }
      final lowValueMultiplier = math.min(
        bestLeft.lowValueMultiplier,
        rightClip.lowValueMultiplier,
      );
      if (lowValueMultiplier < 0.5 && bestScore < 0.96) {
        continue;
      }
      usedLeftIds.add(bestLeft.id);
      anchors.add(
        _TextAnchor(
          offsetMs: bestLeft.localStartMs - rightClip.localStartMs,
          score: bestScore * lowValueMultiplier,
        ),
      );
    }

    if (anchors.length < 2) return null;
    final cluster = _bestOffsetCluster(anchors);
    if (cluster == null) return null;

    final usableClipCount = math.max(
      1,
      math.min(leftClips.length, rightClips.length),
    );
    final coverage = (cluster.anchorCount / math.min(usableClipCount, 8)).clamp(
      0.0,
      1.0,
    );
    final confidence =
        (cluster.averageScore * 0.55 +
                cluster.stabilityScore * 0.30 +
                coverage * 0.15)
            .clamp(0.0, 1.0);

    return _PairCandidate(
      leftId: left.id,
      rightId: right.id,
      rightStartRelativeToLeftMs: cluster.medianOffsetMs,
      anchorCount: cluster.anchorCount,
      textScore: cluster.averageScore,
      stabilityScore: cluster.stabilityScore,
      confidence: confidence,
      note:
          '字幕锚点 ${cluster.anchorCount} 个，偏移 ${_formatSignedMs(cluster.medianOffsetMs)}',
    );
  }

  static _OffsetCluster? _bestOffsetCluster(List<_TextAnchor> anchors) {
    _OffsetCluster? best;
    for (final anchor in anchors) {
      final cluster = anchors
          .where(
            (item) =>
                (item.offsetMs - anchor.offsetMs).abs() <=
                _offsetClusterToleranceMs,
          )
          .toList(growable: false);
      if (cluster.length < 2) continue;
      cluster.sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
      final middle = cluster.length ~/ 2;
      final median = cluster.length.isOdd
          ? cluster[middle].offsetMs
          : ((cluster[middle - 1].offsetMs + cluster[middle].offsetMs) / 2)
                .round();
      final averageScore =
          cluster.fold<double>(0, (sum, item) => sum + item.score) /
          cluster.length;
      final averageDeviation =
          cluster.fold<double>(
            0,
            (sum, item) => sum + (item.offsetMs - median).abs(),
          ) /
          cluster.length;
      final stability = (1.0 - (averageDeviation / _offsetClusterToleranceMs))
          .clamp(0.0, 1.0);
      final offsetCluster = _OffsetCluster(
        medianOffsetMs: median,
        anchorCount: cluster.length,
        averageScore: averageScore,
        stabilityScore: stability,
      );
      if (best == null ||
          offsetCluster.anchorCount > best.anchorCount ||
          (offsetCluster.anchorCount == best.anchorCount &&
              offsetCluster.averageScore > best.averageScore)) {
        best = offsetCluster;
      }
    }
    return best;
  }

  static List<_MulticamGroup> _buildGroups(
    List<MediaFile> videos,
    List<_PairCandidate> candidates,
  ) {
    final ids = videos.map((video) => video.id).toList(growable: false);
    final parent = {for (final id in ids) id: id};

    String find(String id) {
      final current = parent[id] ?? id;
      if (current == id) return current;
      final root = find(current);
      parent[id] = root;
      return root;
    }

    void union(String left, String right) {
      final leftRoot = find(left);
      final rightRoot = find(right);
      if (leftRoot != rightRoot) {
        parent[rightRoot] = leftRoot;
      }
    }

    for (final candidate in candidates) {
      union(candidate.leftId, candidate.rightId);
    }

    final videosByRoot = <String, List<MediaFile>>{};
    for (final video in videos) {
      videosByRoot.putIfAbsent(find(video.id), () => []).add(video);
    }

    final groups = <_MulticamGroup>[];
    var groupIndex = 0;
    for (final members in videosByRoot.values) {
      if (members.length <= 1) continue;
      final primary = [...members]..sort(_compareGroupTrackOrder);
      final primaryId = primary.first.id;
      final relativeStarts = _resolveRelativeStarts(
        primaryId,
        members,
        candidates,
      );
      if (relativeStarts.length != members.length) {
        continue;
      }

      var minStart = 0;
      for (final start in relativeStarts.values) {
        minStart = math.min(minStart, start);
      }
      final shift = -minStart;
      final shiftedStarts = {
        for (final entry in relativeStarts.entries)
          entry.key: entry.value + shift,
      };

      final notes = <String>[];
      var confidenceSum = 0.0;
      var anchorCount = 0;
      var audioStatus = AudioOffsetAssistStatus.skipped;
      for (final candidate in candidates) {
        if (!members.any((video) => video.id == candidate.leftId) ||
            !members.any((video) => video.id == candidate.rightId)) {
          continue;
        }
        confidenceSum += candidate.confidence;
        anchorCount += candidate.anchorCount;
        if (candidate.audioAssistStatus == AudioOffsetAssistStatus.supported ||
            candidate.audioAssistStatus ==
                AudioOffsetAssistStatus.unsupported) {
          audioStatus = candidate.audioAssistStatus;
        }
        notes.add(candidate.note);
      }

      final averageConfidence = confidenceSum / math.max(1, notes.length);
      groups.add(
        _MulticamGroup(
          id: 'multicam-${groupIndex++}',
          memberIds: members.map((video) => video.id).toSet(),
          primaryId: primaryId,
          relativeStarts: shiftedStarts,
          confidence: averageConfidence,
          anchorCount: anchorCount,
          audioAssistStatus: audioStatus,
          note:
              '${shift > 0 ? '组整体右移 ${_formatSignedMs(shift)}；' : ''}${notes.take(3).join('；')}',
        ),
      );
    }
    return groups;
  }

  static Map<String, int> _resolveRelativeStarts(
    String primaryId,
    List<MediaFile> members,
    List<_PairCandidate> candidates,
  ) {
    final memberIds = members.map((video) => video.id).toSet();
    final adjacency = <String, List<_RelativeEdge>>{};
    for (final candidate in candidates) {
      if (!memberIds.contains(candidate.leftId) ||
          !memberIds.contains(candidate.rightId)) {
        continue;
      }
      adjacency
          .putIfAbsent(candidate.leftId, () => [])
          .add(
            _RelativeEdge(
              targetId: candidate.rightId,
              relativeStartMs: candidate.rightStartRelativeToLeftMs,
            ),
          );
      adjacency
          .putIfAbsent(candidate.rightId, () => [])
          .add(
            _RelativeEdge(
              targetId: candidate.leftId,
              relativeStartMs: -candidate.rightStartRelativeToLeftMs,
            ),
          );
    }

    final starts = <String, int>{primaryId: 0};
    final queue = <String>[primaryId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentStart = starts[current] ?? 0;
      for (final edge in adjacency[current] ?? const <_RelativeEdge>[]) {
        if (starts.containsKey(edge.targetId)) continue;
        starts[edge.targetId] = currentStart + edge.relativeStartMs;
        queue.add(edge.targetId);
      }
    }
    return starts;
  }

  static MulticamLayoutResult _applyGroups(
    String projectId,
    List<MediaFile> sorted,
    List<_MulticamGroup> groups,
  ) {
    final groupByMediaId = <String, _MulticamGroup>{};
    for (final group in groups) {
      for (final id in group.memberIds) {
        groupByMediaId[id] = group;
      }
    }

    final videosById = {for (final video in sorted) video.id: video};
    final updated = <MediaFile>[];
    final infoByMediaId = <String, MulticamLayoutInfo>{};
    final processedGroups = <String>{};
    var cursor = 0;
    var sortIndex = 0;

    for (final video in sorted) {
      final group = groupByMediaId[video.id];
      if (group == null) {
        final duration = video.durationMs ?? 0;
        final next = video.copyWith(
          sortIndex: sortIndex++,
          layoutStartMs: cursor,
          layoutEndMs: cursor + duration,
        );
        updated.add(next);
        infoByMediaId[video.id] = MulticamLayoutInfo(
          mediaFileId: video.id,
          groupId: 'single-${video.id}',
          role: MulticamRole.single,
          videoTrackIndex: 0,
          relativeStartMs: 0,
        );
        cursor += duration;
        continue;
      }
      if (processedGroups.contains(group.id)) {
        continue;
      }
      processedGroups.add(group.id);

      final members =
          group.memberIds
              .map((id) => videosById[id])
              .whereType<MediaFile>()
              .toList()
            ..sort((a, b) {
              final trackCompare = _trackIndexFor(
                group,
                a,
              ).compareTo(_trackIndexFor(group, b));
              if (trackCompare != 0) return trackCompare;
              return _compareByImportOrder(a, b);
            });

      var groupDuration = 0;
      for (final member in members) {
        final relativeStart = group.relativeStarts[member.id] ?? 0;
        groupDuration = math.max(
          groupDuration,
          relativeStart + (member.durationMs ?? 0),
        );
      }

      for (final member in members) {
        final relativeStart = group.relativeStarts[member.id] ?? 0;
        final duration = member.durationMs ?? 0;
        final trackIndex = _trackIndexFor(group, member);
        final next = member.copyWith(
          sortIndex: sortIndex++,
          layoutStartMs: cursor + relativeStart,
          layoutEndMs: cursor + relativeStart + duration,
        );
        updated.add(next);
        infoByMediaId[member.id] = MulticamLayoutInfo(
          mediaFileId: member.id,
          groupId: group.id,
          role: member.id == group.primaryId
              ? MulticamRole.primary
              : MulticamRole.angle,
          videoTrackIndex: trackIndex,
          relativeStartMs: relativeStart,
          confidence: group.confidence,
          anchorCount: group.anchorCount,
          audioAssistStatus: group.audioAssistStatus,
          note: group.note,
        );
      }

      cursor += groupDuration;
    }

    return MulticamLayoutResult(
      updatedVideos: updated,
      infoByMediaId: infoByMediaId,
    );
  }

  static int _trackIndexFor(_MulticamGroup group, MediaFile video) {
    if (video.id == group.primaryId) return 0;
    final angleIds =
        group.memberIds.where((id) => id != group.primaryId).toList()
          ..sort((left, right) {
            final startCompare = (group.relativeStarts[left] ?? 0).compareTo(
              group.relativeStarts[right] ?? 0,
            );
            if (startCompare != 0) return startCompare;
            return left.compareTo(right);
          });
    return angleIds.indexOf(video.id) + 1;
  }

  static List<SourceLayoutItem> _toSourceLayouts(
    String projectId,
    List<MediaFile> videos,
  ) {
    final now = DateTime.now();
    return videos
        .map(
          (video) => SourceLayoutItem(
            id: _uuid.v4(),
            projectId: projectId,
            mediaId: video.id,
            mediaType: MediaType.video,
            sortIndex: video.sortIndex,
            layoutStartMs: video.layoutStartMs,
            layoutEndMs: video.layoutEndMs,
            durationMs: video.durationMs ?? 0,
            createdAt: now,
          ),
        )
        .toList(growable: false);
  }

  static List<_ComparableClip> _toComparableClips(List<SubtitleClip> clips) {
    final output = <_ComparableClip>[];
    for (final clip in clips) {
      final normalized = _normalizeText(
        clip.normalizedText.trim().isNotEmpty ? clip.normalizedText : clip.text,
      );
      if (normalized.isEmpty) continue;
      final compact = normalized.replaceAll(' ', '');
      if (compact.length < 2) continue;
      output.add(
        _ComparableClip(
          id: clip.id,
          normalizedText: normalized,
          localStartMs: clip.localStartMs ?? clip.startMs,
          lowValueMultiplier: _lowValuePhraseMultiplier(normalized),
        ),
      );
    }
    return output;
  }

  static String _normalizeText(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll('零', '0')
        .replaceAll('一', '1')
        .replaceAll('二', '2')
        .replaceAll('三', '3')
        .replaceAll('四', '4')
        .replaceAll('五', '5')
        .replaceAll('六', '6')
        .replaceAll('七', '7')
        .replaceAll('八', '8')
        .replaceAll('九', '9');
    return normalized
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _lowValuePhraseMultiplier(String normalizedText) {
    final compact = normalizedText.replaceAll(' ', '');
    if (compact.length <= 2 && AppConstants.lowValuePhrases.contains(compact)) {
      return 0.25;
    }
    if (compact.length <= 4) {
      final parts = normalizedText
          .split(' ')
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.isNotEmpty &&
          parts.every((part) => AppConstants.lowValuePhrases.contains(part))) {
        return 0.4;
      }
    }
    return 1.0;
  }

  static double _textSimilarity(String left, String right) {
    if (left == right) return 1.0;
    if (left.isEmpty || right.isEmpty) return 0.0;
    final maxLength = math.max(left.length, right.length);
    if ((left.length - right.length).abs() / maxLength > _maxLengthDiffRatio) {
      return 0.0;
    }
    final leftSet = _bigramSet(left);
    final rightSet = _bigramSet(right);
    if (leftSet.isEmpty || rightSet.isEmpty) return 0.0;
    var overlap = 0;
    for (final item in leftSet) {
      if (rightSet.contains(item)) overlap++;
    }
    return (2 * overlap) / (leftSet.length + rightSet.length);
  }

  static Set<String> _bigramSet(String text) {
    final compact = text.replaceAll(' ', '');
    if (compact.length <= 1) return {compact};
    final output = <String>{};
    for (var index = 0; index < compact.length - 1; index++) {
      output.add(compact.substring(index, index + 2));
    }
    return output;
  }

  static int _compareByImportOrder(MediaFile a, MediaFile b) {
    final sortCompare = a.sortIndex.compareTo(b.sortIndex);
    if (sortCompare != 0) return sortCompare;
    return a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase());
  }

  static int _compareGroupTrackOrder(MediaFile a, MediaFile b) {
    final durationCompare = (b.durationMs ?? 0).compareTo(a.durationMs ?? 0);
    if (durationCompare != 0) return durationCompare;
    return _compareByImportOrder(a, b);
  }

  static String _formatSignedMs(int ms) {
    final sign = ms >= 0 ? '+' : '-';
    final absMs = ms.abs();
    final seconds = (absMs / 1000).toStringAsFixed(1);
    return '$sign${seconds}s';
  }
}

class _ComparableClip {
  final String id;
  final String normalizedText;
  final int localStartMs;
  final double lowValueMultiplier;

  const _ComparableClip({
    required this.id,
    required this.normalizedText,
    required this.localStartMs,
    required this.lowValueMultiplier,
  });
}

class _TextAnchor {
  final int offsetMs;
  final double score;

  const _TextAnchor({required this.offsetMs, required this.score});
}

class _OffsetCluster {
  final int medianOffsetMs;
  final int anchorCount;
  final double averageScore;
  final double stabilityScore;

  const _OffsetCluster({
    required this.medianOffsetMs,
    required this.anchorCount,
    required this.averageScore,
    required this.stabilityScore,
  });
}

class _PairCandidate {
  final String leftId;
  final String rightId;
  final int rightStartRelativeToLeftMs;
  final int anchorCount;
  final double textScore;
  final double stabilityScore;
  final double confidence;
  final AudioOffsetAssistStatus audioAssistStatus;
  final String note;

  const _PairCandidate({
    required this.leftId,
    required this.rightId,
    required this.rightStartRelativeToLeftMs,
    required this.anchorCount,
    required this.textScore,
    required this.stabilityScore,
    required this.confidence,
    this.audioAssistStatus = AudioOffsetAssistStatus.skipped,
    required this.note,
  });

  bool get shouldUseAudioAssist =>
      confidence >= VideoMulticamLayoutService._audioAssistConfidence &&
      confidence < VideoMulticamLayoutService._acceptConfidence;

  bool get isAccepted =>
      anchorCount >= VideoMulticamLayoutService._minAnchorCount &&
      confidence >= VideoMulticamLayoutService._acceptConfidence &&
      stabilityScore >= VideoMulticamLayoutService._minStabilityScore;

  _PairCandidate withAudioAssist(AudioOffsetAssistResult audio) {
    var nextConfidence = confidence;
    if (audio.status == AudioOffsetAssistStatus.supported) {
      nextConfidence = math.min(1.0, confidence + 0.08);
    } else if (audio.status == AudioOffsetAssistStatus.unsupported) {
      nextConfidence = math.max(0.0, confidence - 0.18);
    }
    return _PairCandidate(
      leftId: leftId,
      rightId: rightId,
      rightStartRelativeToLeftMs: rightStartRelativeToLeftMs,
      anchorCount: anchorCount,
      textScore: textScore,
      stabilityScore: stabilityScore,
      confidence: nextConfidence,
      audioAssistStatus: audio.status,
      note: '$note；音频辅助：${audio.status.label}',
    );
  }
}

class _RelativeEdge {
  final String targetId;
  final int relativeStartMs;

  const _RelativeEdge({required this.targetId, required this.relativeStartMs});
}

class _MulticamGroup {
  final String id;
  final Set<String> memberIds;
  final String primaryId;
  final Map<String, int> relativeStarts;
  final double confidence;
  final int anchorCount;
  final AudioOffsetAssistStatus audioAssistStatus;
  final String note;

  const _MulticamGroup({
    required this.id,
    required this.memberIds,
    required this.primaryId,
    required this.relativeStarts,
    required this.confidence,
    required this.anchorCount,
    required this.audioAssistStatus,
    required this.note,
  });
}
