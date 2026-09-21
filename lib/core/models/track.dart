import 'common.dart';

/// 曲目树节点：`type == 'folder'` 为目录，`type == 'audio'` 为音频文件。
///
/// 大部分作品是「目录 -> 音频」两层结构，但部分作品存在
/// 「特典 / 音频格式 / mp3」这样的多层嵌套，因此统一按树处理。
class TrackNode {
  const TrackNode({
    required this.type,
    required this.title,
    this.children = const [],
    this.hash,
    this.duration,
    this.size,
    this.mediaStreamUrl,
    this.mediaDownloadUrl,
    this.streamLowQualityUrl,
    this.workId,
    this.sourceId,
    this.workTitle,
  });

  final String type;
  final String title;
  final List<TrackNode> children;

  /// 形如 `1653004/1937686`，用于拼接带 token 的媒体地址。
  final String? hash;
  final double? duration;
  final int? size;
  final String? mediaStreamUrl;
  final String? mediaDownloadUrl;
  final String? streamLowQualityUrl;
  final int? workId;
  final String? sourceId;
  final String? workTitle;

  bool get isAudio => type == 'audio';
  bool get isFolder => type == 'folder';

  factory TrackNode.fromJson(Map<String, dynamic> json) {
    final rawWork = asMap(json['work']);
    return TrackNode(
      type: asString(json['type'], 'audio'),
      title: asString(json['title']),
      children: asMapList(json['children']).map(TrackNode.fromJson).toList(),
      hash: asStringOrNull(json['hash']),
      duration: asDoubleOrNull(json['duration']),
      size: asIntOrNull(json['size']),
      mediaStreamUrl: asStringOrNull(json['mediaStreamUrl']),
      mediaDownloadUrl: asStringOrNull(json['mediaDownloadUrl']),
      streamLowQualityUrl: asStringOrNull(json['streamLowQualityUrl']),
      workId: rawWork.isEmpty ? null : asIntOrNull(rawWork['id']),
      sourceId: rawWork.isEmpty ? null : asStringOrNull(rawWork['source_id']),
      workTitle: asStringOrNull(json['workTitle']),
    );
  }

  /// 深度优先展开出全部音频节点，并保留所在目录路径。
  List<AudioTrack> flatten({List<String> path = const []}) {
    final out = <AudioTrack>[];
    if (isAudio) {
      out.add(AudioTrack(node: this, folderPath: path));
      return out;
    }
    final next = [...path, title];
    for (final child in children) {
      out.addAll(child.flatten(path: next));
    }
    return out;
  }
}

/// 展平后的音频，供播放队列使用。
class AudioTrack {
  const AudioTrack({required this.node, this.folderPath = const []});

  final TrackNode node;
  final List<String> folderPath;

  String get title => node.title;
  String? get hash => node.hash;
  double get duration => node.duration ?? 0;
  bool get hasDuration => duration > 0;

  /// 目录层级展示文案，例如 `06：特典 / 03：闹钟音频`。
  String get folderLabel => folderPath.join(' / ');
}
