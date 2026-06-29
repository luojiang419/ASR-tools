import '../models/media_file.dart';

class AudioGroupBundle {
  final String groupKey;
  final String groupLabel;
  final List<MediaFile> files;
  final MediaFile primaryFile;

  const AudioGroupBundle({
    required this.groupKey,
    required this.groupLabel,
    required this.files,
    required this.primaryFile,
  });

  int get trackCount => files.length;
}

class AudioGroupingService {
  AudioGroupingService._();

  static final RegExp _zoomSuffixPattern = RegExp(
    r'^(.*)_(lr|tr(\d+))$',
    caseSensitive: false,
  );

  static List<MediaFile> applyImportGrouping(List<MediaFile> audioFiles) {
    if (audioFiles.isEmpty) {
      return const [];
    }

    final groupedEntries = <String, List<_GroupingEntry>>{};
    for (final file in audioFiles.where(
      (file) => file.type == MediaType.audio,
    )) {
      final parsed = _parseAudioFile(file);
      groupedEntries
          .putIfAbsent(parsed.groupKey, () => <_GroupingEntry>[])
          .add(_GroupingEntry(file: file, parsed: parsed));
    }

    final updated = <MediaFile>[];
    for (final entries in groupedEntries.values) {
      entries.sort(_compareGroupingEntry);
      final primary = entries.reduce(
        (best, next) => _comparePrimaryCandidate(next, best) < 0 ? next : best,
      );
      for (final entry in entries) {
        updated.add(
          entry.file.copyWith(
            audioGroupKey: entry.parsed.groupKey,
            audioGroupLabel: entry.parsed.groupLabel,
            audioTrackKind: entry.parsed.trackKind,
            audioTrackIndex: entry.parsed.trackIndex,
            audioIsPrimary: entry.file.id == primary.file.id,
          ),
        );
      }
    }

    updated.sort((a, b) {
      final sortCompare = a.sortIndex.compareTo(b.sortIndex);
      if (sortCompare != 0) return sortCompare;
      return a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase());
    });
    return updated;
  }

  static List<AudioGroupBundle> groupAudioFiles(List<MediaFile> audioFiles) {
    if (audioFiles.isEmpty) {
      return const [];
    }

    final normalized = applyImportGrouping(audioFiles);
    final byKey = <String, List<MediaFile>>{};
    for (final file in normalized) {
      final key = file.audioGroupKey ?? file.filePath;
      byKey.putIfAbsent(key, () => <MediaFile>[]).add(file);
    }

    final groups = byKey.entries.map((entry) {
      final files = [...entry.value]..sort(_compareMediaFile);
      final primary = files.firstWhere(
        (file) => file.audioIsPrimary,
        orElse: () => files.first,
      );
      return AudioGroupBundle(
        groupKey: entry.key,
        groupLabel: primary.audioGroupLabel ?? baseGroupLabel(primary),
        files: files,
        primaryFile: primary,
      );
    }).toList();

    groups.sort((a, b) {
      final sortCompare = a.primaryFile.sortIndex.compareTo(
        b.primaryFile.sortIndex,
      );
      if (sortCompare != 0) return sortCompare;
      return a.groupLabel.toLowerCase().compareTo(b.groupLabel.toLowerCase());
    });
    return groups;
  }

  static List<MediaFile> selectRepresentativeTracks(
    List<MediaFile> audioFiles, {
    Map<String, int> subtitleCountByMediaId = const {},
  }) {
    return groupAudioFiles(audioFiles)
        .map(
          (group) => selectRepresentativeTrack(
            group.files,
            subtitleCountByMediaId: subtitleCountByMediaId,
          ),
        )
        .toList(growable: false);
  }

  static MediaFile selectRepresentativeTrack(
    List<MediaFile> audioFiles, {
    Map<String, int> subtitleCountByMediaId = const {},
  }) {
    if (audioFiles.isEmpty) {
      throw StateError('音频组不能为空');
    }

    final files = applyImportGrouping(audioFiles);
    final lrWithSubtitle =
        files
            .where(
              (file) =>
                  file.audioTrackKind == AudioTrackKind.lr &&
                  (subtitleCountByMediaId[file.id] ?? 0) > 0,
            )
            .toList()
          ..sort(
            (a, b) => _compareRepresentativeScore(
              a,
              b,
              subtitleCountByMediaId: subtitleCountByMediaId,
            ),
          );
    if (lrWithSubtitle.isNotEmpty) {
      return lrWithSubtitle.first;
    }

    final sorted = [...files]
      ..sort(
        (a, b) => _compareRepresentativeScore(
          a,
          b,
          subtitleCountByMediaId: subtitleCountByMediaId,
        ),
      );
    return sorted.first;
  }

  static List<MediaFile> siblingTracksFor(
    List<MediaFile> audioFiles,
    MediaFile target,
  ) {
    final normalizedTarget = applyImportGrouping([target]);
    final targetKey = normalizedTarget.isEmpty
        ? target.audioGroupKey
        : normalizedTarget.first.audioGroupKey;
    if (targetKey == null || targetKey.trim().isEmpty) {
      return [target];
    }
    final files =
        applyImportGrouping(
            audioFiles,
          ).where((file) => file.audioGroupKey == targetKey).toList()
          ..sort(_compareMediaFile);
    return files.isEmpty ? [target] : files;
  }

  static String buildGroupSummary(
    MediaFile representative,
    List<MediaFile> siblings,
  ) {
    final label =
        representative.audioGroupLabel ?? baseGroupLabel(representative);
    final trackLabel = trackDisplayLabel(representative);
    if (siblings.length <= 1) {
      return '$label ($trackLabel)';
    }
    return '$label (主轨 $trackLabel, 共 ${siblings.length} 轨)';
  }

  static String trackDisplayLabel(MediaFile file) {
    switch (file.audioTrackKind) {
      case AudioTrackKind.lr:
        return 'LR';
      case AudioTrackKind.track:
        return file.audioTrackIndex == null
            ? 'Tr?'
            : 'Tr${file.audioTrackIndex}';
      case AudioTrackKind.single:
        return '单轨';
    }
  }

  static String baseGroupLabel(MediaFile file) {
    return file.audioGroupLabel ?? _baseNameWithoutExtension(file.filePath);
  }

  static _ParsedAudioGroup _parseAudioFile(MediaFile file) {
    final directoryKey = _directoryName(file.filePath).toLowerCase();
    final baseName = _baseNameWithoutExtension(file.filePath);
    final match = _zoomSuffixPattern.firstMatch(baseName);
    if (match == null) {
      return _ParsedAudioGroup(
        groupKey: '$directoryKey|${baseName.toLowerCase()}',
        groupLabel: baseName,
        trackKind: AudioTrackKind.single,
        trackIndex: null,
      );
    }

    final label = match.group(1)?.trim() ?? baseName;
    final suffix = (match.group(2) ?? '').toLowerCase();
    if (suffix == 'lr') {
      return _ParsedAudioGroup(
        groupKey: '$directoryKey|${label.toLowerCase()}',
        groupLabel: label,
        trackKind: AudioTrackKind.lr,
        trackIndex: null,
      );
    }

    return _ParsedAudioGroup(
      groupKey: '$directoryKey|${label.toLowerCase()}',
      groupLabel: label,
      trackKind: AudioTrackKind.track,
      trackIndex: int.tryParse(match.group(3) ?? ''),
    );
  }

  static int _compareGroupingEntry(_GroupingEntry a, _GroupingEntry b) {
    final sortCompare = a.file.sortIndex.compareTo(b.file.sortIndex);
    if (sortCompare != 0) return sortCompare;
    return _comparePrimaryCandidate(a, b);
  }

  static int _comparePrimaryCandidate(_GroupingEntry a, _GroupingEntry b) {
    final rankCompare = _trackPriority(
      a.parsed,
    ).compareTo(_trackPriority(b.parsed));
    if (rankCompare != 0) return rankCompare;
    final aIndex = a.parsed.trackIndex ?? 0;
    final bIndex = b.parsed.trackIndex ?? 0;
    final indexCompare = aIndex.compareTo(bIndex);
    if (indexCompare != 0) return indexCompare;
    return a.file.filePath.toLowerCase().compareTo(
      b.file.filePath.toLowerCase(),
    );
  }

  static int _compareRepresentativeScore(
    MediaFile a,
    MediaFile b, {
    Map<String, int> subtitleCountByMediaId = const {},
  }) {
    final aCount = subtitleCountByMediaId[a.id] ?? 0;
    final bCount = subtitleCountByMediaId[b.id] ?? 0;
    final countCompare = bCount.compareTo(aCount);
    if (countCompare != 0) return countCompare;

    final aDuration = a.durationMs ?? 0;
    final bDuration = b.durationMs ?? 0;
    final durationCompare = bDuration.compareTo(aDuration);
    if (durationCompare != 0) return durationCompare;

    final priorityCompare = _trackPriorityFromFile(
      a,
    ).compareTo(_trackPriorityFromFile(b));
    if (priorityCompare != 0) return priorityCompare;

    final aIndex = a.audioTrackIndex ?? 0;
    final bIndex = b.audioTrackIndex ?? 0;
    final indexCompare = aIndex.compareTo(bIndex);
    if (indexCompare != 0) return indexCompare;

    return a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase());
  }

  static int _compareMediaFile(MediaFile a, MediaFile b) {
    if (a.audioIsPrimary != b.audioIsPrimary) {
      return a.audioIsPrimary ? -1 : 1;
    }
    final priorityCompare = _trackPriorityFromFile(
      a,
    ).compareTo(_trackPriorityFromFile(b));
    if (priorityCompare != 0) return priorityCompare;
    final aIndex = a.audioTrackIndex ?? 0;
    final bIndex = b.audioTrackIndex ?? 0;
    final indexCompare = aIndex.compareTo(bIndex);
    if (indexCompare != 0) return indexCompare;
    final sortCompare = a.sortIndex.compareTo(b.sortIndex);
    if (sortCompare != 0) return sortCompare;
    return a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase());
  }

  static int _trackPriority(_ParsedAudioGroup parsed) {
    switch (parsed.trackKind) {
      case AudioTrackKind.lr:
        return 0;
      case AudioTrackKind.track:
        return 1;
      case AudioTrackKind.single:
        return 2;
    }
  }

  static int _trackPriorityFromFile(MediaFile file) {
    switch (file.audioTrackKind) {
      case AudioTrackKind.lr:
        return 0;
      case AudioTrackKind.track:
        return 1;
      case AudioTrackKind.single:
        return 2;
    }
  }

  static String _baseNameWithoutExtension(String filePath) {
    final baseName = filePath.split(RegExp(r'[/\\]')).last;
    final dotIndex = baseName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return baseName;
    }
    return baseName.substring(0, dotIndex);
  }

  static String _directoryName(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '';
    }
    return normalized.substring(0, slashIndex);
  }
}

class _ParsedAudioGroup {
  final String groupKey;
  final String groupLabel;
  final AudioTrackKind trackKind;
  final int? trackIndex;

  const _ParsedAudioGroup({
    required this.groupKey,
    required this.groupLabel,
    required this.trackKind,
    required this.trackIndex,
  });
}

class _GroupingEntry {
  final MediaFile file;
  final _ParsedAudioGroup parsed;

  const _GroupingEntry({required this.file, required this.parsed});
}
