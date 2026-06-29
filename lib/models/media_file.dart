/// 媒体类型枚举
enum MediaType {
  video('视频'),
  audio('音频');

  final String label;
  const MediaType(this.label);
}

enum AudioTrackKind {
  single('单轨'),
  lr('LR'),
  track('轨道');

  final String label;
  const AudioTrackKind(this.label);
}

/// 字幕识别状态
enum SubtitleStatus {
  pending('待识别'),
  processing('识别中'),
  completed('已完成'),
  failed('失败');

  final String label;
  const SubtitleStatus(this.label);
}

/// 媒体文件模型
class MediaFile {
  final String id;
  final String projectId;
  final String filePath;
  final MediaType type;
  final int? durationMs;
  final int sortIndex;
  final int layoutStartMs;
  final int layoutEndMs;
  final double? frameRate;
  final int? sampleRate;
  final int? channels;
  final int? width;
  final int? height;
  final bool hasEmbeddedAudio;
  final int? fileSize;
  final int? modifiedAtMs;
  final String? thumbnailPath;
  final String? audioGroupKey;
  final String? audioGroupLabel;
  final AudioTrackKind audioTrackKind;
  final int? audioTrackIndex;
  final bool audioIsPrimary;
  final SubtitleStatus subtitleStatus;
  final DateTime createdAt;

  const MediaFile({
    required this.id,
    required this.projectId,
    required this.filePath,
    required this.type,
    this.durationMs,
    this.sortIndex = 0,
    this.layoutStartMs = 0,
    this.layoutEndMs = 0,
    this.frameRate,
    this.sampleRate,
    this.channels,
    this.width,
    this.height,
    this.hasEmbeddedAudio = false,
    this.fileSize,
    this.modifiedAtMs,
    this.thumbnailPath,
    this.audioGroupKey,
    this.audioGroupLabel,
    this.audioTrackKind = AudioTrackKind.single,
    this.audioTrackIndex,
    this.audioIsPrimary = false,
    this.subtitleStatus = SubtitleStatus.pending,
    required this.createdAt,
  });

  MediaFile copyWith({
    int? durationMs,
    int? sortIndex,
    int? layoutStartMs,
    int? layoutEndMs,
    double? frameRate,
    int? sampleRate,
    int? channels,
    int? width,
    int? height,
    bool? hasEmbeddedAudio,
    int? fileSize,
    int? modifiedAtMs,
    String? thumbnailPath,
    String? audioGroupKey,
    String? audioGroupLabel,
    AudioTrackKind? audioTrackKind,
    int? audioTrackIndex,
    bool? audioIsPrimary,
    SubtitleStatus? subtitleStatus,
  }) {
    return MediaFile(
      id: id,
      projectId: projectId,
      filePath: filePath,
      type: type,
      durationMs: durationMs ?? this.durationMs,
      sortIndex: sortIndex ?? this.sortIndex,
      layoutStartMs: layoutStartMs ?? this.layoutStartMs,
      layoutEndMs: layoutEndMs ?? this.layoutEndMs,
      frameRate: frameRate ?? this.frameRate,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      width: width ?? this.width,
      height: height ?? this.height,
      hasEmbeddedAudio: hasEmbeddedAudio ?? this.hasEmbeddedAudio,
      fileSize: fileSize ?? this.fileSize,
      modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      audioGroupKey: audioGroupKey ?? this.audioGroupKey,
      audioGroupLabel: audioGroupLabel ?? this.audioGroupLabel,
      audioTrackKind: audioTrackKind ?? this.audioTrackKind,
      audioTrackIndex: audioTrackIndex ?? this.audioTrackIndex,
      audioIsPrimary: audioIsPrimary ?? this.audioIsPrimary,
      subtitleStatus: subtitleStatus ?? this.subtitleStatus,
      createdAt: createdAt,
    );
  }

  factory MediaFile.fromMap(Map<String, dynamic> map) {
    return MediaFile(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      filePath: map['file_path'] as String,
      type: map['type'] == 'video' ? MediaType.video : MediaType.audio,
      durationMs: map['duration_ms'] as int?,
      sortIndex: map['sort_index'] as int? ?? 0,
      layoutStartMs: map['layout_start_ms'] as int? ?? 0,
      layoutEndMs: map['layout_end_ms'] as int? ?? 0,
      frameRate: (map['frame_rate'] as num?)?.toDouble(),
      sampleRate: map['sample_rate'] as int?,
      channels: map['channels'] as int?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      hasEmbeddedAudio: (map['has_embedded_audio'] as int? ?? 0) == 1,
      fileSize: map['file_size'] as int?,
      modifiedAtMs: map['modified_at_ms'] as int?,
      thumbnailPath: map['thumbnail_path'] as String?,
      audioGroupKey: map['audio_group_key'] as String?,
      audioGroupLabel: map['audio_group_label'] as String?,
      audioTrackKind: AudioTrackKind.values.firstWhere(
        (e) => e.name == map['audio_track_kind'],
        orElse: () => AudioTrackKind.single,
      ),
      audioTrackIndex: map['audio_track_index'] as int?,
      audioIsPrimary: (map['audio_is_primary'] as int? ?? 0) == 1,
      subtitleStatus: SubtitleStatus.values.firstWhere(
        (e) => e.name == map['subtitle_status'],
        orElse: () => SubtitleStatus.pending,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'project_id': projectId,
    'file_path': filePath,
    'type': type.name,
    'duration_ms': durationMs,
    'sort_index': sortIndex,
    'layout_start_ms': layoutStartMs,
    'layout_end_ms': layoutEndMs,
    'frame_rate': frameRate,
    'sample_rate': sampleRate,
    'channels': channels,
    'width': width,
    'height': height,
    'has_embedded_audio': hasEmbeddedAudio ? 1 : 0,
    'file_size': fileSize,
    'modified_at_ms': modifiedAtMs,
    'thumbnail_path': thumbnailPath,
    'audio_group_key': audioGroupKey,
    'audio_group_label': audioGroupLabel,
    'audio_track_kind': audioTrackKind.name,
    'audio_track_index': audioTrackIndex,
    'audio_is_primary': audioIsPrimary ? 1 : 0,
    'subtitle_status': subtitleStatus.name,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  bool get hasAudioGroup =>
      type == MediaType.audio &&
      audioGroupKey != null &&
      audioGroupKey!.trim().isNotEmpty;
}
