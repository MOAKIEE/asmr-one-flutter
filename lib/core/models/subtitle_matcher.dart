import 'track.dart';

/// Supported subtitle file extensions.
final RegExp _subtitleExtRe = RegExp(r'\.(lrc|srt|vtt)$', caseSensitive: false);

/// Known audio extensions that may precede a subtitle extension (e.g. `01.mp3.vtt`).
final RegExp _audioExtRe = RegExp(
  r'\.(mp3|wav|flac|m4a|aac|ogg|opus|wma|alac|aiff|mp4|webm)$',
  caseSensitive: false,
);

/// A subtitle attachment indexed from a work's original track tree.
class SubtitleAttachment {
  const SubtitleAttachment({required this.node, this.folderPath = const []});

  final TrackNode node;
  final List<String> folderPath;

  String get title => node.title;
  String? get hash => node.hash;
  String get folderLabel => folderPath.join(' / ');
  String get fullPath =>
      folderPath.isEmpty ? title : '${folderPath.join('/')}/$title';

  /// Stable identifier for caching and deduplication.
  String get attachmentId =>
      (node.hash != null && node.hash!.isNotEmpty) ? node.hash! : fullPath;
}

/// Shared index of a work's audio tracks and subtitle attachments from the raw tree.
class WorkTrackIndex {
  WorkTrackIndex({
    required this.workId,
    required this.audioTracks,
    required this.subtitles,
  });

  factory WorkTrackIndex.fromNodes(int workId, List<TrackNode> roots) {
    final audio = <AudioTrack>[];
    final subs = <SubtitleAttachment>[];

    void walk(List<TrackNode> nodes, List<String> path) {
      for (final node in nodes) {
        if (node.isAudio) {
          audio.add(AudioTrack(node: node, folderPath: path));
        } else if (node.isFolder || node.children.isNotEmpty) {
          walk(node.children, [...path, node.title]);
        } else if (isSupportedSubtitleFilename(node.title)) {
          subs.add(SubtitleAttachment(node: node, folderPath: path));
        }
      }
    }

    walk(roots, const []);
    return WorkTrackIndex(workId: workId, audioTracks: audio, subtitles: subs);
  }

  final int workId;
  final List<AudioTrack> audioTracks;
  final List<SubtitleAttachment> subtitles;

  static bool isSupportedSubtitleFilename(String title) =>
      _subtitleExtRe.hasMatch(title.trim());

  /// Locates the original audio track node by hash first, then by full folder + title.
  AudioTrack? findAudio({
    required int workId,
    String? hash,
    required String folderLabel,
    required String title,
  }) {
    if (workId != this.workId) return null;
    if (hash != null && hash.isNotEmpty) {
      for (final track in audioTracks) {
        if (track.hash == hash) return track;
      }
    }
    for (final track in audioTracks) {
      if (track.folderLabel == folderLabel && track.title == title) {
        return track;
      }
    }
    final normFolder = _normalizeSegmentText(folderLabel);
    final normTitle = _normalizeSegmentText(title);
    for (final track in audioTracks) {
      if (_normalizeSegmentText(track.folderLabel) == normFolder &&
          _normalizeSegmentText(track.title) == normTitle) {
        return track;
      }
    }
    return null;
  }
}

enum SubtitleMatchOutcome { matched, ambiguous, noMatch }

class SubtitleMatchResult {
  const SubtitleMatchResult._({
    required this.outcome,
    this.attachment,
    this.candidates = const [],
  });

  const SubtitleMatchResult.matched(SubtitleAttachment attachment)
    : this._(
        outcome: SubtitleMatchOutcome.matched,
        attachment: attachment,
        candidates: const [],
      );

  const SubtitleMatchResult.ambiguous(List<SubtitleAttachment> candidates)
    : this._(outcome: SubtitleMatchOutcome.ambiguous, candidates: candidates);

  const SubtitleMatchResult.noMatch()
    : this._(outcome: SubtitleMatchOutcome.noMatch);

  final SubtitleMatchOutcome outcome;
  final SubtitleAttachment? attachment;
  final List<SubtitleAttachment> candidates;
}

/// Canonical language bucket detected from subtitle paths or filenames.
enum _SubtitleLang { zhHans, zhHant, zh, ja, en, ko }

/// Matches a chapter audio track to its corresponding subtitle attachment within the same work.
class SubtitleMatcher {
  /// Increment whenever matching rules change so cached auto-matches re-evaluate.
  static const int ruleVersion = 1;

  static SubtitleMatchResult match({
    required WorkTrackIndex index,
    required AudioTrack audio,
    required String preferredLanguage,
  }) {
    if (index.subtitles.isEmpty) return const SubtitleMatchResult.noMatch();

    // Deduplicate identical attachments by attachmentId while preserving order.
    final seenIds = <String>{};
    final uniqueSubs = <SubtitleAttachment>[];
    for (final sub in index.subtitles) {
      if (seenIds.add(sub.attachmentId)) {
        uniqueSubs.add(sub);
      }
    }

    final audioInfo = _analyzeAudio(audio);
    final subInfos = uniqueSubs.map(_analyzeSubtitle).toList();

    // Tier 1: Same raw directory & same normalized stem.
    final tier1 = [
      for (final sub in subInfos)
        if (_listEquals(audioInfo.rawDir, sub.rawDir) &&
            audioInfo.normalizedStem.isNotEmpty &&
            audioInfo.normalizedStem == sub.normalizedStem)
          sub,
    ];
    if (tier1.isNotEmpty) {
      return _resolveCandidates(tier1, preferredLanguage);
    }

    // Tier 2: Same semantic group directory (stripping format/subtitle/language wrapper folders)
    // and same normalized stem.
    final tier2 = [
      for (final sub in subInfos)
        if (_listEquals(audioInfo.groupDir, sub.groupDir) &&
            audioInfo.normalizedStem.isNotEmpty &&
            audioInfo.normalizedStem == sub.normalizedStem)
          sub,
    ];
    if (tier2.isNotEmpty) {
      return _resolveCandidates(tier2, preferredLanguage);
    }

    // Tier 3: Unique matching chapter number within the same semantic group.
    if (audioInfo.chapterNumber != null) {
      final sameGroupAudios = index.audioTracks
          .map(_analyzeAudio)
          .where((other) => _listEquals(other.groupDir, audioInfo.groupDir))
          .toList();
      final chapterCountInGroup = sameGroupAudios
          .where((other) => other.chapterNumber == audioInfo.chapterNumber)
          .length;

      final tier3 = <_AnalyzedSubtitle>[];
      for (final sub in subInfos) {
        if (!_listEquals(audioInfo.groupDir, sub.groupDir)) continue;
        if (sub.chapterNumber != audioInfo.chapterNumber) continue;

        final audioHasTitle = audioInfo.descriptiveTitle.isNotEmpty;
        final subHasTitle = sub.descriptiveTitle.isNotEmpty;

        if (audioHasTitle && subHasTitle) {
          // Both carry descriptive titles: require them to match after normalization.
          if (audioInfo.descriptiveTitle != sub.descriptiveTitle) continue;
          tier3.add(sub);
        } else {
          // At least one side only has a chapter number: only allow when this chapter number
          // uniquely identifies the audio track within the group.
          if (chapterCountInGroup == 1) {
            tier3.add(sub);
          }
        }
      }
      if (tier3.isNotEmpty) {
        return _resolveCandidates(tier3, preferredLanguage);
      }
    }

    return const SubtitleMatchResult.noMatch();
  }

  static SubtitleMatchResult _resolveCandidates(
    List<_AnalyzedSubtitle> candidates,
    String preferredLanguage,
  ) {
    if (candidates.isEmpty) return const SubtitleMatchResult.noMatch();
    if (candidates.length == 1) {
      return SubtitleMatchResult.matched(candidates.single.attachment);
    }

    final pref = preferredLanguage.toLowerCase();
    var bestScore = -1;
    final best = <_AnalyzedSubtitle>[];

    for (final candidate in candidates) {
      final score = _languageScore(candidate.language, pref);
      if (score > bestScore) {
        bestScore = score;
        best
          ..clear()
          ..add(candidate);
      } else if (score == bestScore) {
        best.add(candidate);
      }
    }

    if (best.length == 1) {
      return SubtitleMatchResult.matched(best.single.attachment);
    }
    return SubtitleMatchResult.ambiguous(
      best.map((e) => e.attachment).toList(),
    );
  }

  static int _languageScore(_SubtitleLang? lang, String preferredLanguage) {
    if (lang == null) return 0;
    if (preferredLanguage.startsWith('zh')) {
      final preferHant =
          preferredLanguage.contains('tw') ||
          preferredLanguage.contains('hk') ||
          preferredLanguage.contains('hant');
      return switch (lang) {
        _SubtitleLang.zhHans => preferHant ? 2 : 3,
        _SubtitleLang.zhHant => preferHant ? 3 : 2,
        _SubtitleLang.zh => 2,
        _ => 0,
      };
    }
    if (preferredLanguage.startsWith('ja')) {
      return lang == _SubtitleLang.ja ? 3 : 0;
    }
    if (preferredLanguage.startsWith('en')) {
      return lang == _SubtitleLang.en ? 3 : 0;
    }
    return 0;
  }

  static _AnalyzedAudio _analyzeAudio(AudioTrack track) {
    final rawDir = track.folderPath
        .map(_normalizeSegmentText)
        .where((s) => s.isNotEmpty)
        .toList();
    final groupDir = <String>[];
    for (final segment in track.folderPath) {
      final parsed = _classifyFolderSegment(segment, isSubtitleSide: false);
      if (parsed.groupSegment.isNotEmpty) {
        groupDir.add(parsed.groupSegment);
      }
    }

    final stemRaw = _stripAudioExtension(track.title);
    final stemParsed = _parseFilenameStem(stemRaw, stripLanguageTags: false);

    return _AnalyzedAudio(
      rawDir: rawDir,
      groupDir: groupDir,
      normalizedStem: stemParsed.normalizedStem,
      chapterNumber: stemParsed.chapterNumber,
      descriptiveTitle: stemParsed.descriptiveTitle,
    );
  }

  static _AnalyzedSubtitle _analyzeSubtitle(SubtitleAttachment attachment) {
    final rawDir = attachment.folderPath
        .map(_normalizeSegmentText)
        .where((s) => s.isNotEmpty)
        .toList();
    final groupDir = <String>[];
    _SubtitleLang? folderLang;
    for (final segment in attachment.folderPath) {
      final parsed = _classifyFolderSegment(segment, isSubtitleSide: true);
      if (parsed.language != null) folderLang = parsed.language;
      if (parsed.groupSegment.isNotEmpty) {
        groupDir.add(parsed.groupSegment);
      }
    }

    var stemRaw = attachment.title.trim().replaceFirst(_subtitleExtRe, '');
    // Also strip a preceding audio extension like `01 耳かき.mp3.vtt`.
    stemRaw = _stripAudioExtension(stemRaw);
    final stemParsed = _parseFilenameStem(stemRaw, stripLanguageTags: true);

    return _AnalyzedSubtitle(
      attachment: attachment,
      rawDir: rawDir,
      groupDir: groupDir,
      normalizedStem: stemParsed.normalizedStem,
      chapterNumber: stemParsed.chapterNumber,
      descriptiveTitle: stemParsed.descriptiveTitle,
      language: stemParsed.language ?? folderLang,
    );
  }
}

class _AnalyzedAudio {
  const _AnalyzedAudio({
    required this.rawDir,
    required this.groupDir,
    required this.normalizedStem,
    required this.chapterNumber,
    required this.descriptiveTitle,
  });

  final List<String> rawDir;
  final List<String> groupDir;
  final String normalizedStem;
  final int? chapterNumber;
  final String descriptiveTitle;
}

class _AnalyzedSubtitle {
  const _AnalyzedSubtitle({
    required this.attachment,
    required this.rawDir,
    required this.groupDir,
    required this.normalizedStem,
    required this.chapterNumber,
    required this.descriptiveTitle,
    required this.language,
  });

  final SubtitleAttachment attachment;
  final List<String> rawDir;
  final List<String> groupDir;
  final String normalizedStem;
  final int? chapterNumber;
  final String descriptiveTitle;
  final _SubtitleLang? language;
}

class _FolderSegmentInfo {
  const _FolderSegmentInfo({required this.groupSegment, this.language});
  final String groupSegment;
  final _SubtitleLang? language;
}

class _StemInfo {
  const _StemInfo({
    required this.normalizedStem,
    required this.chapterNumber,
    required this.descriptiveTitle,
    this.language,
  });

  final String normalizedStem;
  final int? chapterNumber;
  final String descriptiveTitle;
  final _SubtitleLang? language;
}

String _stripAudioExtension(String name) {
  final trimmed = name.trim();
  if (_audioExtRe.hasMatch(trimmed)) {
    return trimmed.replaceFirst(_audioExtRe, '');
  }
  return trimmed;
}

/// Converts fullwidth ASCII / ideographic space to halfwidth ASCII and lowercases.
String _toHalfWidthLower(String input) {
  final buffer = StringBuffer();
  for (final code in input.codeUnits) {
    if (code == 0x3000) {
      buffer.writeCharCode(0x20);
    } else if (code >= 0xFF01 && code <= 0xFF5E) {
      buffer.writeCharCode(code - 0xFEE0);
    } else {
      buffer.writeCharCode(code);
    }
  }
  return buffer.toString().toLowerCase();
}

String _normalizeSegmentText(String raw) {
  final half = _toHalfWidthLower(raw);
  return _normalizeLeadingZeros(
    half.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

String _normalizeLeadingZeros(String input) => input.replaceAllMapped(
  RegExp(r'(?<![0-9])0+([0-9]+)'),
  (m) => m[1]!,
);

/// Format-only tokens that can be stripped from directory names when grouping.
const Set<String> _formatFolderTokens = {
  'mp3',
  'wav',
  'flac',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'alac',
  'wma',
  'aiff',
  'lossless',
  'hi-res',
  'hires',
  '16bit',
  '24bit',
  '320k',
  '320kbps',
  '256k',
  '192k',
  '128k',
  'audio',
  'mp3版',
  'wav版',
  'flac版',
  'aac版',
  '无损',
  '高音质',
  '高码率',
  '音频',
  '音源',
  '音轨',
  '音声',
  '音频格式',
  '格式',
  'lrc',
  'srt',
  'vtt',
};

/// Subtitle-container tokens stripped from subtitle directory names.
const Set<String> _subtitleFolderTokens = {
  'sub',
  'subs',
  'subtitle',
  'subtitles',
  'lyric',
  'lyrics',
  'caption',
  'captions',
  'lrc',
  'srt',
  'vtt',
  '字幕',
  '字幕文件',
  '字幕包',
  '外挂字幕',
  '歌词',
  '歌词文件',
  '台本字幕',
  '双语字幕',
  '字幕版',
  '带字幕',
};

final Map<String, _SubtitleLang> _languageTokens = {
  // Simplified Chinese
  '简中': _SubtitleLang.zhHans,
  '简体': _SubtitleLang.zhHans,
  '简体中文': _SubtitleLang.zhHans,
  '简字': _SubtitleLang.zhHans,
  '简中字幕': _SubtitleLang.zhHans,
  '简体字幕': _SubtitleLang.zhHans,
  'chs': _SubtitleLang.zhHans,
  'zh-cn': _SubtitleLang.zhHans,
  'zh_cn': _SubtitleLang.zhHans,
  'zh-hans': _SubtitleLang.zhHans,
  'zh_hans': _SubtitleLang.zhHans,
  'sc': _SubtitleLang.zhHans,
  'gb': _SubtitleLang.zhHans,
  // Traditional Chinese
  '繁中': _SubtitleLang.zhHant,
  '繁体': _SubtitleLang.zhHant,
  '繁体中文': _SubtitleLang.zhHant,
  '繁體': _SubtitleLang.zhHant,
  '繁體中文': _SubtitleLang.zhHant,
  '繁字': _SubtitleLang.zhHant,
  '繁中字幕': _SubtitleLang.zhHant,
  '繁体字幕': _SubtitleLang.zhHant,
  '繁體字幕': _SubtitleLang.zhHant,
  'cht': _SubtitleLang.zhHant,
  'zh-tw': _SubtitleLang.zhHant,
  'zh_tw': _SubtitleLang.zhHant,
  'zh-hk': _SubtitleLang.zhHant,
  'zh_hk': _SubtitleLang.zhHant,
  'zh-hant': _SubtitleLang.zhHant,
  'zh_hant': _SubtitleLang.zhHant,
  'tc': _SubtitleLang.zhHant,
  'big5': _SubtitleLang.zhHant,
  // Generic Chinese / Bilingual Chinese
  '中文': _SubtitleLang.zh,
  '中字': _SubtitleLang.zh,
  '中文字幕': _SubtitleLang.zh,
  '汉化': _SubtitleLang.zh,
  '汉化字幕': _SubtitleLang.zh,
  '中日': _SubtitleLang.zh,
  '日中': _SubtitleLang.zh,
  '中日双语': _SubtitleLang.zh,
  '中日字幕': _SubtitleLang.zh,
  'zh': _SubtitleLang.zh,
  'cn': _SubtitleLang.zh,
  'chinese': _SubtitleLang.zh,
  // Japanese
  '日文': _SubtitleLang.ja,
  '日语': _SubtitleLang.ja,
  '日語': _SubtitleLang.ja,
  '日字': _SubtitleLang.ja,
  '日文字幕': _SubtitleLang.ja,
  '日本語': _SubtitleLang.ja,
  '日本語字幕': _SubtitleLang.ja,
  'ja': _SubtitleLang.ja,
  'jp': _SubtitleLang.ja,
  'jpn': _SubtitleLang.ja,
  'ja-jp': _SubtitleLang.ja,
  'ja_jp': _SubtitleLang.ja,
  'japanese': _SubtitleLang.ja,
  // English
  '英文': _SubtitleLang.en,
  '英语': _SubtitleLang.en,
  '英語': _SubtitleLang.en,
  '英字': _SubtitleLang.en,
  '英文字幕': _SubtitleLang.en,
  'en': _SubtitleLang.en,
  'eng': _SubtitleLang.en,
  'en-us': _SubtitleLang.en,
  'en_us': _SubtitleLang.en,
  'en-gb': _SubtitleLang.en,
  'en_gb': _SubtitleLang.en,
  'english': _SubtitleLang.en,
  // Korean
  '韩文': _SubtitleLang.ko,
  '韩语': _SubtitleLang.ko,
  '韓文': _SubtitleLang.ko,
  '한국어': _SubtitleLang.ko,
  'ko': _SubtitleLang.ko,
  'kr': _SubtitleLang.ko,
  'kor': _SubtitleLang.ko,
  'korean': _SubtitleLang.ko,
};

/// Separators that divide filename or folder tokens without erasing content words.
final RegExp _separatorRe = RegExp(
  r'''[\s_\-\.·・,、:：;；/\\|~\u301C\u2013\u2014\u2015()\[\]{}【】「」『』<>《》]+''',
);

_FolderSegmentInfo _classifyFolderSegment(
  String segment, {
  required bool isSubtitleSide,
}) {
  final half = _toHalfWidthLower(segment).trim();
  if (half.isEmpty) return const _FolderSegmentInfo(groupSegment: '');

  // Check whole-segment language or container match first (handles `zh-cn`, `简中字幕`, etc.).
  final exactLang = _languageTokens[half];
  if (exactLang != null) {
    return _FolderSegmentInfo(groupSegment: '', language: exactLang);
  }
  if (_formatFolderTokens.contains(half) ||
      (isSubtitleSide && _subtitleFolderTokens.contains(half))) {
    return const _FolderSegmentInfo(groupSegment: '');
  }

  // Token-level filtering for composite wrapper folders like `字幕_简中`, `Disc 2 (MP3)`.
  // Preserve hyphenated locale tokens like `zh-cn` before splitting.
  final rawTokens = _tokenizePreservingLocales(half);
  final kept = <String>[];
  _SubtitleLang? lang;

  for (final token in rawTokens) {
    final tokenLang = _languageTokens[token];
    if (tokenLang != null) {
      lang ??= tokenLang;
      continue;
    }
    if (_formatFolderTokens.contains(token)) continue;
    if (isSubtitleSide && _subtitleFolderTokens.contains(token)) continue;
    kept.add(_normalizeLeadingZeros(token));
  }

  // Merge adjacent letter+number group tokens like `disc 2` / `cd 1` consistently:
  // `disc2` and `disc 2` both become `disc 2`.
  final normalized = _normalizeGroupTokens(kept);
  return _FolderSegmentInfo(groupSegment: normalized, language: lang);
}

String _normalizeGroupTokens(List<String> tokens) {
  if (tokens.isEmpty) return '';
  final expanded = <String>[];
  final discPrefix = RegExp(r'^(disc|cd|part|vol|volume)(\d+)$');
  for (final token in tokens) {
    final m = discPrefix.firstMatch(token);
    if (m != null) {
      expanded.add(m[1]!);
      expanded.add(_normalizeLeadingZeros(m[2]!));
    } else {
      expanded.add(token);
    }
  }
  return expanded.join(' ');
}

List<String> _tokenizePreservingLocales(String half) {
  final protected = half.replaceAllMapped(
    RegExp(r'\b(zh|ja|en)[-_](cn|tw|hk|hans|hant|jp|us|gb)\b'),
    (m) => '${m[1]}__${m[2]}',
  );
  return protected
      .split(_separatorRe)
      .where((t) => t.isNotEmpty)
      .map((t) => t.replaceAll('__', '-'))
      .toList();
}

_StemInfo _parseFilenameStem(
  String rawStem, {
  required bool stripLanguageTags,
}) {
  var working = _toHalfWidthLower(rawStem).trim();
  _SubtitleLang? lang;

  if (stripLanguageTags) {
    // 1. Strip bracketed language tags like `[简中]`, `(JP)`, `【中文字幕】`.
    working = working.replaceAllMapped(
      RegExp(r'[\(\[\{【「『《]\s*([^\)\]\}\】」』》]+?)\s*[\)\]\}】」』》]'),
      (match) {
        final inner = match[1]!.trim();
        final detected = _detectPureLanguageOrSubTag(inner);
        if (detected != null) {
          lang ??= detected.language;
          return ' ';
        }
        return match[0]!;
      },
    );

    // 2. Strip trailing language tag separated by `.`, `_`, `-`, or space, e.g. `01 耳かき.zh-cn`, `01_chs`.
    var changed = true;
    while (changed) {
      changed = false;
      final suffixMatch = RegExp(
        r'(?:^|[\s._\-])([a-z]{2}(?:[-_][a-z]{2,4})?|chs|cht|jpn|eng|kor|简中|简体|简体中文|简字|简中字幕|繁中|繁体|繁体中文|繁體|繁體中文|繁字|繁中字幕|中文|中字|中文字幕|日文|日语|日語|日字|日文字幕|日本語|日本語字幕|英文|英语|英語|英字|英文字幕|韩文|韩语|한국어|中日|日中|中日双语|中日字幕|双语字幕|字幕)$',
      ).firstMatch(working);
      if (suffixMatch != null) {
        final token = suffixMatch[1]!;
        final prefix = working.substring(0, suffixMatch.start).trim();
        // Do not strip if it would erase the entire filename.
        if (prefix.isNotEmpty) {
          final detected = _detectPureLanguageOrSubTag(token);
          if (detected != null) {
            lang ??= detected.language;
            working = prefix;
            changed = true;
          }
        }
      }
    }
  }

  final tokens = _tokenizePreservingLocales(
    working,
  ).map(_normalizeLeadingZeros).toList();
  final normalizedStem = tokens.join(' ');

  final chapter = _extractChapterAndTitle(working);
  return _StemInfo(
    normalizedStem: normalizedStem,
    chapterNumber: chapter.number,
    descriptiveTitle: chapter.descriptiveTitle,
    language: lang,
  );
}

class _LangTagMatch {
  const _LangTagMatch(this.language);
  final _SubtitleLang? language;
}

_LangTagMatch? _detectPureLanguageOrSubTag(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  final exact = _languageTokens[cleaned];
  if (exact != null) return _LangTagMatch(exact);
  if (_subtitleFolderTokens.contains(cleaned)) {
    return const _LangTagMatch(null);
  }
  final parts = _tokenizePreservingLocales(cleaned);
  if (parts.isEmpty) return null;
  _SubtitleLang? lang;
  for (final part in parts) {
    final partLang = _languageTokens[part];
    if (partLang != null) {
      lang ??= partLang;
      continue;
    }
    if (_subtitleFolderTokens.contains(part)) continue;
    // Contains a non-language/non-subtitle word (e.g. `无声效`, `特典`, `左声道`): keep it!
    return null;
  }
  return _LangTagMatch(lang);
}

class _ChapterExtraction {
  const _ChapterExtraction({this.number, required this.descriptiveTitle});
  final int? number;
  final String descriptiveTitle;
}

_ChapterExtraction _extractChapterAndTitle(String halfLowerStem) {
  final trimmed = halfLowerStem.trim();
  if (trimmed.isEmpty) {
    return const _ChapterExtraction(descriptiveTitle: '');
  }

  // Pattern A: Prefix + chapter number, e.g. `track 01 ...`, `tr.02 ...`, `ch03 ...`, `第01话 ...`, `#04 ...`
  final patterns = <RegExp>[
    RegExp(
      r'^(?:track|tr|ch|chap|chapter|no|ep|episode|part|scene|act|#|＃)[\s._\-]*(\d{1,4})(?:$|[\s._\-:：、·・()\[\]【】「」『』]+(.*)$|(?=[^\da-z])(.*)$)',
    ),
    RegExp(
      r'^第\s*(\d{1,4})\s*(?:章|话|話|回|节|節|幕|部|トラック|話目)(?:$|[\s._\-:：、·・()\[\]【】「」『』]*(.*)$)',
    ),
    RegExp(
      r'^(\d{1,4})(?:$|[\s._\-:：、·・()\[\]【】「」『』]+(.*)$|(?=[^\da-z])(.*)$)',
    ),
  ];

  for (final re in patterns) {
    final m = re.firstMatch(trimmed);
    if (m != null) {
      final numValue = int.tryParse(m[1]!);
      if (numValue != null) {
        final rest = m.groupCount >= 3
            ? (m[2] ?? m[3] ?? '')
            : (m.groupCount >= 2 ? (m[2] ?? '') : '');
        final titleTokens = _tokenizePreservingLocales(
          rest,
        ).map(_normalizeLeadingZeros).toList();
        return _ChapterExtraction(
          number: numValue,
          descriptiveTitle: titleTokens.join(' '),
        );
      }
    }
  }

  return _ChapterExtraction(
    descriptiveTitle: _tokenizePreservingLocales(
      trimmed,
    ).map(_normalizeLeadingZeros).toList().join(' '),
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
